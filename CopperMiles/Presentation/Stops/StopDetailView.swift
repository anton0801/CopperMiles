import SwiftUI

/// One place: what was planned for it, and what actually happened there.
struct StopDetailView: View {
  let tripID: UUID
  let stopID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var isEditing = false
  @State private var isAddingNote = false
  @State private var isEditingVisit = false
  @State private var isSkipping = false
  @State private var isConfirmingRemoval = false
  @State private var isConfirmingDestination = false
  @State private var isRemovingVisit = false

  private var trip: Trip? { environment.trip(tripID) }
  private var stop: Stop? { trip?.stop(stopID) }

  var body: some View {
    Group {
      if let trip, let stop {
        content(trip, stop)
      } else {
        CMScreen {
          CMEmptyState(
            illustration: .stopMarker,
            title: "This stop is gone",
            message: "It is no longer part of the plan."
          )
        }
      }
    }
    .navigationTitle("Stop")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func content(_ trip: Trip, _ stop: Stop) -> some View {
    CMScreen {
      header(trip, stop)
      maps(stop)
      plan(stop)
      visit(trip, stop)
      notes(trip, stop)
      management(trip, stop)
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Edit") { isEditing = true }
      }
    }
    .sheet(isPresented: $isEditing) {
      StopEditorSheet(
        tripID: tripID,
        stop: stop,
        defaultArrival: trip.plannedDeparture ?? environment.dates.now
      )
    }
    .sheet(isPresented: $isAddingNote) {
      RoadNoteEditorSheet(
        tripID: tripID,
        note: RoadNote(recordedAt: noteDate(trip), stopID: stopID)
      )
    }
    .sheet(isPresented: $isEditingVisit) {
      VisitEditorSheet(tripID: tripID, stop: stop)
    }
    .sheet(isPresented: $isSkipping) {
      SkipStopSheet(tripID: tripID, stopID: stopID, stopName: stop.name)
    }
    .alert(removalTitle(stop), isPresented: $isConfirmingRemoval) {
      Button("Confirm", role: .destructive) {
        let didRemove = environment.perform {
          try environment.useCases.removeStop.execute(tripID: tripID, stopID: stopID)
        }
        if didRemove { dismiss() }
      }
      Button("Keep stop", role: .cancel) {}
    } message: {
      Text(
        stop.isVisited
          ? "It leaves the plan, and your visit and its notes stay in the journal."
          : "It is removed from the plan."
      )
    }
    .alert("Head for \(stop.name) instead?", isPresented: $isConfirmingDestination) {
      Button("Make it the destination") {
        environment.perform {
          try environment.useCases.setDestination.execute(tripID: tripID, stopID: stopID)
        }
      }
      Button("Keep the current one", role: .cancel) {}
    } message: {
      Text(
        trip.destination.map {
          "\($0.name) becomes an ordinary stop, and \(stop.name) moves to the end of the plan."
        } ?? "\(stop.name) moves to the end of the plan."
      )
    }
    .confirmationDialog(
      "Remove this visit?",
      isPresented: $isRemovingVisit,
      titleVisibility: .visible
    ) {
      Button("Remove visit, keep the notes") { removeVisit(.keepAsTripNotes) }
      Button("Remove visit and its notes", role: .destructive) { removeVisit(.deleteWithVisit) }
      Button("Keep visit", role: .cancel) {}
    } message: {
      Text("The stop goes back to planned. Its notes can stay in your journal as trip notes.")
    }
  }

  // MARK: - Header

  private func header(_ trip: Trip, _ stop: Stop) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMScreenHeader(eyebrow: stop.kind.displayName, title: stop.name) {
        if !hasPhotos(trip) {
          CMAsset(.stopMarker, width: 56, height: 68)
        }
      }

      HStack(spacing: Theme.Spacing.small) {
        CMTag(text: stop.stateLabel, colour: stop.stateColour)

        if trip.status == .active, stop.isOutstanding, trip.nextStop?.id != stop.id {
          CMTag(text: "Out of order", colour: Theme.Colour.accent)
        }
      }

