import SwiftUI

/// Brings a journey home, and later corrects it.
///
/// The same form serves both: finishing an active trip, and editing the summary of
/// one already in the journal. Editing simply also offers the start, and checks that
/// every recorded event still fits inside the new interval.
struct FinishTripSheet: View {
  let tripID: UUID
  var isEditingSummary = false

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var actualStart = Date()
  @State private var actualEnd = Date()
  @State private var startOdometerText = ""
  @State private var endOdometerText = ""
  @State private var outcome: TripOutcome = .completed
  @State private var endReason = ""
  @State private var hasReadingDiscontinuity = false
  @State private var finalNote = ""
  @State private var isReviewing = false
  @State private var hasLoaded = false

  private var trip: Trip? { environment.trip(tripID) }

  var body: some View {
    Group {
      if let trip {
        content(trip)
      } else {
        CMEditorSheet(
          title: "Finish",
          saveTitle: "Close",
          onSave: { dismiss() },
          onCancel: { dismiss() }
        ) {
          CMEmptyState(
            illustration: .pipTripComplete,
            title: "This trip is gone",
            message: "It is no longer in your journal."
          )
        }
      }
    }
  }

  private func content(_ trip: Trip) -> some View {
    CMEditorSheet(
      title: isEditingSummary ? "Edit summary" : "Bring it home",
      saveTitle: "Review the summary",
      saveIcon: "arrow.right",
      onSave: { review(trip) },
      onCancel: { dismiss() }
    ) {
      header(trip)
      outcomeSection
      timesSection(trip)
      odometerSection(trip)
      stopsSection(trip)
      openVisitSection(trip)
      finalNoteSection
    }
    .onAppear { load(trip) }
    .sheet(isPresented: $isReviewing) {
      FinishSummarySheet(
        tripID: tripID,
        isEditingSummary: isEditingSummary,
        actualStart: isEditingSummary ? actualStart : (trip.actualStart ?? actualStart),
        actualEnd: actualEnd,
        outcome: outcome,
        endOdometerText: endOdometerText,
        finalNote: finalNote,
        onConfirm: { confirm(trip) },
        onKeepEditing: { isReviewing = false }
      )
    }
  }

  // MARK: - Sections

  private func header(_ trip: Trip) -> some View {
    CMScreenHeader(
      eyebrow: "Another page in your story",
      title: trip.name
    ) {
      CMAsset(.pipTripComplete, width: 88, height: 95)
    }
  }

  private var outcomeSection: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMFieldLabel(title: "How did it go?", isRequired: true)

      CMSegmentedPicker(
        options: TripOutcome.allCases,
        title: \.displayName,
        selection: $outcome
      )

