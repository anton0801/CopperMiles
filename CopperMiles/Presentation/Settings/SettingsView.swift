import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Preferences, and the traveller's own data.
struct SettingsView: View {
  @EnvironmentObject private var environment: AppEnvironment

  @State private var share: SharePayload?
  @State private var isImporting = false
  @State private var importCandidate: ImportCandidate?
  @State private var isDeletingEverything = false
  @State private var isShowingExportOptions = false
  @State private var remindersToReview: [UUID] = []

  var body: some View {
    CMScreen {
      header
      preferences
      journalData
      reviewReminders
      dangerZone
      about
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $share) { ShareSheet(items: $0.items) }
    .sheet(isPresented: $isShowingExportOptions) { ExportOptionsSheet() }
    .sheet(item: $importCandidate) { candidate in
      ImportPreviewSheet(candidate: candidate) { tripsToReview in
        importCandidate = nil
        remindersToReview = tripsToReview
      }
    }
    .sheet(isPresented: $isDeletingEverything) { DeleteEverythingSheet() }
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.zip]) { result in
      readBackup(result)
    }
  }

  // MARK: - Sections

  private var header: some View {
    CMScreenHeader(
      eyebrow: "Make yourself at home",
      title: "The little details",
      subtitle: "Your journal, just the way you like it."
    )
  }

  private var preferences: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(title: "Preferences")

      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMSegmentedPicker(
          options: DistanceUnit.allCases,
          title: \.longName,
          selection: setting(\.reportUnit)
        )
        CMHint(
          text: "Reports are shown in this unit. Each vehicle keeps its own readings exactly as recorded."
        )
      }

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMToggleRow(title: "24-hour time", isOn: setting(\.uses24HourTime))
          CMDivider()
          CMToggleRow(
            title: "Reduce motion",
            hint: "Turns off the app's transitions, on top of whatever iOS is set to.",
            isOn: setting(\.prefersReducedMotion)
          )
        }
      }
    }
  }

  private var journalData: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(title: "Your journal")

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMNavigationRow(
            icon: "archivebox",
            title: "Archived records",
            detail: archivedDetail
          ) {
            ArchivedRecordsView()
          }

          CMDivider()

          CMActionRow(
            icon: "slider.horizontal.3",
            title: "Export options",
            detail: exportOptionsDetail
          ) {
            isShowingExportOptions = true
          }

          CMDivider()

          CMActionRow(
            icon: "square.and.arrow.up",
            title: "Export a full backup",
            detail: "A ZIP with everything, photos included"
          ) {
            exportBackup()
          }

          CMDivider()

          CMActionRow(
            icon: "square.and.arrow.down",
            title: "Import a backup",
            detail: environment.activeTrip == nil ? "Replaces this journal" : "Unavailable right now"
          ) {
            isImporting = true
          }
          .disabled(environment.activeTrip != nil)
        }
      }

      CMHint(
        text: "A full backup carries every address, coordinate and photo, so it can restore your journal completely. Keep the file somewhere private.",
        icon: "lock.shield"
      )

      if environment.activeTrip != nil {
        CMHint(
          text: "Finish the trip under way before replacing your journal.",
          icon: "info.circle"
        )
      }
    }
  }

  @ViewBuilder
  private var reviewReminders: some View {
    if !remindersToReview.isEmpty {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMSectionHeader(title: "Review your reminders")

        CMHint(
          text: "Nothing was scheduled automatically after the import. Open each trip to check its times and switch them on.",
          icon: "bell.badge"
        )

        CMCard(padding: 0) {
          VStack(spacing: 0) {
            ForEach(Array(remindersToReview.enumerated()), id: \.element) { index, tripID in
              CMNavigationRow(
                icon: "bell",
                title: environment.trip(tripID)?.name ?? "Trip"
              ) {
                RemindersView(tripID: tripID)
              }
              if index < remindersToReview.count - 1 {
                CMDivider()
              }
            }
          }
        }
      }
    }
  }

  private var dangerZone: some View {
    CMCard(padding: 0) {
      VStack(spacing: 0) {
        CMActionRow(
          icon: "arrow.counterclockwise",
          title: "Meet Pip again",
          detail: "Replays the introduction. Nothing is deleted."
        ) {
          environment.updateSettings { $0.hasSeenOnboarding = false }
        }

        CMDivider()

        CMActionRow(icon: "trash", title: "Delete all data", isDestructive: true) {
          isDeletingEverything = true
        }
      }
    }
  }

  private var about: some View {
    VStack(spacing: Theme.Spacing.small) {
      Text("Copper Miles")
        .font(Font.CM.cardTitle)
        .foregroundColor(Theme.Colour.primaryText)

      Text("Made for the journey. And the little things.")
        .font(Font.CM.footnote)
        .foregroundColor(Theme.Colour.secondaryText)

      Label("No account. No cloud. Just your road.", systemImage: "lock.shield")
        .font(Font.CM.caption)
        .foregroundColor(Theme.Colour.secondaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Theme.Spacing.large)
    .accessibilityElement(children: .combine)
  }

  // MARK: - Helpers

  /// A two-way binding onto one preference.
  private func setting<Value>(
    _ keyPath: WritableKeyPath<AppSettings, Value>
  ) -> Binding<Value> {
    Binding(
      get: { environment.settings[keyPath: keyPath] },
      set: { value in environment.updateSettings { $0[keyPath: keyPath] = value } }
    )
  }

  private var archivedDetail: String {
    let records = environment.useCases.findArchivedRecords.execute()
    if records.isEmpty { return "Nothing archived" }
    var parts: [String] = []
    if !records.vehicles.isEmpty { parts.append("\(records.vehicles.count) vehicles") }
    if !records.trips.isEmpty { parts.append("\(records.trips.count) trips") }
    return parts.joined(separator: " · ")
  }

  private var exportOptionsDetail: String {
    let options = environment.settings.exportOptions
    var included: [String] = []
    if options.includesAddresses { included.append("addresses") }
    if options.includesCoordinates { included.append("coordinates") }
    if options.includesPhotos { included.append("photos") }
    return included.isEmpty ? "Nothing extra included" : "Includes \(included.joined(separator: ", "))"
  }

  // MARK: - Backup

  private func exportBackup() {
    environment.perform {
      let data = try environment.useCases.exportBackup.execute()
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CopperMiles-backup.zip")
      try data.write(to: url, options: .atomic)
      share = SharePayload(items: [url])
    }
  }

  private func readBackup(_ result: Result<URL, Error>) {
    environment.perform {
      let url = try result.get()

      // A file handed over by the document picker lives outside the sandbox and has
      // to be opened while its security scope is held.
      let isScoped = url.startAccessingSecurityScopedResource()
      defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

      let data = try Data(contentsOf: url)
      let candidate = try environment.useCases.readBackup.execute(data)
      importCandidate = ImportCandidate(candidate: candidate)
    }
  }
}

