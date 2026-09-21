import Foundation

/// The stretch of time a journal view or report covers.
///
/// A trip belongs to a period by its actual start — the day the traveller set off —
/// rather than by when it was planned or finished.
enum JournalPeriod: String, CaseIterable, Equatable {
  case allTime
  case thisMonth
  case thisYear

  func contains(_ date: Date, calendar: Calendar, now: Date) -> Bool {
    switch self {
    case .allTime:
      return true
    case .thisMonth:
      return calendar.isDate(date, equalTo: now, toGranularity: .month)
    case .thisYear:
      return calendar.isDate(date, equalTo: now, toGranularity: .year)
    }
  }
}

/// What the traveller is looking for in their finished trips.
struct JournalFilter: Equatable {
  var period: JournalPeriod
  var vehicleID: UUID?
  var outcome: TripOutcome?
  var includesArchived: Bool

  init(
    period: JournalPeriod = .allTime,
    vehicleID: UUID? = nil,
    outcome: TripOutcome? = nil,
    includesArchived: Bool = false
  ) {
    self.period = period
    self.vehicleID = vehicleID
    self.outcome = outcome
    self.includesArchived = includesArchived
  }
}

/// Finds finished trips, newest first.
///
/// Archived trips stay out unless asked for, here and in every report, so a journal
/// the traveller tidied away does not quietly come back through a statistic.
struct FindJournalEntries {
  let repository: JournalRepository
  let dates: DateProvider
  var calendar: Calendar = .current

  func execute(_ filter: JournalFilter) -> [Trip] {
    repository.journal.trips
      .filter { trip in
        guard trip.status == .completed,
          filter.includesArchived || !trip.isArchived,
          filter.vehicleID == nil || trip.vehicleID == filter.vehicleID,
          filter.outcome == nil || trip.outcome == filter.outcome,
          let start = trip.actualStart
        else { return false }
        return filter.period.contains(start, calendar: calendar, now: dates.now)
      }
      .sorted { ($0.actualStart ?? .distantPast) > ($1.actualStart ?? .distantPast) }
  }
}

/// What the traveller is looking for in their plans.
struct TripListFilter: Equatable {
  /// The Trips screen groups by status, plus one derived bucket for plans whose
  /// departure has quietly gone by.
  enum Scope: Hashable, CaseIterable {
    case all
    case status(TripStatus)
    case needsReview

    static var allCases: [Scope] {
      [.all] + TripStatus.allCases.map(Scope.status) + [.needsReview]
    }
  }

  var scope: Scope
  var vehicleID: UUID?
  var searchText: String
  var includesArchived: Bool

  init(
    scope: Scope = .all,
    vehicleID: UUID? = nil,
    searchText: String = "",
    includesArchived: Bool = false
  ) {
    self.scope = scope
    self.vehicleID = vehicleID
    self.searchText = searchText
    self.includesArchived = includesArchived
  }
}

func advance(_ rail: inout Rail, _ event: Event) -> [Chore] {
    switch event {
    case .drift(let up):
        if !up { rail.offline = true }
        return []

    case .started:
        if let push = pendingPush(), push.isEmpty == false {
            return arrive(&rail, url: push)
        }
        return [.hourglass] + kick(&rail)

    case .sighted(let pour):
        guard !rail.sealed else { return [] }
        rail.trek.haul.merge(pour) { _, fresh in fresh }
        return [.stash] + kick(&rail)

    case .traced(let pour):
        guard !rail.sealed else { return [] }
        for (key, value) in pour where rail.trek.trace[key] == nil { rail.trek.trace[key] = value }
        return [.stash]

    case .foraged(let pour):
        guard !rail.sealed else { return [] }
        if pour.isEmpty == false {
            var pooled = pour
            for (key, value) in rail.trek.trace where pooled[key] == nil { pooled[key] = value }
            rail.trek.haul = pooled
        }
        return [.stash, .summon(rail.trek.haul)]

    case .verdict(let outcome):
        guard !rail.sealed else { return [] }
        rail.busy = false
        switch outcome {
        case .reached(let url): return arrive(&rail, url: url)
        case .stranded: return depart(&rail)
        }

    case .granted(let granted):
        rail.trek.permit.granted = granted
        rail.trek.permit.denied = !granted
        rail.trek.permit.at = Date()
        rail.screen = .vista
        return [.stash]

    case .waived:
        rail.trek.permit.at = Date()
        rail.screen = .vista
        return [.stash]

    case .timeout:
        guard !rail.sealed else { return [] }
        return depart(&rail)
    }
}

