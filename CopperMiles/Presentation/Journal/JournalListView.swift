import SwiftUI

/// Finished trips, newest first.
struct JournalListView: View {
  @EnvironmentObject private var environment: AppEnvironment

  @State private var filter: JournalFilter
  @State private var isPlanningTrip = false

  /// Opened either as the Journal tab or from a figure in the travel summary, in
  /// which case it arrives carrying that figure's filters so the traveller lands on
  /// exactly the trips the number was counting.
  init(
    initialPeriod: JournalPeriod = .allTime,
    initialVehicleID: UUID? = nil,
    initialOutcome: TripOutcome? = nil,
    includesArchived: Bool = false
  ) {
    _filter = State(
      initialValue: JournalFilter(
        period: initialPeriod,
        vehicleID: initialVehicleID,
        outcome: initialOutcome,
        includesArchived: includesArchived
      )
    )
  }

  private var entries: [Trip] {
    environment.useCases.findJournalEntries.execute(filter)
  }

  private var hasAnyFinishedTrip: Bool {
    environment.journal.trips.contains { $0.status == .completed }
  }

  private var archivedCount: Int {
    environment.journal.trips.filter { $0.status == .completed && $0.isArchived }.count
  }

  var body: some View {
    CMScreen {
      CMScreenHeader(
        eyebrow: "The places stay with you",
        title: "Road memories",
        subtitle: "Little discoveries. Well-loved detours."
      )

      summaryLink
      filters

      if entries.isEmpty {
        emptyState
      } else {
        ForEach(entries) { trip in
          NavigationLink {
            JournalEntryView(tripID: trip.id)
          } label: {
            JournalCard(trip: trip)
          }
          .buttonStyle(.plain)
        }
      }

      if archivedCount > 0 {
        CMCard(padding: 0) {
          CMToggleRow(
            title: "Include archived trips",
            hint: "\(archivedCount) tidied away. Reports leave them out too.",
            isOn: $filter.includesArchived
          )
        }
      }
    }
    .navigationTitle("Journal")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isPlanningTrip) { NewTripFlow() }
  }

  private var summaryLink: some View {
    NavigationLink {
      TravelSummaryView()
    } label: {
      HStack(spacing: Theme.Spacing.medium) {
        Image(systemName: "chart.bar.xaxis")
          .font(.system(.title3))
          .foregroundColor(Theme.Colour.primaryText)

        VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
          Text("Your travel story")
            .font(Font.CM.labelEmphasis)
            .foregroundColor(Theme.Colour.primaryText)
          Text("The distance, the stops and the months you got out")
            .font(Font.CM.footnote)
            .foregroundColor(Theme.Colour.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: Theme.Spacing.small)

        Image(systemName: "arrow.up.right")
          .font(.system(.caption).weight(.semibold))
          .foregroundColor(Theme.Colour.secondaryText)
      }
      .padding(Theme.Spacing.cardPadding)
      .frame(maxWidth: .infinity)
      .background(Theme.Colour.action.opacity(0.5))
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var filters: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSegmentedPicker(
        options: JournalPeriod.allCases,
        title: \.displayName,
        selection: $filter.period
      )

      HStack(alignment: .top, spacing: Theme.Spacing.medium) {
        CMMenuPicker(
          title: "Outcome",
          options: [nil] + TripOutcome.allCases.map { Optional($0) },
          optionTitle: { $0?.displayName ?? "Any outcome" },
          selection: $filter.outcome
        )

        if environment.journal.vehicles.count > 1 {
          CMMenuPicker(
            title: "Vehicle",
            options: [nil] + environment.journal.vehicles.map { Optional($0.id) },
            optionTitle: { id in
              guard let id else { return "All vehicles" }
              return environment.vehicle(id)?.name ?? "Unknown"
            },
            selection: $filter.vehicleID
          )
        }
      }
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    if hasAnyFinishedTrip {
      CMEmptyState(
        illustration: .roadNotebook,
        illustrationSize: 88,
        title: "Nothing in this stretch",
        message: "No finished trips match these filters. Try a wider period."
      ) {
        CMButton(title: "Show everything", prominence: .secondary) {
          filter = JournalFilter(includesArchived: filter.includesArchived)
        }
      }
    } else {
      CMEmptyState(
        illustration: .roadNotebook,
        title: "The story starts out there",
        message: "Your finished trips, photos and little discoveries will find a home here."
      ) {
        CMButton(title: "Plan your first trip", icon: "plus") { isPlanningTrip = true }
      }
    }
  }
}

/// One journal entry in the list.
struct JournalCard: View {
  let trip: Trip

  @EnvironmentObject private var environment: AppEnvironment

  private var photoIDs: [AttachmentID] {
    Array(trip.notes.flatMap(\.photoIDs).prefix(3))
  }

  var body: some View {
    CMCard {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        HStack {
          CMTag(
            text: trip.outcome?.displayName ?? "Completed",
            colour: trip.outcome == .endedEarly ? Theme.Colour.accent : Theme.Colour.success
          )
          if trip.isArchived {
            CMTag(text: "Archived")
          }
          Spacer()
          Text(trip.actualStart.map(environment.formatters.day) ?? "")
            .font(Font.CM.footnote)
            .foregroundColor(Theme.Colour.secondaryText)
        }

        Text(trip.name)
          .font(Font.CM.cardTitle)
          .foregroundColor(Theme.Colour.primaryText)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        Text(environment.vehicleName(trip.vehicleID))
          .font(Font.CM.footnote)
          .foregroundColor(Theme.Colour.secondaryText)

        HStack(spacing: Theme.Spacing.large) {
          Label(
            environment.formatters.duration(trip.elapsed(until: environment.dates.now)),
            systemImage: "clock"
          )

          Label(
            environment.formatters.distance(
              trip.recordedDistance,
              unit: environment.unit(forTrip: trip)
            ),
            systemImage: "arrow.left.and.right"
          )

          Spacer()
        }
        .font(Font.CM.footnote)
        .foregroundColor(Theme.Colour.secondaryText)

        if !photoIDs.isEmpty {
          HStack(spacing: Theme.Spacing.small) {
            ForEach(photoIDs, id: \.self) { id in
              CMPhoto(id: id)
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            }
          }
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
