import SwiftUI

/// The last look before setting off.
///
/// Confirming records the actual start and turns the plan into a journey in one
/// step, so a second tap cannot open a second session.
struct StartTripSheet: View {
  let tripID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var actualStart = Date()
  @State private var odometerText = ""
  @State private var explanation: OdometerExplanation = .correctedReading
  @State private var isConfirmingOpenItems = false
  @State private var hasLoaded = false

  private var trip: Trip? { environment.trip(tripID) }

  var body: some View {
    Group {
      if let trip {
        content(trip)
      } else {
        CMEditorSheet(
          title: "One last look",
          saveTitle: "Close",
          onSave: { dismiss() },
          onCancel: { dismiss() }
        ) {
          CMEmptyState(
            illustration: .pipHome,
            title: "This trip is gone",
            message: "It is no longer in your journal."
          )
        }
      }
    }
    .onAppear {
      // Only on first appearance, so returning to this sheet does not overwrite a
      // start time the traveller has already picked.
      guard !hasLoaded else { return }
      hasLoaded = true
      actualStart = environment.dates.now
    }
  }

  private func content(_ trip: Trip) -> some View {
    CMEditorSheet(
      title: "One last look",
      saveTitle: "Set off",
      onSave: { attemptStart(trip) },
      onCancel: { dismiss() }
    ) {
      header
      summary(trip)
      startTime
      odometer(trip)
      openItems(trip)
      otherActiveTrip(trip)
    }
    .alert("Set off with open checks?", isPresented: $isConfirmingOpenItems) {
      Button("Set off anyway") { start(allowingOpenItems: true) }
      Button("Back to the checklist", role: .cancel) {}
    } message: {
      Text(openItemsMessage(trip))
    }
  }

  // MARK: - Sections

  private var header: some View {
    CMScreenHeader(
      eyebrow: "Your trip is waiting",
      title: "Looking good."
    ) {
      CMAsset(.pipHome, width: 64, height: 73)
    }
  }

  private func summary(_ trip: Trip) -> some View {
    CMCard(padding: 0) {
      VStack(spacing: 0) {
        CMInfoRow(icon: "map", title: "Trip", value: trip.name)
        CMDivider()
        CMInfoRow(
          icon: "car.fill",
          title: "Vehicle",
          value: environment.vehicleName(trip.vehicleID)
        )
        CMDivider()
        CMInfoRow(
          icon: "calendar",
          title: "Planned departure",
          value: trip.plannedDeparture.map(environment.formatters.fullDateAndTime) ?? "—"
        )
        CMDivider()
        CMInfoRow(icon: "mappin", title: "Stops", value: "\(trip.activeStops.count)")
        CMDivider()
        CMInfoRow(
          icon: "checklist",
          title: "Preparation",
          value: checklistValue(trip)
        )
      }
    }
  }

  private func checklistValue(_ trip: Trip) -> String {
    let progress = trip.checklistProgress
    return progress.isEmpty ? "No checklist" : "\(progress.checked) of \(progress.total)"
  }

  private var startTime: some View {
    CMDateField(
      title: "Actual start",
      isRequired: true,
      date: $actualStart,
      range: ...environment.dates.now,
      hint: "This is when the journey really began. It cannot be in the future."
    )
  }

  private func odometer(_ trip: Trip) -> some View {
    let unit = environment.unit(forTrip: trip)
    let previous = environment.journal.latestOdometerReading(forVehicle: trip.vehicleID)

    return VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMTextField(
        title: "Start odometer in \(unit.shortName)",
        text: $odometerText,
        placeholder: "Optional",
        keyboard: .decimalPad
      )

      if let previous {
        CMHint(
          text: "Last recorded: \(environment.formatters.odometer(previous.value, unit: unit)) on \(environment.formatters.day(previous.recordedAt))."
        )
      }

      if needsExplanation(previous) {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
          CMHint(
            text: "That is below the last reading for this vehicle. Which is it?",
            icon: "exclamationmark.circle",
            tone: .warning
          )
          CMSegmentedPicker(
            options: OdometerExplanation.allCases,
            title: \.displayName,
            selection: $explanation
          )
        }
      }
    }
  }

  /// Whether the typed reading sits below what this vehicle last recorded.
  ///
  /// Checked as the traveller types so the explanation appears with the problem,
  /// rather than as a refusal after they tap Set off.
  private func needsExplanation(_ previous: Journal.OdometerRecord?) -> Bool {
    // `try?` on a throwing function that already returns an optional flattens to one
    // level, so an empty field and an unreadable one both arrive here as `nil`.
    guard let previous, let reading = try? OdometerValidator.reading(odometerText) else {
      return false
    }
    return reading < previous.value
  }

  @ViewBuilder
  private func openItems(_ trip: Trip) -> some View {
    if !trip.openImportantItems.isEmpty {
      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        CMSectionHeader(title: "Still open", detail: "\(trip.openImportantItems.count) important")

        CMRowList(elements: trip.openImportantItems) { item in
          HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: "exclamationmark.circle")
              .foregroundColor(Theme.Colour.danger)
            Text(item.name)
              .font(Font.CM.label)
              .foregroundColor(Theme.Colour.primaryText)
            Spacer()
          }
          .padding(.horizontal, Theme.Spacing.cardPadding)
          .padding(.vertical, Theme.Spacing.medium)
        }

        CMHint(text: "A tick records that you looked. It does not check the car for you.")
      }
    }
  }

  @ViewBuilder
  private func otherActiveTrip(_ trip: Trip) -> some View {
    if let active = environment.activeTrip, active.id != trip.id {
      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        CMHint(
          text: "\(active.name) is already under way. Only one trip runs at a time.",
          icon: "exclamationmark.circle",
          tone: .warning
        )
        NavigationLink {
          OnTheRoadView(tripID: active.id)
        } label: {
          CMPrimaryLinkLabel(title: "Continue \(active.name)", icon: "arrow.right")
        }
        .buttonStyle(CMPressStyle())
      }
    }
  }

  // MARK: - Starting

  private func attemptStart(_ trip: Trip) {
    if trip.openImportantItems.isEmpty {
      start(allowingOpenItems: false)
    } else {
      isConfirmingOpenItems = true
    }
  }

  private func start(allowingOpenItems: Bool) {
    let didStart = environment.perform {
      let previous = environment.journal.latestOdometerReading(
        forVehicle: trip?.vehicleID
      )
      // Only send the explanation when the reading actually calls for one, so a
      // correction the traveller then fixed upward is not filed against the trip.
      let request = StartTrip.Request(
        tripID: tripID,
        actualStart: actualStart,
        startOdometer: try OdometerValidator.reading(odometerText),
        explanation: needsExplanation(previous) ? explanation : nil,
        allowsOpenImportantItems: allowingOpenItems
      )
      try environment.useCases.startTrip.execute(request)
    }
    if didStart { dismiss() }
  }

  private func openItemsMessage(_ trip: Trip) -> String {
    let names = trip.openImportantItems.map(\.name).joined(separator: ", ")
    return "Still open: \(names)."
  }
}
