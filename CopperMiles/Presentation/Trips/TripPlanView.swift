import SwiftUI

/// One trip's plan: where it goes, in what order, and how ready it is.
struct TripPlanView: View {
  let tripID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var isEditing = false
  @State private var isAddingStop = false
  @State private var isConfirmingCancel = false
  @State private var duplicatedTrip: Trip?

  private var trip: Trip? { environment.trip(tripID) }

  var body: some View {
    Group {
      if let trip {
        content(trip)
      } else {
        CMScreen {
          CMEmptyState(
            illustration: .roadSign,
            title: "This trip is gone",
            message: "It is no longer in your journal."
          )
        }
      }
    }
    .navigationTitle("Trip plan")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func content(_ trip: Trip) -> some View {
    CMScreen {
      header(trip)
      facts(trip)
      stops(trip)
      preparation(trip)
      moreActions(trip)
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        if trip.status.isPlanning {
          Button("Edit") { isEditing = true }
        }
      }
    }
    .sheet(isPresented: $isEditing) { TripEditorSheet(trip: trip) }
    .sheet(isPresented: $isAddingStop) { StopEditorSheet(tripID: trip.id, stop: Stop()) }
    .sheet(item: $duplicatedTrip) { copy in
      TripEditorSheet(trip: copy)
    }
    .alert("Cancel this trip?", isPresented: $isConfirmingCancel) {
      Button("Cancel trip", role: .destructive) {
        environment.perform { try environment.useCases.cancelTrip.execute(tripID: tripID) }
      }
      Button("Keep planning", role: .cancel) {}
    } message: {
      Text("The plan stays in your list as Cancelled, and its reminders are removed.")
    }
  }

  // MARK: - Header

