import Foundation

/// Checks a recorded stay at a stop.
///
/// Visits are the backbone of the journal's timeline, so their times must sit inside
/// the trip, in order, and never in the future.
enum VisitValidator {
  static func validate(
    arrival: Date,
    departure: Date?,
    stopID: UUID,
    in trip: Trip,
    now: Date
  ) throws {
    guard trip.status.hasStarted, let start = trip.actualStart else {
      throw DomainError("Start the trip before recording a visit.")
    }

    let tripEnd = trip.actualEnd ?? now

    guard arrival >= start else {
      throw DomainError("An arrival cannot come before the trip started.")
    }
    guard arrival <= now else {
      throw DomainError("An arrival cannot be in the future.")
    }
    guard arrival <= tripEnd else {
      throw DomainError("An arrival cannot come after the trip ended.")
    }

    if let departure {
      guard departure >= arrival else {
        throw DomainError("Leaving a stop cannot come before arriving at it.")
      }
      guard departure <= now else {
        throw DomainError("A departure cannot be in the future.")
      }
      guard departure <= tripEnd else {
        throw DomainError("A departure cannot come after the trip ended.")
      }
    } else {
      guard trip.status != .completed else {
        throw DomainError("A finished trip cannot hold an open visit.")
      }
      if let open = trip.openVisit, open.id != stopID {
        throw DomainError(
          "You are still at \(open.name). Record leaving there before arriving somewhere else."
        )
      }
    }

    try validateNoOverlap(arrival: arrival, departure: departure, stopID: stopID, in: trip)
  }

  private static func validateNoOverlap(
    arrival: Date,
    departure: Date?,
    stopID: UUID,
    in trip: Trip
  ) throws {
    let end = departure ?? .distantFuture

    for other in trip.stops where other.id != stopID {
      guard let visit = other.visit else { continue }
      let otherEnd = visit.departure ?? .distantFuture
      guard arrival < otherEnd, visit.arrival < end else { continue }
      throw DomainError(
        "These times overlap your visit to \(other.name). Correct that visit first."
      )
    }
  }
}
