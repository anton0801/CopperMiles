import SwiftUI

/// One finished trip, in full.
struct JournalEntryView: View {
  let tripID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var isEditingSummary = false
  @State private var isExporting = false
  @State private var isConfirmingDelete = false
  @State private var repeatedTrip: Trip?

  private var trip: Trip? { environment.trip(tripID) }

  var body: some View {
    Group {
      if let trip {
        content(trip)
      } else {
        CMScreen {
          CMEmptyState(
            illustration: .roadNotebook,
            title: "This entry is gone",
            message: "It is no longer in your journal."
          )
        }
      }
    }
    .navigationTitle("Journal entry")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func content(_ trip: Trip) -> some View {
    CMScreen {
      header(trip)
      metrics(trip)
      readings(trip)
      closingWords(trip)
      timeline(trip)
      unreached(trip)
      actions(trip)
    }
    .sheet(isPresented: $isEditingSummary) {
      FinishTripSheet(tripID: tripID, isEditingSummary: true)
    }
    .sheet(isPresented: $isExporting) {
      TripExportSheet(tripID: tripID)
    }
    .sheet(item: $repeatedTrip) { copy in
      TripEditorSheet(trip: copy, now: environment.dates.now)
    }
    .alert("Delete this journey?", isPresented: $isConfirmingDelete) {
      Button("Delete trip", role: .destructive) {
        let didDelete = environment.perform {
          try environment.useCases.deleteTrip.execute(tripID: tripID)
        }
        if didDelete { dismiss() }
      }
      Button("Keep journey", role: .cancel) {}
    } message: {
      Text(deletionMessage)
    }
  }

  // MARK: - Sections

  private func header(_ trip: Trip) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMScreenHeader(
        eyebrow: trip.actualStart.map(environment.formatters.fullDateAndTime) ?? "Your journal",
        title: trip.name
      )

      HStack(spacing: Theme.Spacing.small) {
        CMTag(
          text: trip.outcome?.displayName ?? "Completed",
          colour: trip.outcome == .endedEarly ? Theme.Colour.accent : Theme.Colour.success
        )
        if trip.isArchived {
          CMTag(text: "Archived")
        }
      }

      if !trip.endReason.isEmpty {
        CMHint(text: "Ended early: \(trip.endReason)", icon: "info.circle")
      }
    }
  }

  private func metrics(_ trip: Trip) -> some View {
    HStack(alignment: .top, spacing: Theme.Spacing.medium) {
      CMCard {
        CMStatistic(
          value: environment.formatters.duration(trip.elapsed(until: environment.dates.now)),
          label: "Elapsed, stops included"
        )
      }

      CMCard {
        CMStatistic(
          value: environment.formatters.distance(
            trip.recordedDistance,
            unit: environment.unit(forTrip: trip)
          ),
          label: "Recorded distance"
        )
      }
    }
  }

  private func readings(_ trip: Trip) -> some View {
    let unit = environment.unit(forTrip: trip)

    return VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMInfoRow(
            icon: "car.fill",
            title: "Vehicle",
            value: environment.vehicleName(trip.vehicleID)
          )
          CMDivider()
          CMInfoRow(
            icon: "clock",
            title: "Set off",
            value: trip.actualStart.map(environment.formatters.fullDateAndTime) ?? "—"
          )
          CMDivider()
          CMInfoRow(
            icon: "flag.checkered",
            title: "Came home",
            value: trip.actualEnd.map(environment.formatters.fullDateAndTime) ?? "—"
          )
          CMDivider()
          CMInfoRow(
            icon: "gauge",
            title: "Start reading",
            value: environment.formatters.odometer(trip.startOdometer, unit: unit)
          )
          CMDivider()
          CMInfoRow(
            icon: "gauge",
            title: "End reading",
            value: environment.formatters.odometer(trip.endOdometer, unit: unit)
          )
        }
      }

      if trip.hasReadingDiscontinuity {
        CMHint(
          text: "The odometer was replaced or reset during this trip, so its distance stays unknown.",
          icon: "exclamationmark.circle"
        )
      }
    }
  }

  @ViewBuilder
  private func closingWords(_ trip: Trip) -> some View {
    if !trip.finalNote.isEmpty {
      CMCard {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
          CMEyebrow(text: "Looking back")
          Text(trip.finalNote)
            .font(Font.CM.body)
            .foregroundColor(Theme.Colour.primaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  // MARK: - Timeline

  private func timeline(_ trip: Trip) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(title: "The journey, remembered")

      let events = JournalTimeline.events(for: trip)

      if events.isEmpty {
        CMCard {
          Text("No visits or notes were recorded on this trip.")
            .font(Font.CM.callout)
            .foregroundColor(Theme.Colour.secondaryText)
        }
      } else {
        ForEach(events) { event in
          switch event.kind {
          case .visit(let stop):
            NavigationLink {
              StopDetailView(tripID: tripID, stopID: stop.id)
            } label: {
              visitRow(stop, at: event.date)
            }
            .buttonStyle(.plain)

          case .note(let note):
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
  }

  private func visitRow(_ stop: Stop, at date: Date) -> some View {
    CMCard {
      HStack(spacing: Theme.Spacing.medium) {
        Image(systemName: stop.kind.icon)
          .font(.system(.body))
          .foregroundColor(Theme.Colour.primaryText)
          .frame(width: 42, height: 46)
          .background(Theme.Colour.action.opacity(0.5))
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))

        VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
          Text(stop.name)
            .font(Font.CM.labelEmphasis)
            .foregroundColor(Theme.Colour.primaryText)
            .multilineTextAlignment(.leading)

          Text("Arrived \(environment.formatters.dateAndTime(date))")
            .font(Font.CM.footnote)
            .foregroundColor(Theme.Colour.secondaryText)

          if let departure = stop.visit?.departure {
            Text("Left \(environment.formatters.dateAndTime(departure))")
              .font(Font.CM.footnote)
              .foregroundColor(Theme.Colour.secondaryText)
          }
        }

        Spacer(minLength: Theme.Spacing.small)

        Image(systemName: "chevron.right")
          .font(.system(.caption).weight(.semibold))
          .foregroundColor(Theme.Colour.secondaryText.opacity(0.6))
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func unreached(_ trip: Trip) -> some View {
    let others = trip.activeStops.filter { !$0.isVisited }

    if !others.isEmpty {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMSectionHeader(title: "Not this time", detail: "\(others.count)")

        CMRowList(elements: others) { stop in
          HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: stop.isSkipped ? "arrow.uturn.right" : "circle")
              .font(.system(.footnote))
              .foregroundColor(Theme.Colour.secondaryText)
              .frame(width: 24)

            VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
              Text(stop.name)
                .font(Font.CM.label)
                .foregroundColor(Theme.Colour.primaryText)
              if let reason = stop.skipReason {
                Text(reason)
                  .font(Font.CM.footnote)
                  .foregroundColor(Theme.Colour.secondaryText)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }

            Spacer(minLength: Theme.Spacing.small)

            Text(stop.isSkipped ? "Passed by" : "Not reached")
              .font(Font.CM.footnote)
              .foregroundColor(Theme.Colour.secondaryText)
          }
          .padding(.horizontal, Theme.Spacing.cardPadding)
          .padding(.vertical, Theme.Spacing.medium)
        }
      }
    }
  }

  // MARK: - Actions

  private func actions(_ trip: Trip) -> some View {
    VStack(spacing: Theme.Spacing.medium) {
      CMButton(title: "Take this trip again", icon: "arrow.triangle.2.circlepath") {
        repeatedTrip = environment.performReturning {
          try environment.useCases.duplicateTrip.execute(
            tripID: tripID,
            carryingHints: Set(trip.notes.filter(\.isPinnedForRepeat).map(\.id))
          )
        }
      }

      if trip.notes.contains(where: \.isPinnedForRepeat) {
        CMHint(text: "Your pinned notes come along as written hints, not as new events.")
      }

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMActionRow(icon: "pencil", title: "Edit the summary") { isEditingSummary = true }
          CMDivider()
          CMActionRow(icon: "square.and.arrow.up", title: "Export this trip") {
            isExporting = true
          }
          CMDivider()
          CMActionRow(
            icon: trip.isArchived ? "arrow.uturn.backward" : "archivebox",
            title: trip.isArchived ? "Restore this trip" : "Archive this trip",
            detail: trip.isArchived ? nil : "Keeps it out of the journal and reports"
          ) {
            environment.perform {
              try environment.useCases.setTripArchived.execute(
                tripID: tripID,
                isArchived: !trip.isArchived
              )
            }
          }
          CMDivider()
          CMActionRow(icon: "trash", title: "Delete this trip", isDestructive: true) {
            isConfirmingDelete = true
          }
        }
      }
    }
  }

  private var deletionMessage: String {
    guard let contents = environment.useCases.deleteTrip.contents(tripID: tripID) else {
      return "This removes the trip from your journal."
    }
    var parts = ["\(contents.stops) stops", "\(contents.notes) notes"]
    if contents.photos > 0 { parts.append("\(contents.photos) photos") }
    if contents.reminders > 0 { parts.append("\(contents.reminders) reminders") }
    return "This removes \(parts.joined(separator: ", ")). Your other trips are untouched."
  }
}

/// Puts a trip's visits and notes in the order they happened.
enum JournalTimeline {
  struct Event: Identifiable {
    enum Kind {
      case visit(Stop)
      case note(RoadNote)
    }

    let id: UUID
    let date: Date
    let kind: Kind
  }

  static func events(for trip: Trip) -> [Event] {
    let visits = trip.stops.compactMap { stop -> Event? in
      guard let visit = stop.visit else { return nil }
      return Event(id: stop.id, date: visit.arrival, kind: .visit(stop))
    }

    let notes = trip.notes.map { note in
      Event(id: note.id, date: note.recordedAt, kind: .note(note))
    }

    return (visits + notes).sorted { $0.date < $1.date }
  }
}