  private func header(_ trip: Trip) -> some View {
    let needsReview = trip.needsReview(now: environment.dates.now)

    return VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMScreenHeader(
        eyebrow: needsReview ? "Needs review" : trip.status.displayName,
        title: trip.name.isEmpty ? "Untitled trip" : trip.name
      ) {
        CMAsset(.roadSign, width: 64, height: 70)
      }

      if needsReview {
        CMHint(
          text: "This departure has already passed. Give it a new date, or bring the plan up to date.",
          icon: "calendar.badge.exclamationmark",
          tone: .warning
        )
      }

      if trip.status == .planned {
        NavigationLink {
          ChecklistView(tripID: tripID)
        } label: {
          CMPrimaryLinkLabel(title: "Get ready to go", icon: "checklist")
        }
        .buttonStyle(CMPressStyle())
      }
    }
  }

  private func facts(_ trip: Trip) -> some View {
    CMCard(padding: 0) {
      VStack(spacing: 0) {
        CMInfoRow(
          icon: "car.fill",
          title: "Vehicle",
          value: environment.vehicleName(trip.vehicleID)
        )
        CMDivider()
        CMInfoRow(
          icon: "calendar",
          title: "Departure",
          value: trip.plannedDeparture.map(environment.formatters.fullDateAndTime)
            ?? "Not set"
        )
        if let end = trip.expectedEnd {
          CMDivider()
          CMInfoRow(
            icon: "calendar.badge.clock",
            title: "Expected back",
            value: environment.formatters.fullDateAndTime(end)
          )
        }
        CMDivider()
        CMInfoRow(
          icon: "location.circle",
          title: "Setting off from",
          value: trip.startPlace.isEmpty ? "Not set" : trip.startPlace
        )
        CMDivider()
        CMInfoRow(
          icon: "person.2",
          title: "Travellers",
          value: "\(trip.travellers)"
        )
      }
    }
  }

  // MARK: - Stops

  private func stops(_ trip: Trip) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(
        title: "Along the way",
        detail: trip.status.hasStarted
          ? "\(trip.visitedStops.count) of \(trip.activeStops.count) visited"
          : nil
      ) {
        if trip.status.isPlanning || trip.status == .active {
          CMIconButton(systemImage: "plus", accessibilityLabel: "Add a stop", prominence: .primary) {
            isAddingStop = true
          }
        }
      }

      if trip.activeStops.isEmpty {
        CMCard {
          Text("Add the places you want to stop at, and the destination you are heading for.")
            .font(Font.CM.callout)
            .foregroundColor(Theme.Colour.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        CMCard(padding: 0) {
          VStack(spacing: 0) {
            ForEach(Array(trip.activeStops.enumerated()), id: \.element.id) { index, stop in
              HStack(spacing: 0) {
                NavigationLink {
                  StopDetailView(tripID: trip.id, stopID: stop.id)
                } label: {
                  StopRow(stop: stop, index: index)
                }
                .buttonStyle(.plain)

                if MoveStop.isMovable(stop, in: trip) {
                  reorderMenu(stop)
                }
              }

              if index < trip.activeStops.count - 1 {
                CMDivider()
              }
            }
          }
        }

        if trip.status.isPlanning {
          CMHint(text: "The destination stays last. Everything before it can be rearranged.")
        } else if trip.status == .active {
          CMHint(text: "While you are on the road, only the stops still ahead can be rearranged.")
        }
      }
    }
  }

  private func reorderMenu(_ stop: Stop) -> some View {
    Menu {
      Button {
        move(stop.id, by: -1)
      } label: {
        Label("Move earlier", systemImage: "arrow.up")
      }
      Button {
        move(stop.id, by: 1)
      } label: {
        Label("Move later", systemImage: "arrow.down")
      }
    } label: {
      Image(systemName: "line.3.horizontal")
        .font(.system(.footnote))
        .foregroundColor(Theme.Colour.secondaryText)
        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
    }
    .accessibilityLabel("Reorder \(stop.name)")
  }

  private func move(_ stopID: UUID, by offset: Int) {
    environment.perform {
      try environment.useCases.moveStop.execute(tripID: tripID, stopID: stopID, offset: offset)
    }
  }

  // MARK: - Preparation and notes

  @ViewBuilder
  private func preparation(_ trip: Trip) -> some View {
    if trip.status.isPlanning {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMSectionHeader(title: "Before you go")

        CMCard(padding: 0) {
          VStack(spacing: 0) {
            CMNavigationRow(
              icon: "checklist",
              title: "Departure checklist",
              detail: checklistDetail(trip),
              tint: Theme.Colour.success
            ) {
              ChecklistView(tripID: trip.id)
            }

            CMDivider()

            CMNavigationRow(
              icon: "bell",
              title: "Departure reminders",
              detail: reminderDetail(trip)
            ) {
              RemindersView(tripID: trip.id)
            }
          }
        }
      }
    }

    if !trip.note.isEmpty {
      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        CMSectionHeader(title: "A note for the road")
        CMCard {
          Text(trip.note)
            .font(Font.CM.callout)
            .foregroundColor(Theme.Colour.primaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func checklistDetail(_ trip: Trip) -> String {
    let progress = trip.checklistProgress
    if progress.isEmpty { return "No checks yet" }
    return "\(progress.checked) of \(progress.total) ready"
  }

  private func reminderDetail(_ trip: Trip) -> String {
    let scheduled = trip.reminders.filter(\.isScheduled).count
    if trip.reminders.isEmpty { return "None set" }
    if scheduled == 0 { return "\(trip.reminders.count) set · none scheduled" }
    return "\(scheduled) scheduled"
  }

  // MARK: - Other actions

  private func moreActions(_ trip: Trip) -> some View {
    VStack(spacing: Theme.Spacing.medium) {
      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMActionRow(
            icon: "plus.square.on.square",
            title: "Take this trip again",
            detail: "A fresh plan with the same car and stops"
          ) {
            duplicatedTrip = environment.performReturning {
              try environment.useCases.duplicateTrip.execute(
                tripID: tripID,
                carryingHints: Set(trip.notes.filter(\.isPinnedForRepeat).map(\.id))
              )
            }
          }

          if trip.status.isPlanning {
            CMDivider()
            CMActionRow(
              icon: "xmark.circle",
              title: "Cancel this trip",
              isDestructive: true
            ) {
              isConfirmingCancel = true
            }
          }
        }
      }
    }
  }
}
