import Foundation

/// Checks a trip's plan.
///
/// A draft may be as incomplete as the traveller likes. The rules below apply the
/// moment a trip becomes Planned, because from then on it can be started.
enum TripValidator {
  /// One planned arrival that cannot be right, with the reason why.
  ///
  /// Conflicts are gathered rather than thrown one at a time: the traveller should
  /// see every line that needs attention, not be sent back for each in turn.
  struct ScheduleConflict: Identifiable, Equatable {
    let id: UUID
    let stopName: String
    let reason: String
  }

  /// Normalises a trip for storage: trimmed text, the destination held last.
  static func normalised(_ trip: Trip) throws -> Trip {
    var trip = trip
    trip.name = trip.name.trimmed
    trip.startPlace = trip.startPlace.trimmed
    trip.note = trip.note.trimmed
    trip.endReason = trip.endReason.trimmed
    trip.finalNote = trip.finalNote.trimmed
    trip.stops = try trip.stops.map(StopValidator.validated)
    trip.stops = movingDestinationLast(trip.stops)
    return trip
  }

  /// The destination always sits at the end of the plan, whatever order editing left
  /// the stops in.
  static func movingDestinationLast(_ stops: [Stop]) -> [Stop] {
    guard let index = stops.lastIndex(where: { $0.kind == .destination }) else { return stops }
    var stops = stops
    let destination = stops.remove(at: index)
    stops.append(destination)
    return stops
  }

  /// Everything a trip needs before it may be saved as Planned.
  static func validatePlanned(_ trip: Trip) throws {
    guard !trip.name.isBlank else {
      throw DomainError("Give your trip a name.")
    }
    guard trip.vehicleID != nil else {
      throw DomainError("Choose the vehicle you will travel in.")
    }
    guard let departure = trip.plannedDeparture else {
      throw DomainError("Choose a planned departure.")
    }
    guard !trip.startPlace.isBlank else {
      throw DomainError("Add the place you will set off from.")
    }
    guard Trip.travellerRange.contains(trip.travellers) else {
      throw DomainError("A trip carries between 1 and 9 travellers.")
    }
    if let end = trip.expectedEnd, end <= departure {
      throw DomainError("The expected end must come after the departure.")
    }

    let destinations = trip.stops.filter { $0.kind == .destination }
    guard destinations.count == 1 else {
      throw DomainError(
        destinations.isEmpty
          ? "Add the destination you are heading for."
          : "A trip has exactly one final destination."
      )
    }
    guard trip.stops.last?.kind == .destination else {
      throw DomainError("The destination is the last stop of the plan.")
    }

    for stop in trip.stops {
      _ = try StopValidator.validated(stop)
    }

    let conflicts = scheduleConflicts(in: trip)
    guard conflicts.isEmpty else {
      throw DomainError(
        "Some planned arrivals need a look:\n"
          + conflicts.map { "· \($0.stopName): \($0.reason)" }.joined(separator: "\n")
      )
    }
  }

  /// Planned arrivals that fall outside the trip or out of order.
  ///
  /// Nothing is moved on the traveller's behalf — these are their own times, and the
  /// interface offers the lines to correct instead of quietly rewriting them.
  static func scheduleConflicts(in trip: Trip) -> [ScheduleConflict] {
    var conflicts: [ScheduleConflict] = []
    var previousArrival: Date?
    var previousName: String?

    for stop in trip.activeStops {
      guard let arrival = stop.plannedArrival else { continue }

      if let departure = trip.plannedDeparture, arrival < departure {
        conflicts.append(
          ScheduleConflict(
            id: stop.id,
            stopName: stop.name,
            reason: "arrives before the trip leaves"
          )
        )
      } else if let end = trip.expectedEnd, arrival > end {
        conflicts.append(
          ScheduleConflict(
            id: stop.id,
            stopName: stop.name,
            reason: "arrives after the expected end"
          )
        )
      } else if let previousArrival, let previousName, arrival < previousArrival {
        conflicts.append(
          ScheduleConflict(
            id: stop.id,
            stopName: stop.name,
            reason: "arrives before \(previousName), which comes earlier in the plan"
          )
        )
      }

      previousArrival = arrival
      previousName = stop.name
    }
    return conflicts
  }

  /// Other planned trips for the same vehicle whose dates overlap this one.
  ///
  /// This is a warning, never a refusal: two plans for one car on the same weekend
  /// may well be intentional, and only the traveller knows.
  static func overlappingTrips(with trip: Trip, in journal: Journal) -> [Trip] {
    guard let vehicleID = trip.vehicleID, let departure = trip.plannedDeparture else { return [] }
    let end = trip.expectedEnd ?? departure

    return journal.trips.filter { other in
      guard other.id != trip.id,
        other.vehicleID == vehicleID,
        !other.isArchived,
        other.status.isPlanning,
        let otherDeparture = other.plannedDeparture
      else { return false }

      let otherEnd = other.expectedEnd ?? otherDeparture
      return departure <= otherEnd && otherDeparture <= end
    }
  }
}
