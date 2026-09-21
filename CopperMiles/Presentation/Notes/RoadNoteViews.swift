import SwiftUI

/// Holds a road note while it is being written.
///
/// Newly chosen photos are kept as bytes here and only stored when the note saves,
/// so cancelling leaves nothing behind on disk.
@MainActor
final class RoadNoteEditorModel: ObservableObject {
  @Published var note: RoadNote
  @Published var addedPhotos: [Data] = []

  init(note: RoadNote) {
    self.note = note
  }

  var totalPhotoCount: Int {
    note.photoIDs.count + addedPhotos.count
  }

  var canAddPhoto: Bool {
    totalPhotoCount < RoadNote.maximumPhotos
  }

  func addPhoto(_ data: Data) {
    guard canAddPhoto else { return }
    addedPhotos.append(data)
  }

  func removeStoredPhoto(_ id: AttachmentID) {
    note.photoIDs.removeAll { $0 == id }
  }

  func removeAddedPhoto(at index: Int) {
    guard addedPhotos.indices.contains(index) else { return }
    addedPhotos.remove(at: index)
  }
}

/// The form for a road note.
struct RoadNoteEditorSheet: View {
  let tripID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @StateObject private var model: RoadNoteEditorModel

  @State private var isChoosingPhoto = false
  @State private var isTakingPhoto = false
  @State private var isConfirmingCancel = false

  init(tripID: UUID, note: RoadNote) {
    self.tripID = tripID
    _model = StateObject(wrappedValue: RoadNoteEditorModel(note: note))
  }

  private var trip: Trip? { environment.trip(tripID) }

  /// The picker must not offer a time the validator would then refuse: on a trip
  /// already brought home, that is its end rather than this moment.
  private var latestAllowedDate: Date {
    min(trip?.actualEnd ?? environment.dates.now, environment.dates.now)
  }

  private var stopOptions: [UUID?] {
    [nil] + (trip?.activeStops.map { Optional($0.id) } ?? [])
  }

  var body: some View {
    CMEditorSheet(
      title: "A little road memory",
      saveTitle: "Save note",
      onSave: save,
      onCancel: { isConfirmingCancel = true }
    ) {
      header
      details
      photos
      pinning
    }
    .sheet(isPresented: $isChoosingPhoto) {
      PhotoLibraryPicker(
        onPicked: { model.addPhoto($0) },
        onFailed: { environment.show(.error($0)) }
      )
    }
    .sheet(isPresented: $isTakingPhoto) {
      CameraPicker(onPicked: { model.addPhoto($0) })
    }
    .confirmationDialog(
      "Keep this memory?",
      isPresented: $isConfirmingCancel,
      titleVisibility: .visible
    ) {
      Button("Save note") { save() }
      Button("Discard", role: .destructive) { dismiss() }
      Button("Keep writing", role: .cancel) {}
    }
  }

  // MARK: - Sections

  private var header: some View {
    CMScreenHeader(
      eyebrow: "Worth remembering",
      title: "Keep the little things."
    ) {
      CMAsset(.roadNotebook, width: 64, height: 64)
    }
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      CMMenuPicker(
        title: "What is this about",
        options: RoadNoteKind.allCases,
        optionTitle: \.displayName,
        selection: $model.note.kind
      )

      CMTextEditor(
        title: "Your note",
        text: $model.note.text,
        isRequired: true,
        minimumHeight: 140,
        characterLimit: RoadNote.maximumCharacters
      )

      CMDateField(
        title: "Recorded at",
        isRequired: true,
        date: $model.note.recordedAt,
        range: ...latestAllowedDate,
        hint: "This sits inside the trip, between setting off and coming home."
      )

      if stopOptions.count > 1 {
        CMMenuPicker(
          title: "Related stop",
          options: stopOptions,
          optionTitle: { id in
            guard let id else { return "The whole trip" }
            return trip?.stop(id)?.name ?? "Unknown stop"
          },
          selection: $model.note.stopID
        )
      }
    }
  }

  private var photos: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(
        title: "Photos",
        detail: "\(model.totalPhotoCount) of \(RoadNote.maximumPhotos)"
      )

      ForEach(model.note.photoIDs, id: \.self) { id in
        photoRow {
          CMPhoto(id: id)
        } onRemove: {
          model.removeStoredPhoto(id)
        }
      }

      ForEach(Array(model.addedPhotos.enumerated()), id: \.offset) { index, data in
        photoRow {
          if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
          }
        } onRemove: {
          model.removeAddedPhoto(at: index)
        }
      }

      if model.canAddPhoto {
        HStack(spacing: Theme.Spacing.medium) {
          CMButton(
            title: "Choose",
            icon: "photo",
            prominence: .secondary,
            fillsWidth: false
          ) {
            isChoosingPhoto = true
          }

          CMButton(
            title: "Take one",
            icon: "camera",
            prominence: .secondary,
            fillsWidth: false
          ) {
            Task { await requestCamera() }
          }

          Spacer()
        }

        CMHint(text: "Your words are saved whether or not a photo comes with them.")
      }
    }
  }

  private func photoRow<Content: View>(
    @ViewBuilder _ content: () -> Content,
    onRemove: @escaping () -> Void
  ) -> some View {
    VStack(spacing: Theme.Spacing.small) {
      content()
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

      HStack {
        CMButton(title: "Remove photo", icon: "trash", prominence: .destructive, fillsWidth: false) {
          onRemove()
        }
        Spacer()
      }
    }
  }

  private var pinning: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      CMCard(padding: 0) {
        CMToggleRow(
          title: "Pin for a future trip",
          hint: "A pinned note can be carried into a repeat of this plan as a written hint.",
          isOn: $model.note.isPinnedForRepeat
        )
      }
      CMHint(text: "A pinned note never becomes an event in the new trip. It is only advice.")
    }
  }

  // MARK: - Actions

  private func requestCamera() async {
    switch await CameraAccess.request() {
    case .granted:
      isTakingPhoto = true
    case .denied:
      environment.show(
        .error("Camera access is off. You can keep writing, or choose a photo instead.")
      )
    case .unavailable:
      environment.show(
        .error("This device has no camera. You can choose a photo instead.")
      )
    }
  }

  private func save() {
    let didSave = environment.perform {
      try environment.useCases.saveRoadNote.execute(
        tripID: tripID,
        note: model.note,
        addedPhotos: model.addedPhotos
      )
    }
    if didSave { dismiss() }
  }
}