/// A backup that has been read and is waiting for the traveller's decision.
struct ImportCandidate: Identifiable {
  let id = UUID()
  let candidate: ReadBackup.Candidate
}

/// Shows what an archive holds before anything is replaced.
struct ImportPreviewSheet: View {
  let candidate: ImportCandidate
  let onImported: ([UUID]) -> Void

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  private var preview: ReadBackup.Preview { candidate.candidate.preview }

  var body: some View {
    CMEditorSheet(
      title: "Import preview",
      saveTitle: "Back up mine, then replace",
      saveIcon: "arrow.down.doc",
      onSave: replace,
      onCancel: { dismiss() }
    ) {
      CMScreenHeader(
        eyebrow: "Backup checked",
        title: "Bring this journal over",
        subtitle: "Everything in the archive was read and checked. Nothing has changed yet."
      )

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMInfoRow(icon: "car", title: "Vehicles", value: "\(preview.vehicles)")
          CMDivider()
          CMInfoRow(icon: "map", title: "Trips", value: "\(preview.trips)")
          CMDivider()
          CMInfoRow(icon: "mappin", title: "Stops", value: "\(preview.stops)")
          CMDivider()
          CMInfoRow(icon: "note.text", title: "Notes", value: "\(preview.notes)")
          CMDivider()
          CMInfoRow(icon: "photo", title: "Photos", value: "\(preview.photos)")
        }
      }

      CMHint(
        text: "This replaces your current journal. A copy of what you have now is saved first, in the app's Documents folder, where you can find it in Files.",
        icon: "exclamationmark.circle",
        tone: .warning
      )

      CMHint(
        text: "Reminders are not switched on again automatically. The trips that had them are listed afterwards so you can check their times."
      )
    }
  }

  private func replace() {
    let outcome = environment.performReturning {
      let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      return try environment.useCases.importBackup.execute(
        candidate.candidate,
        safetyCopyDirectory: directory
      )
    }
    guard let outcome else { return }

    onImported(outcome.tripsToReview)
    dismiss()
  }
}