      if outcome == .endedEarly {
        CMTextEditor(
          title: "Why it ended early",
          text: $endReason,
          isRequired: true,
          minimumHeight: 80
        )
      }
    }
  }

  @ViewBuilder
  private func timesSection(_ trip: Trip) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      if isEditingSummary {
        CMDateField(
          title: "Actual start",
          isRequired: true,
          date: $actualStart,
          range: ...environment.dates.now
        )
      } else {
        CMCard(padding: 0) {
          CMInfoRow(
            icon: "clock",
            title: "Set off",
            value: trip.actualStart.map(environment.formatters.fullDateAndTime) ?? "—"
          )
        }
      }

      CMDateField(
        title: "Actual end",
        isRequired: true,
        date: $actualEnd,
        range: ...environment.dates.now,
        hint: "The end comes after everything you recorded on the road."
      )
    }
  }

  private func odometerSection(_ trip: Trip) -> some View {
    let unit = environment.unit(forTrip: trip)

    return VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      CMSectionHeader(title: "Odometer", detail: "Optional")

      if isEditingSummary {
        CMTextField(
          title: "Start reading in \(unit.shortName)",
          text: $startOdometerText,
          placeholder: "Not recorded",
          keyboard: .decimalPad
        )
      } else {
        CMCard(padding: 0) {
          CMInfoRow(
            icon: "gauge",
            title: "Start reading",
            value: environment.formatters.odometer(trip.startOdometer, unit: unit)
          )
        }
      }

      CMTextField(
        title: "End reading in \(unit.shortName)",
        text: $endOdometerText,
        placeholder: "Not recorded",
        keyboard: .decimalPad
      )

      CMCard(padding: 0) {
        CMToggleRow(
          title: "The odometer was replaced or reset",
          hint: "Distance stays unknown rather than being reported as a number that could not have happened.",
          isOn: $hasReadingDiscontinuity
        )
      }

      if let distance = previewDistance(trip) {
        CMCard(padding: 0) {
          CMInfoRow(
            icon: "arrow.left.and.right",
            title: "Recorded distance",
            value: environment.formatters.distance(distance, unit: unit),
            valueColour: Theme.Colour.success
          )
        }
      }
    }
  }

  private func stopsSection(_ trip: Trip) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(title: "Your stops")

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMInfoRow(
            icon: "checkmark.circle",
            title: "Visited",
            value: "\(trip.visitedStops.count)"
          )
          CMDivider()
          CMInfoRow(
            icon: "arrow.uturn.right",
            title: "Passed by",
            value: "\(trip.skippedStops.count)"
          )
          CMDivider()
          CMInfoRow(
            icon: "circle",
            title: "Not reached",
            value: "\(trip.unvisitedStops.count)"
          )
        }
      }

      if !trip.unvisitedStops.isEmpty {
        CMHint(text: "Places you did not reach stay exactly that. You can always go back another day.")
      }
    }
  }

  @ViewBuilder
  private func openVisitSection(_ trip: Trip) -> some View {
    if let open = trip.openVisit {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMHint(
          text: "You are still at \(open.name). Record leaving before finishing.",
          icon: "exclamationmark.circle",
          tone: .warning
        )

        CMButton(title: "Left \(open.name) at the end time", prominence: .secondary) {
          guard let arrival = open.visit?.arrival else { return }
          environment.perform {
            try environment.useCases.recordVisit.execute(
              tripID: tripID,
              stopID: open.id,
              arrival: arrival,
              departure: actualEnd
            )
          }
        }
      }
    }
  }

  private var finalNoteSection: some View {
    CMTextEditor(
      title: "A final note",
      text: $finalNote,
      hint: "How it felt, what you would do differently, anything worth keeping."
    )
  }

  // MARK: - Working out

  /// The distance the form would record, shown live so the traveller sees the
  /// consequence of a reading before confirming it.
  private func previewDistance(_ trip: Trip) -> Double? {
    guard !hasReadingDiscontinuity else { return nil }

    let start =
      isEditingSummary
      ? (try? OdometerValidator.reading(startOdometerText)).flatMap { $0 }
      : trip.startOdometer
    guard
      let start,
      let end = (try? OdometerValidator.reading(endOdometerText)).flatMap({ $0 }),
      end >= start
    else { return nil }
    return end - start
  }

  private func load(_ trip: Trip) {
    // Only on first appearance: a sheet's body runs again on every keystroke, and
    // reloading here would wipe what the traveller has just typed.
    guard !hasLoaded else { return }
    hasLoaded = true

    actualStart = trip.actualStart ?? environment.dates.now
    actualEnd = trip.actualEnd ?? environment.dates.now
    startOdometerText = trip.startOdometer.map { String($0) } ?? ""
    endOdometerText = trip.endOdometer.map { String($0) } ?? ""
    outcome = trip.outcome ?? .completed
    endReason = trip.endReason
    hasReadingDiscontinuity = trip.hasReadingDiscontinuity
    finalNote = trip.finalNote
  }

  // MARK: - Confirming

  /// Checks the form before showing the summary, so a refusal arrives here rather
  /// than on the confirmation screen.
  private func review(_ trip: Trip) {
    let isValid = environment.perform {
      _ = try endingRequest()
      if isEditingSummary {
        let conflicts = environment.useCases.editTripSummary.conflicts(for: try summaryRequest())
        guard conflicts.isEmpty else {
          throw DomainError(
            "These records fall outside the new times. Correct them first:\n"
              + conflicts.map { "· \($0.description)" }.joined(separator: "\n")
          )
        }
      }
    }
    if isValid { isReviewing = true }
  }

  private func endingRequest() throws -> FinishTrip.Request {
    FinishTrip.Request(
      tripID: tripID,
      actualEnd: actualEnd,
      endOdometer: try OdometerValidator.reading(endOdometerText),
      outcome: outcome,
      endReason: endReason,
      hasReadingDiscontinuity: hasReadingDiscontinuity,
      finalNote: finalNote
    )
  }

  private func summaryRequest() throws -> EditTripSummary.Request {
    EditTripSummary.Request(
      tripID: tripID,
      actualStart: actualStart,
      startOdometer: try OdometerValidator.reading(startOdometerText),
      ending: try endingRequest()
    )
  }

  private func confirm(_ trip: Trip) {
    let didSave = environment.perform {
      if isEditingSummary {
        try environment.useCases.editTripSummary.execute(try summaryRequest())
      } else {
        try environment.useCases.finishTrip.execute(try endingRequest())
      }
    }

    if didSave {
      isReviewing = false
      dismiss()
    }
  }
}