/// One note, as it appears in a list.
struct RoadNoteCard: View {
  let note: RoadNote
  var lineLimit: Int = 4

  @EnvironmentObject private var environment: AppEnvironment

  var body: some View {
    CMCard {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        HStack {
          CMTag(text: note.kind.displayName)
          Spacer()
          if note.isPinnedForRepeat {
            Image(systemName: "pin.fill")
              .font(.system(.caption))
              .foregroundColor(Theme.Colour.accent)
              .accessibilityLabel("Pinned for a future trip")
          }
        }

        Text(note.text)
          .font(Font.CM.callout)
          .foregroundColor(Theme.Colour.primaryText)
          .lineLimit(lineLimit)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        if let first = note.photoIDs.first {
          CMPhoto(id: first)
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }

        Text(environment.formatters.dateAndTime(note.recordedAt))
          .font(Font.CM.caption)
          .foregroundColor(Theme.Colour.secondaryText)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// One note in full.
struct RoadNoteDetailView: View {
  let tripID: UUID
  let noteID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var isEditing = false
  @State private var isConfirmingDelete = false

  private var note: RoadNote? {
    environment.trip(tripID)?.notes.first { $0.id == noteID }
  }

  var body: some View {
    Group {
      if let note {
        content(note)
      } else {
        CMScreen {
          CMEmptyState(
            illustration: .roadNotebook,
            title: "This note is gone",
            message: "It is no longer in your journal."
          )
        }
      }
    }
    .navigationTitle("Road memory")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func content(_ note: RoadNote) -> some View {
    CMScreen {
      HStack {
        CMTag(text: note.kind.displayName)
        if note.isPinnedForRepeat {
          CMTag(text: "Pinned", colour: Theme.Colour.accent)
        }
        Spacer()
      }

      Text(note.text)
        .font(Font.CM.body)
        .foregroundColor(Theme.Colour.primaryText)
        .fixedSize(horizontal: false, vertical: true)

      Text(environment.formatters.fullDateAndTime(note.recordedAt))
        .font(Font.CM.footnote)
        .foregroundColor(Theme.Colour.secondaryText)

      if let stopID = note.stopID, let stop = environment.trip(tripID)?.stop(stopID) {
        CMCard(padding: 0) {
          CMNavigationRow(icon: stop.kind.icon, title: stop.name, detail: "The stop this belongs to") {
            StopDetailView(tripID: tripID, stopID: stopID)
          }
        }
      }

      ForEach(note.photoIDs, id: \.self) { id in
        CMPhoto(id: id, contentMode: .fit)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
      }

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMActionRow(icon: "pencil", title: "Edit this note") { isEditing = true }
          CMDivider()
          CMActionRow(icon: "trash", title: "Delete this note", isDestructive: true) {
            isConfirmingDelete = true
          }
        }
      }
    }
    .sheet(isPresented: $isEditing) {
      RoadNoteEditorSheet(tripID: tripID, note: note)
    }
    .alert("Delete this note?", isPresented: $isConfirmingDelete) {
      Button("Delete", role: .destructive) {
        let didDelete = environment.perform {
          try environment.useCases.deleteRoadNote.execute(tripID: tripID, noteID: noteID)
        }
        if didDelete { dismiss() }
      }
      Button("Keep note", role: .cancel) {}
    } message: {
      Text(
        note.photoIDs.isEmpty
          ? "The note is removed from your journal."
          : "The note and its \(note.photoIDs.count) photos are removed from your journal."
      )
    }
  }
}