/// Chooses what a shared trip carries by default.
struct ExportOptionsSheet: View {
  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    CMEditorSheet(
      title: "Export options",
      saveTitle: "Done",
      onSave: { dismiss() },
      onCancel: { dismiss() }
    ) {
      CMScreenHeader(
        eyebrow: "What gets shared",
        title: "Your defaults",
        subtitle: "These are the starting settings when you export a trip. Every export shows a preview first."
      )

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMToggleRow(title: "Include addresses", isOn: option(\.includesAddresses))
          CMDivider()
          CMToggleRow(title: "Include coordinates", isOn: option(\.includesCoordinates))
          CMDivider()
          CMToggleRow(title: "Include photos in the PDF", isOn: option(\.includesPhotos))
        }
      }

      CMHint(
        text: "All three are off to begin with. A shared trip is a story about the road, not a map of where you are.",
        icon: "lock.shield"
      )

      CMHint(
        text: "A full backup always carries everything, so it can restore your journal. It is labelled as such."
      )
    }
  }

  private func option(_ keyPath: WritableKeyPath<ExportOptions, Bool>) -> Binding<Bool> {
    Binding(
      get: { environment.settings.exportOptions[keyPath: keyPath] },
      set: { value in
        environment.updateSettings { $0.exportOptions[keyPath: keyPath] = value }
      }
    )
  }
}

/// The last gate before everything goes.
struct DeleteEverythingSheet: View {
  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var confirmation = ""

  var body: some View {
    CMEditorSheet(
      title: "Delete all data",
      saveTitle: "Delete everything",
      saveIcon: "trash",
      isSaveEnabled: confirmation.trimmed.uppercased() == DeleteAllData.confirmationPhrase,
      onSave: deleteEverything,
      onCancel: { dismiss() }
    ) {
      CMScreenHeader(
        eyebrow: "This cannot be undone",
        title: "Delete everything?"
      )

      CMCard {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
          Text(summary)
            .font(Font.CM.body)
            .foregroundColor(Theme.Colour.danger)
            .fixedSize(horizontal: false, vertical: true)

          Text("Every local reminder is cancelled too.")
            .font(Font.CM.footnote)
            .foregroundColor(Theme.Colour.secondaryText)
        }
      }

      CMHint(text: "Export a backup first if there is any chance you will want this back.")

      CMTextField(
        title: "Type DELETE to confirm",
        text: $confirmation,
        placeholder: "DELETE",
        isRequired: true,
        capitalisation: .characters
      )
    }
  }

  private var summary: String {
    let journal = environment.journal
    let photos = journal.referencedAttachmentIDs.count
    return "This removes \(journal.vehicles.count) vehicles, \(journal.trips.count) trips and \(photos) photos."
  }

  private func deleteEverything() {
    let didDelete = environment.perform {
      try environment.useCases.deleteAllData.execute(confirmation: confirmation)
    }
    if didDelete { dismiss() }
  }
}

/// Records the traveller has tidied away.
struct ArchivedRecordsView: View {
  @EnvironmentObject private var environment: AppEnvironment

  private var records: FindArchivedRecords.Records {
    environment.useCases.findArchivedRecords.execute()
  }

  var body: some View {
    CMScreen {
      CMScreenHeader(
        eyebrow: "Put away, not lost",
        title: "Archived records",
        subtitle: "Archived records stay out of your everyday lists and out of reports, until you bring them back."
      )

      if records.isEmpty {
        CMEmptyState(
          illustration: .roadNotebook,
          illustrationSize: 96,
          title: "Nothing archived",
          message: "Everything you have is in the everyday lists."
        )
      } else {
        if !records.vehicles.isEmpty {
          VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            CMSectionHeader(title: "Vehicles", detail: "\(records.vehicles.count)")

            CMRowList(elements: records.vehicles) { vehicle in
              HStack(spacing: Theme.Spacing.medium) {
                Text(vehicle.name)
                  .font(Font.CM.label)
                  .foregroundColor(Theme.Colour.primaryText)
                Spacer()
                CMButton(title: "Restore", prominence: .secondary, fillsWidth: false) {
                  environment.perform {
                    try environment.useCases.setVehicleArchived.execute(
                      vehicle.id,
                      isArchived: false
                    )
                  }
                }
              }
              .padding(.horizontal, Theme.Spacing.cardPadding)
              .padding(.vertical, Theme.Spacing.small)
            }
          }
        }

        if !records.trips.isEmpty {
          VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            CMSectionHeader(title: "Trips", detail: "\(records.trips.count)")

            CMRowList(elements: records.trips) { trip in
              HStack(spacing: Theme.Spacing.medium) {
                VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                  Text(trip.name)
                    .font(Font.CM.label)
                    .foregroundColor(Theme.Colour.primaryText)
                  Text(trip.actualStart.map(environment.formatters.day) ?? "")
                    .font(Font.CM.footnote)
                    .foregroundColor(Theme.Colour.secondaryText)
                }
                Spacer()
                CMButton(title: "Restore", prominence: .secondary, fillsWidth: false) {
                  environment.perform {
                    try environment.useCases.setTripArchived.execute(
                      tripID: trip.id,
                      isArchived: false
                    )
                  }
                }
              }
              .padding(.horizontal, Theme.Spacing.cardPadding)
              .padding(.vertical, Theme.Spacing.small)
            }
          }
        }
      }
    }
    .navigationTitle("Archived")
    .navigationBarTitleDisplayMode(.inline)
  }
}
