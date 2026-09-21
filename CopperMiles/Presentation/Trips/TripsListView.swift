import SwiftUI

/// Every trip, from first idea to last detour.
struct TripsListView: View {
  @EnvironmentObject private var environment: AppEnvironment

  @State private var filter: TripListFilter
  @State private var isCreating = false

  init(initialScope: TripListFilter.Scope = .all, initialVehicleID: UUID? = nil) {
    _filter = State(
      initialValue: TripListFilter(scope: initialScope, vehicleID: initialVehicleID)
    )
  }

  private var trips: [Trip] {
    environment.useCases.findTrips.execute(filter)
  }

  private var archivedCount: Int {
    environment.journal.trips.filter(\.isArchived).count
  }

  var body: some View {
    CMScreen {
      CMScreenHeader(
        eyebrow: "The open road is calling",
        title: "Your trips",
        subtitle: "From the first idea to the last little detour."
      )

      CMSearchField(placeholder: "Find a trip, place or stop", text: $filter.searchText)

      CMChipRow(
        options: TripListFilter.Scope.allCases,
        title: \.displayName,
        selection: $filter.scope
      )

      if environment.journal.vehicles.count > 1 {
        vehicleFilter
      }

      if trips.isEmpty {
        emptyState
      } else {
        ForEach(trips) { trip in
          NavigationLink {
            destination(for: trip)
          } label: {
            TripCard(trip: trip, isHighlighted: trip.status == .active)
          }
          .buttonStyle(.plain)
        }
      }

      CMButton(title: "Plan a new trip", icon: "plus") { isCreating = true }

      if archivedCount > 0 {
        CMCard(padding: 0) {
          CMToggleRow(
            title: "Include archived trips",
            hint: "\(archivedCount) tidied away",
            isOn: $filter.includesArchived
          )
        }
      }
    }
    .navigationTitle("Trips")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isCreating) { NewTripFlow() }
  }

  @ViewBuilder
  private func destination(for trip: Trip) -> some View {
    if trip.status == .active {
      OnTheRoadView(tripID: trip.id)
    } else if trip.status == .completed {
      JournalEntryView(tripID: trip.id)
    } else {
      TripPlanView(tripID: trip.id)
    }
  }

  private var vehicleFilter: some View {
    CMMenuPicker(
      title: "Vehicle",
      options: [nil] + environment.journal.vehicles.map { Optional($0.id) },
      optionTitle: { id in
        guard let id else { return "All vehicles" }
        return environment.vehicle(id)?.name ?? "Unknown vehicle"
      },
      selection: $filter.vehicleID
    )
  }

  @ViewBuilder
  private var emptyState: some View {
    if filter.searchText.isBlank && filter.scope == .all && filter.vehicleID == nil {
      CMEmptyState(
        illustration: .roadSign,
        title: "A new road awaits",
        message: "Your plans will feel right at home here. Start with somewhere you’d love to go."
      )
    } else {
      CMEmptyState(
        illustration: .roadSign,
        illustrationSize: 88,
        title: "Nothing matches",
        message: "Try another filter, or clear the search to see everything again."
      ) {
        CMButton(title: "Show all trips", prominence: .secondary) {
          filter = TripListFilter(includesArchived: filter.includesArchived)
        }
      }
    }
  }
}
