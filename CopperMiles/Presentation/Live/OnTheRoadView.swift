import SwiftUI

/// A journey under way.
///
/// Built for a passenger or for someone parked: nothing here needs to be tapped
/// while driving, and nothing is recorded automatically. There is no speed, no
/// background location and no arrival guessed on the traveller's behalf.
struct OnTheRoadView: View {
  let tripID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @ScaledMetric(relativeTo: .largeTitle) private var heroSize = Font.CM.heroSize

  @State private var isAddingNote = false
  @State private var isFinishing = false

  private var trip: Trip? { environment.trip(tripID) }

  var body: some View {
    Group {
      if let trip, trip.status == .active {
        content(trip)
      } else if let trip {
        finishedNotice(trip)
      } else {
        CMScreen {
          CMEmptyState(
            illustration: .pipOnTheRoad,
            title: "This trip is gone",
            message: "It is no longer in your journal."
          )
        }
      }
    }
    .navigationTitle("On the road")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func content(_ trip: Trip) -> some View {
    CMScreen {
      header(trip)
      elapsed(trip)
      nextStop(trip)
      lastNote(trip)
      actions(trip)
      footnote
    }
    .sheet(isPresented: $isAddingNote) {
      RoadNoteEditorSheet(
        tripID: tripID,
        note: RoadNote(recordedAt: environment.dates.now)
      )
    }
    .sheet(isPresented: $isFinishing) {
      FinishTripSheet(tripID: tripID)
    }
  }

  // MARK: - Sections

  private func header(_ trip: Trip) -> some View {
    CMScreenHeader(
      eyebrow: "On the road",
      title: trip.name,
      subtitle: trip.actualStart.map {
        "Set off \(environment.formatters.fullDateAndTime($0))"
      }
    ) {
      CMAsset(.pipOnTheRoad, width: 56, height: 64)
    }
  }

  /// The running clock.
  ///
  /// Recomputed from the stored start each minute, so closing the app and coming
  /// back shows the right figure rather than restarting from zero.
  private func elapsed(_ trip: Trip) -> some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      CMCard(background: Theme.Colour.action.opacity(0.45)) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
            Text(environment.formatters.duration(trip.elapsed(until: context.date)))
              .font(Font.CM.hero(heroSize))
              .minimumScaleFactor(0.6)
              .lineLimit(1)
              .foregroundColor(Theme.Colour.primaryText)

            Text("ELAPSED · INCLUDES EVERY STOP")
              .font(Font.CM.eyebrow)
              .cmTracked(1.1)
              .foregroundColor(Theme.Colour.primaryText.opacity(0.7))
          }

          Spacer()

          CMTag(text: "Under way", colour: Theme.Colour.success)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        "Elapsed \(environment.formatters.duration(trip.elapsed(until: context.date))), including every stop"
      )
    }
  }

  @ViewBuilder
  private func nextStop(_ trip: Trip) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(
        title: "Your stops",
        detail: "\(trip.visitedStops.count) of \(trip.activeStops.count) visited"
      )

      // Being somewhere comes before going somewhere: while a visit is open, that
      // stop is what the screen is about, and the next one can wait.
      if let here = trip.openVisit {
        currentStopCard(here)
      } else if let next = trip.nextStop {
        CMCard(isHighlighted: true) {
          VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            CMEyebrow(text: "Next stop")

            Text(next.name)
              .font(Font.CM.cardTitle)
              .foregroundColor(Theme.Colour.primaryText)
              .fixedSize(horizontal: false, vertical: true)

            if let arrival = next.plannedArrival {
              Text("You planned to be there \(environment.formatters.dateAndTime(arrival))")
                .font(Font.CM.footnote)
                .foregroundColor(Theme.Colour.secondaryText)
            }

            NavigationLink {
              StopDetailView(tripID: tripID, stopID: next.id)
            } label: {
              CMPrimaryLinkLabel(title: "Open this stop", icon: "arrow.right")
            }
            .buttonStyle(CMPressStyle())
          }
        }
      } else {
        CMCard {
          HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: "checkmark.circle")
              .font(.system(.title3))
              .foregroundColor(Theme.Colour.success)
            VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
              Text("Every stop has been looked at")
                .font(Font.CM.labelEmphasis)
                .foregroundColor(Theme.Colour.primaryText)
              Text("Reaching the destination does not end the trip. You decide when it is over.")
                .font(Font.CM.footnote)
                .foregroundColor(Theme.Colour.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }

      NavigationLink {
        TripPlanView(tripID: tripID)
      } label: {
        CMCard(padding: 0) {
          CMRowContent(
            icon: "list.bullet",
            title: "Show every stop",
            detail: "The whole plan, in order",
            showsChevron: true
          )
        }
      }
      .buttonStyle(.plain)
    }
  }

  /// The stop the traveller is at right now.
  private func currentStopCard(_ stop: Stop) -> some View {
    CMCard(isHighlighted: true) {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMEyebrow(text: "You are here", colour: Theme.Colour.success)

        Text(stop.name)
          .font(Font.CM.cardTitle)
          .foregroundColor(Theme.Colour.primaryText)
          .fixedSize(horizontal: false, vertical: true)

        if let arrival = stop.visit?.arrival {
          Text("Arrived \(environment.formatters.dateAndTime(arrival))")
            .font(Font.CM.footnote)
            .foregroundColor(Theme.Colour.secondaryText)
        }

        CMButton(title: "Leave now", icon: "arrow.up.right") {
          environment.perform {
            try environment.useCases.recordVisit.leaveNow(tripID: tripID, stopID: stop.id)
          }
        }

        NavigationLink {
          StopDetailView(tripID: tripID, stopID: stop.id)
        } label: {
          CMRowContent(
            icon: "mappin.and.ellipse",
            title: "Open this stop",
            detail: "Notes, times and photos",
            showsChevron: true
          )
          .padding(.horizontal, -Theme.Spacing.cardPadding)
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private func lastNote(_ trip: Trip) -> some View {
    if let note = trip.notes.max(by: { $0.recordedAt < $1.recordedAt }) {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMSectionHeader(title: "Last little memory")

        NavigationLink {
          RoadNoteDetailView(tripID: tripID, noteID: note.id)
        } label: {
          RoadNoteCard(note: note, lineLimit: 3)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func actions(_ trip: Trip) -> some View {
    VStack(spacing: Theme.Spacing.medium) {
      CMButton(title: "Add a road note", icon: "square.and.pencil") {
        isAddingNote = true
      }

      CMButton(title: "Finish this trip", icon: "flag.checkered", prominence: .secondary) {
        isFinishing = true
      }
    }
  }

  private var footnote: some View {
    CMHint(
      text: "Copper Miles never records anything on its own. Use it while parked, or let a passenger help.",
      icon: "hand.raised"
    )
  }

  private func finishedNotice(_ trip: Trip) -> some View {
    CMScreen {
      CMEmptyState(
        illustration: .pipTripComplete,
        title: "This trip is home",
        message: "It has finished and now lives in your journal."
      ) {
        NavigationLink {
          JournalEntryView(tripID: tripID)
        } label: {
          CMPrimaryLinkLabel(title: "Open the journal entry", icon: "arrow.right")
        }
        .buttonStyle(CMPressStyle())
      }
    }
  }
}
