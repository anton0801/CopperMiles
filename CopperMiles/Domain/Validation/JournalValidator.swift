import Foundation

/// Checks a whole journal before it is allowed to replace the traveller's own.
///
/// An import is the one moment records arrive from outside the app, so every
/// invariant the rest of the code relies on is re-established here: unique
/// identifiers, vehicles that exist, visits inside their trip. If anything fails the
/// current journal is left exactly as it was.
enum JournalValidator {
  static func validate(_ journal: Journal, now: Date) throws {
    try validateUniqueIdentifiers(journal)

    guard journal.trips.filter({ $0.status == .active }).count <= 1 else {
      throw DomainError("This backup holds more than one trip under way.")
    }

    for vehicle in journal.vehicles {
      _ = try VehicleValidator.validated(vehicle)
    }

    for trip in journal.trips {
      try validate(trip: trip, in: journal, now: now)
    }
  }

  private static func validate(trip: Trip, in journal: Journal, now: Date) throws {
    if let vehicleID = trip.vehicleID, journal.vehicle(vehicleID) == nil {
      throw DomainError("A trip in this backup refers to a vehicle that is not included.")
    }

    if trip.status != .draft && trip.status != .cancelled {
      try TripValidator.validatePlanned(trip)
    }

    try OdometerValidator.validate(trip.startOdometer)
    try OdometerValidator.validate(trip.endOdometer)

    if trip.status.hasStarted {
      guard let start = trip.actualStart, start <= now else {
        throw DomainError("A trip in this backup has an impossible start time.")
      }
    }

    if trip.status == .completed {
      guard let start = trip.actualStart,
        let end = trip.actualEnd,
        end >= start,
        end <= now,
        trip.outcome != nil,
        trip.openVisit == nil
      else {
        throw DomainError("A finished trip in this backup has an incomplete record.")
      }
    }

    for stop in trip.stops {
      _ = try StopValidator.validated(stop)
      guard let visit = stop.visit else { continue }
      try VisitValidator.validate(
        arrival: visit.arrival,
        departure: visit.departure,
        stopID: stop.id,
        in: trip,
        now: now
      )
    }

    for note in trip.notes {
      _ = try RoadNoteValidator.validated(note, in: trip, now: now)
    }
  }

  private static func validateUniqueIdentifiers(_ journal: Journal) throws {
    var seen = Set<UUID>()

    func claim(_ id: UUID) throws {
      guard seen.insert(id).inserted else {
        throw DomainError("This backup contains duplicate identifiers.")
      }
    }

    for vehicle in journal.vehicles {
      try claim(vehicle.id)
      try vehicle.preparationTemplate.forEach { try claim($0.id) }
    }
    for trip in journal.trips {
      try claim(trip.id)
      try trip.stops.forEach { try claim($0.id) }
      try trip.checklist.forEach { try claim($0.id) }
      try trip.notes.forEach { try claim($0.id) }
      try trip.reminders.forEach { try claim($0.id) }
    }
  }
}