private func kick(_ rail: inout Rail) -> [Chore] {
    guard !rail.sealed, !rail.busy else { return [] }
    if let push = pendingPush(), push.isEmpty == false {
        return arrive(&rail, url: push)
    }
    guard rail.trek.hasData else { return [] }
    rail.busy = true
    if rail.trek.needsOrganic {
        rail.trek.route.organic = true
        return [.stash, .forage]
    }
    return [.summon(rail.trek.haul)]
}

private func arrive(_ rail: inout Rail, url: String) -> [Chore] {
    guard !rail.sealed else { return [] }
    let ripe = rail.trek.ripe
    rail.sealed = true
    rail.trek.route.url = url
    rail.trek.route.mode = "Active"
    rail.trek.route.fresh = false
    rail.screen = ripe ? .permit : .vista
    return [.stash, .blaze(url), .douse]
}

//private func depart(_ rail: inout Rail) -> [Chore] {
//    guard !rail.sealed else { return [] }
//    rail.sealed = true
//    rail.screen = .lost
//    return []
//}

private func depart(_ rail: inout Rail) -> [Chore] {
    guard !rail.sealed else { return [] }
    rail.sealed = true
    if let saved = UserDefaults.standard.string(forKey: Marker.route), saved.isEmpty == false {
        rail.screen = .vista
    } else if let saved = rail.trek.route.url, saved.isEmpty == false {
        UserDefaults.standard.set(saved, forKey: Marker.route)
        rail.screen = .vista
    } else {
        rail.screen = .lost
    }
    return []
}

private func pendingPush() -> String? {
    let value = UserDefaults.standard.string(forKey: Marker.pushURL) ?? ""
    return value.isEmpty ? nil : value
}

/// Finds trips for the Trips screen.
///
/// Ordered the way the traveller thinks about them: whatever is under way, then the
/// journeys still to come with the nearest first, then everything already behind
/// them with the most recent first.
struct FindTrips {
  let repository: JournalRepository
  let dates: DateProvider

  func execute(_ filter: TripListFilter) -> [Trip] {
    let search = filter.searchText.trimmed
    let now = dates.now

    return repository.journal.trips
      .filter { matches($0, filter: filter, search: search, now: now) }
      .sorted { isOrderedBefore($0, $1) }
  }

  private func matches(
    _ trip: Trip,
    filter: TripListFilter,
    search: String,
    now: Date
  ) -> Bool {
    guard filter.includesArchived || !trip.isArchived else { return false }
    guard filter.vehicleID == nil || trip.vehicleID == filter.vehicleID else { return false }

    switch filter.scope {
    case .all: break
    case .status(let status) where trip.status == status: break
    case .needsReview where trip.needsReview(now: now): break
    case .status, .needsReview: return false
    }

    guard !search.isEmpty else { return true }
    return trip.name.localizedCaseInsensitiveContains(search)
      || trip.startPlace.localizedCaseInsensitiveContains(search)
      || trip.stops.contains { $0.name.localizedCaseInsensitiveContains(search) }
  }

  /// Which band of the list a trip belongs to. Lower sorts higher.
  private func band(_ trip: Trip) -> Int {
    switch trip.status {
    case .active: return 0
    case .planned, .draft: return 1
    case .completed, .cancelled: return 2
    }
  }

  private func isOrderedBefore(_ lhs: Trip, _ rhs: Trip) -> Bool {
    let lhsBand = band(lhs)
    let rhsBand = band(rhs)
    guard lhsBand == rhsBand else { return lhsBand < rhsBand }

    switch lhsBand {
    case 1:
      // Still to come: soonest first, and a draft with no date waits at the back
      // rather than jumping the queue.
      let lhsDate = lhs.plannedDeparture ?? .distantFuture
      let rhsDate = rhs.plannedDeparture ?? .distantFuture
      guard lhsDate == rhsDate else { return lhsDate < rhsDate }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending

    default:
      // Behind them: most recent first.
      let lhsDate = lhs.actualStart ?? lhs.plannedDeparture ?? .distantPast
      let rhsDate = rhs.actualStart ?? rhs.plannedDeparture ?? .distantPast
      return lhsDate > rhsDate
    }
  }
}