/// The last confirmation before a trip becomes a journal entry.
struct FinishSummarySheet: View {
  let tripID: UUID
  let isEditingSummary: Bool
  let actualStart: Date
  let actualEnd: Date
  let outcome: TripOutcome
  let endOdometerText: String
  let finalNote: String
  let onConfirm: () -> Void
  let onKeepEditing: () -> Void

  @EnvironmentObject private var environment: AppEnvironment

  private var trip: Trip? { environment.trip(tripID) }

  var body: some View {
    NavigationView {
      CMScreenWithAction {
        if let trip {
          CMScreenHeader(eyebrow: "Your trip, in a nutshell", title: trip.name)

          CMTag(text: outcome.displayName, colour: Theme.Colour.success)

          CMCard(padding: 0) {
            VStack(spacing: 0) {
              CMInfoRow(
                icon: "clock",
                title: "Elapsed",
                value: environment.formatters.duration(
                  actualEnd.timeIntervalSince(actualStart)
                )
              )
              CMDivider()
              CMInfoRow(
                icon: "calendar",
                title: "Ended",
                value: environment.formatters.fullDateAndTime(actualEnd)
              )
              CMDivider()
              CMInfoRow(
                icon: "gauge",
                title: "End reading",
                value: endOdometerText.isBlank ? "Not recorded" : endOdometerText
              )
              CMDivider()
              CMInfoRow(
                icon: "mappin",
                title: "Stops",
                value: "\(trip.visitedStops.count) visited · \(trip.skippedStops.count) passed by · \(trip.unvisitedStops.count) not reached"
              )
            }
          }

          if !finalNote.isBlank {
            CMCard {
              Text(finalNote)
                .font(Font.CM.callout)
                .foregroundColor(Theme.Colour.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          CMHint(
            text: "Elapsed time covers the whole trip, stops included. It is not driving time."
          )
        }
      } action: {
        VStack(spacing: Theme.Spacing.small) {
          CMButton(
            title: isEditingSummary ? "Save these changes" : "Finish the trip",
            icon: "checkmark",
            action: onConfirm
          )
          CMButton(title: "Keep editing", prominence: .tertiary, action: onKeepEditing)
        }
      }
      .navigationTitle("Review")
      .navigationBarTitleDisplayMode(.inline)
    }
    .navigationViewStyle(.stack)
  }
}
