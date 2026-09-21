import Foundation

/// The traveller's own history, gathered up.
///
/// Every figure here is something they recorded. There is no fuel economy, no
/// driver score and no speed inferred from a handful of timestamps — the summary
/// reports the journal, it does not guess beyond it.
struct TravelSummary: Equatable {
  /// One vehicle's share of the period.
  struct VehicleRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let tripCount: Int
    let distance: Double
  }

  /// Finished trips in one month, for the twelve-month chart.
  struct MonthlyCount: Identifiable, Equatable {
    let id: Date
    let month: Date
    let count: Int
  }

  let periodStart: Date?
  let completedTrips: Int
  let endedEarlyTrips: Int
  let visitedStops: Int

  /// Totalled in the report unit; trips without a trustworthy reading add nothing
  /// rather than counting as zero distance travelled.
  let recordedDistance: Double
  let reportUnit: DistanceUnit
  let tripsWithDistance: Int
  let finishedTrips: Int

  /// The whole length of the trips, stops included. Never called driving time.
  let elapsedTime: TimeInterval

  let vehicleRows: [VehicleRow]
  let monthlyCounts: [MonthlyCount]

  var isEmpty: Bool { finishedTrips == 0 }
}

/// Builds the travel summary for a period.
struct BuildTravelSummary {
  let repository: JournalRepository
  let entries: FindJournalEntries
  let dates: DateProvider
  var calendar: Calendar = .current

  func execute(_ filter: JournalFilter) -> TravelSummary {
    let journal = repository.journal
    let trips = entries.execute(filter)
    let reportUnit = journal.settings.reportUnit

    /// A trip's distance in the report unit, or `nil` when it has none to give.
    func distance(of trip: Trip) -> Double? {
      guard let value = trip.recordedDistance else { return nil }
      let unit = journal.vehicle(trip.vehicleID)?.unit ?? reportUnit
      return unit.converting(value, to: reportUnit)
    }

    let distances = trips.compactMap(distance)

    let vehicleRows = journal.vehicles
      .compactMap { vehicle -> TravelSummary.VehicleRow? in
        let vehicleTrips = trips.filter { $0.vehicleID == vehicle.id }
        guard !vehicleTrips.isEmpty else { return nil }
        return TravelSummary.VehicleRow(
          id: vehicle.id,
          name: vehicle.name,
          tripCount: vehicleTrips.count,
          distance: vehicleTrips.compactMap(distance).reduce(0, +)
        )
      }
      .sorted { $0.tripCount > $1.tripCount }

    return TravelSummary(
      periodStart: trips.compactMap(\.actualStart).min(),
      completedTrips: trips.filter { $0.outcome == .completed }.count,
      endedEarlyTrips: trips.filter { $0.outcome == .endedEarly }.count,
      visitedStops: trips.reduce(0) { $0 + $1.visitedStops.count },
      recordedDistance: distances.reduce(0, +),
      reportUnit: reportUnit,
      tripsWithDistance: distances.count,
      finishedTrips: trips.count,
      elapsedTime: trips.reduce(0) { $0 + ($1.elapsed(until: dates.now) ?? 0) },
      vehicleRows: vehicleRows,
      monthlyCounts: monthlyCounts(for: trips)
    )
  }

  /// Twelve months up to now, including the empty ones so the chart keeps its shape.
  private func monthlyCounts(for trips: [Trip]) -> [TravelSummary.MonthlyCount] {
    let now = dates.now
    let months = (0..<12).reversed().compactMap {
      calendar.date(byAdding: .month, value: -$0, to: now)
    }

    return months.map { month in
      let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
      let count = trips.filter { trip in
        guard let date = trip.actualStart else { return false }
        return calendar.isDate(date, equalTo: month, toGranularity: .month)
      }.count
      return TravelSummary.MonthlyCount(id: start, month: month, count: count)
    }
  }
}