      if let reason = stop.skipReason {
        CMHint(text: "Passed by: \(reason)", icon: "arrow.uturn.right")
      }
    }
  }

  // MARK: - Maps

  @ViewBuilder
  private func maps(_ stop: Stop) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      if !stop.address.isEmpty {
        CMCard(padding: 0) {
          CMInfoRow(icon: "mappin.and.ellipse", title: "Address", value: stop.address)
        }
      }

      switch MapsDestination(stop: stop) {
      case .coordinate:
        CMButton(title: "Open in Maps", icon: "arrow.up.forward.app", prominence: .secondary) {
          environment.maps.open(stop)
        }
        if let coordinate = stop.coordinate {
          CMHint(
            text: "\(coordinate.latitude), \(coordinate.longitude)",
            icon: "location"
          )
        }

      case .addressSearch:
        CMButton(title: "Open in Maps", icon: "arrow.up.forward.app", prominence: .secondary) {
          environment.maps.open(stop)
        }
        CMHint(text: "Maps will search for this address. Confirm the place there.")

      case .unavailable:
        CMButton(title: "Add an address", icon: "plus", prominence: .secondary) {
          isEditing = true
        }
        CMHint(text: "With an address or a coordinate, this stop can be opened in Maps.")
      }
    }
  }

  // MARK: - Plan

  @ViewBuilder
  private func plan(_ stop: Stop) -> some View {
    if stop.plannedArrival != nil || stop.plannedStayMinutes != nil
      || !stop.parkingNote.isEmpty || !stop.personalNote.isEmpty
    {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMSectionHeader(title: "What you planned")

        if stop.plannedArrival != nil || stop.plannedStayMinutes != nil {
          CMCard(padding: 0) {
            VStack(spacing: 0) {
              if let arrival = stop.plannedArrival {
                CMInfoRow(
                  icon: "clock",
                  title: "Planned arrival",
                  value: environment.formatters.fullDateAndTime(arrival)
                )
              }
              if let minutes = stop.plannedStayMinutes {
                if stop.plannedArrival != nil { CMDivider() }
                CMInfoRow(
                  icon: "hourglass",
                  title: "Planned stay",
                  value: environment.formatters.duration(TimeInterval(minutes * 60))
                )
              }
            }
          }
        }

        if !stop.parkingNote.isEmpty {
          CMCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
              Label("Parking", systemImage: "parkingsign.circle")
                .font(Font.CM.labelEmphasis)
                .foregroundColor(Theme.Colour.primaryText)
              Text(stop.parkingNote)
                .font(Font.CM.callout)
                .foregroundColor(Theme.Colour.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }

        if !stop.personalNote.isEmpty {
          CMCard {
            Text(stop.personalNote)
              .font(Font.CM.callout)
              .foregroundColor(Theme.Colour.primaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  // MARK: - Visit

  @ViewBuilder
  private func visit(_ trip: Trip, _ stop: Stop) -> some View {
    if let visit = stop.visit {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMSectionHeader(title: "Your visit")

        CMCard(padding: 0) {
          VStack(spacing: 0) {
            CMInfoRow(
              icon: "arrow.down.circle",
              title: "Arrived",
              value: environment.formatters.fullDateAndTime(visit.arrival)
            )
            CMDivider()
            CMInfoRow(
              icon: "arrow.up.circle",
              title: "Left",
              value: visit.departure.map(environment.formatters.fullDateAndTime) ?? "Still here"
            )
            if let departure = visit.departure {
              CMDivider()
              CMInfoRow(
                icon: "hourglass",
                title: "Stayed",
                value: environment.formatters.duration(
                  departure.timeIntervalSince(visit.arrival)
                )
              )
            }
          }
        }

        if visit.isOpen, trip.status == .active {
          CMButton(title: "Leave now", icon: "arrow.up.right") {
            environment.perform {
              try environment.useCases.recordVisit.leaveNow(tripID: tripID, stopID: stopID)
            }
          }
        }

        CMCard(padding: 0) {
          VStack(spacing: 0) {
            CMActionRow(icon: "clock.arrow.circlepath", title: "Edit visit times") {
              isEditingVisit = true
            }
            CMDivider()
            CMActionRow(icon: "arrow.uturn.backward", title: "Remove visit", isDestructive: true) {
              isRemovingVisit = true
            }
          }
        }
      }
    } else if trip.status == .active, !stop.isSkipped {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMButton(title: "Arrive now", icon: "mappin.and.ellipse") {
          environment.perform {
            try environment.useCases.recordVisit.arriveNow(tripID: tripID, stopID: stopID)
          }
        }

        CMCard(padding: 0) {
          VStack(spacing: 0) {
            CMActionRow(icon: "clock", title: "Set an arrival time") { isEditingVisit = true }
            CMDivider()
            CMActionRow(icon: "arrow.uturn.right", title: "Pass this stop by") {
              isSkipping = true
            }
          }
        }
      }
    } else if stop.isSkipped, trip.status == .active {
      CMButton(title: "Bring this stop back", icon: "arrow.uturn.backward", prominence: .secondary) {
        environment.perform {
          try environment.useCases.skipStop.undo(tripID: tripID, stopID: stopID)
        }
      }
    }
  }

  // MARK: - Notes

  @ViewBuilder
  private func notes(_ trip: Trip, _ stop: Stop) -> some View {
    let stopNotes = trip.notes
      .filter { $0.stopID == stopID }
      .sorted { $0.recordedAt < $1.recordedAt }

    if trip.status.hasStarted {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMSectionHeader(
          title: "Little memories",
          detail: stopNotes.isEmpty ? nil : "\(stopNotes.count)"
        )

        CMButton(title: "Add a memory", icon: "square.and.pencil", prominence: .secondary) {
          isAddingNote = true
        }

        ForEach(stopNotes) { note in
          NavigationLink {
            RoadNoteDetailView(tripID: tripID, noteID: note.id)
          } label: {
            RoadNoteCard(note: note)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: - Management

  @ViewBuilder
  private func management(_ trip: Trip, _ stop: Stop) -> some View {
    VStack(spacing: Theme.Spacing.medium) {
      CMCard(padding: 0) {
        VStack(spacing: 0) {
          if trip.status != .completed, trip.status != .cancelled {
            CMActionRow(
              icon: "plus.square.on.square",
              title: "Plan this place again",
              detail: "Adds a second stop, so each stay keeps its own times"
            ) {
              environment.perform {
                _ = try environment.useCases.duplicateStop.execute(tripID: tripID, stopID: stopID)
              }
            }
            CMDivider()
          }

          if SetDestination.canBecomeDestination(stop, in: trip) {
            CMActionRow(
              icon: "flag",
              title: "Make this the destination",
              detail: "It becomes where the trip is heading, and moves to the end"
            ) {
              isConfirmingDestination = true
            }
            CMDivider()
          }

          if stop.kind == .destination {
            CMInfoRow(
              icon: "flag.fill",
              title: "Destination",
              value: "Stays last",
              valueColour: Theme.Colour.secondaryText
            )
          } else {
            CMActionRow(
              icon: stop.isVisited ? "archivebox" : "trash",
              title: stop.isVisited ? "Archive this stop" : "Delete this stop",
              isDestructive: true
            ) {
              isConfirmingRemoval = true
            }
          }
        }
      }

      if stop.kind == .destination {
        CMHint(
          text: "To remove this stop, make another one the destination first.",
          icon: "info.circle"
        )
      }
    }
  }

  // MARK: - Helpers

  private func hasPhotos(_ trip: Trip) -> Bool {
    trip.notes.contains { $0.stopID == stopID && !$0.photoIDs.isEmpty }
  }

  private func removalTitle(_ stop: Stop) -> String {
    stop.isVisited ? "Archive \(stop.name)?" : "Delete \(stop.name)?"
  }

  private func removeVisit(_ handling: RemoveVisit.NoteHandling) {
    environment.perform {
      try environment.useCases.removeVisit.execute(
        tripID: tripID,
        stopID: stopID,
        notes: handling
      )
    }
  }

  /// A note defaults to now while the trip runs, and to the trip's end once it is
  /// finished, so it always lands inside the interval.
  private func noteDate(_ trip: Trip) -> Date {
    trip.actualEnd ?? environment.dates.now
  }
}

/// Records passing a stop by, with the reason kept beside it.
struct SkipStopSheet: View {
  let tripID: UUID
  let stopID: UUID
  let stopName: String

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var reason = ""

  var body: some View {
    CMEditorSheet(
      title: "Pass this by",
      saveTitle: "Pass \(stopName) by",
      onSave: save,
      onCancel: { dismiss() }
    ) {
      CMScreenHeader(
        eyebrow: stopName,
        title: "Not this time?",
        subtitle: "A stop you passed by is kept as exactly that — not as somewhere you visited, and not as a failure."
      )

      CMTextEditor(
        title: "Why you passed it by",
        text: $reason,
        isRequired: true,
        hint: "A few words are plenty. It will be useful the next time you plan this road."
      )
    }
  }

  private func save() {
    let didSave = environment.perform {
      try environment.useCases.skipStop.skip(tripID: tripID, stopID: stopID, reason: reason)
    }
    if didSave { dismiss() }
  }
}

/// Corrects the times of a stay.
struct VisitEditorSheet: View {
  let tripID: UUID
  let stop: Stop

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var arrival: Date
  @State private var hasLeft: Bool
  @State private var departure: Date
  @State private var isReviewing = false

  init(tripID: UUID, stop: Stop) {
    self.tripID = tripID
    self.stop = stop
    _arrival = State(initialValue: stop.visit?.arrival ?? Date())
    _hasLeft = State(initialValue: stop.visit?.departure != nil)
    _departure = State(initialValue: stop.visit?.departure ?? Date())
  }

  var body: some View {
    CMEditorSheet(
      title: "Visit times",
      saveTitle: "Review the change",
      onSave: { isReviewing = true },
      onCancel: { dismiss() }
    ) {
      CMScreenHeader(eyebrow: "Your stay", title: stop.name)

      CMDateField(
        title: "Arrived",
        isRequired: true,
        date: $arrival,
        range: ...environment.dates.now
      )

      CMCard(padding: 0) {
        CMToggleRow(title: "This visit has ended", isOn: $hasLeft)
      }

      if hasLeft {
        CMDateField(title: "Left", date: $departure, range: ...environment.dates.now)
      }

      CMHint(
        text: "Times stay inside the trip, in order, and cannot overlap another visit."
      )
    }
    .alert("Save these times?", isPresented: $isReviewing) {
      Button("Save visit") { save() }
      Button("Keep editing", role: .cancel) {}
    } message: {
      Text(
        """
        Arrived: \(environment.formatters.fullDateAndTime(arrival))
        Left: \(hasLeft ? environment.formatters.fullDateAndTime(departure) : "Still here")
        """
      )
    }
  }

  private func save() {
    let didSave = environment.perform {
      try environment.useCases.recordVisit.execute(
        tripID: tripID,
        stopID: stop.id,
        arrival: arrival,
        departure: hasLeft ? departure : nil
      )
    }
    if didSave { dismiss() }
  }
}
