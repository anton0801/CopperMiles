import Foundation

/// Adds a stop to a plan or stores an edit to one.
///
/// Promoting a stop to Destination demotes whichever stop held that role, because a
/// plan has exactly one place it is heading for, and it is always last.
struct SaveStop {
  let repository: JournalRepository

  @discardableResult
  func execute(tripID: UUID, stop: Stop) throws -> Stop {
    let validated = try StopValidator.validated(stop)

    try repository.updateTrip(tripID) { trip in
      if validated.kind == .destination {
        for index in trip.stops.indices
        where trip.stops[index].id != validated.id && trip.stops[index].kind == .destination {
          trip.stops[index].kind = .custom
        }
      }

      if let index = trip.index(ofStop: validated.id) {
        trip.stops[index] = validated
      } else {
        // A new stop joins the plan just before the destination, which stays last.
        let insertion = trip.stops.last?.kind == .destination ? trip.stops.count - 1 : trip.stops.count
        trip.stops.insert(validated, at: max(0, insertion))
      }

      trip.stops = TripValidator.movingDestinationLast(trip.stops)
    }
    return validated
  }
}

/// Makes another stop the place the trip is heading for.
///
/// The stop that held the role becomes an ordinary one, and the new destination
/// moves to the end of the plan. This is the only way out of a destination the
/// traveller has changed their mind about, since `RemoveStop` refuses to delete the
/// one the trip is aiming at.
struct SetDestination {
  let repository: JournalRepository

  /// Whether this stop could take the role.
  static func canBecomeDestination(_ stop: Stop, in trip: Trip) -> Bool {
    stop.kind != .destination && !stop.isArchived && trip.status != .cancelled
  }

  func execute(tripID: UUID, stopID: UUID) throws {
    try repository.updateTrip(tripID) { trip in
      guard let index = trip.index(ofStop: stopID) else {
        throw DomainError.journalUnavailable
      }
      guard Self.canBecomeDestination(trip.stops[index], in: trip) else {
        throw DomainError("This is already where the trip is heading.")
      }

      for other in trip.stops.indices where trip.stops[other].kind == .destination {
        trip.stops[other].kind = .custom
      }
      trip.stops[index].kind = .destination
      trip.stops = TripValidator.movingDestinationLast(trip.stops)
    }
  }
}

/// Reorders the places along the way.
///
/// The destination stays at the end, and once a trip is under way only the stops
/// still ahead may be rearranged — the road already travelled is a record, not a
/// plan.
struct MoveStop {
  let repository: JournalRepository

  static func isMovable(_ stop: Stop, in trip: Trip) -> Bool {
    guard stop.kind != .destination, !stop.isArchived else { return false }
    guard trip.status != .completed, trip.status != .cancelled else { return false }
    return trip.status == .active ? stop.isOutstanding : true
  }

  /// Moves a stop one place earlier (`-1`) or later (`+1`) in the plan.
  func execute(tripID: UUID, stopID: UUID, offset: Int) throws {
    try repository.updateTrip(tripID) { trip in
      let movable = trip.stops.enumerated().filter { Self.isMovable($0.element, in: trip) }
      guard let position = movable.firstIndex(where: { $0.element.id == stopID }) else {
        throw DomainError("This stop stays where it is.")
      }
      let target = position + offset
      guard movable.indices.contains(target) else {
        throw DomainError(
          offset < 0
            ? "This is already the first stop you can move."
            : "This is already the last stop you can move."
        )
      }
      trip.stops.swapAt(movable[position].offset, movable[target].offset)
    }
  }
}

/// Removes a stop, or keeps it as a record when it has already been visited.
///
/// A visited stop is archived rather than deleted: the plan loses it, the journal
/// keeps the afternoon spent there.
struct RemoveStop {
  let repository: JournalRepository

  enum Outcome: Equatable {
    case deleted
    case archived
  }

  func plannedOutcome(tripID: UUID, stopID: UUID) -> Outcome? {
    guard let stop = repository.journal.trip(tripID)?.stop(stopID) else { return nil }
    return stop.isVisited ? .archived : .deleted
  }

  @discardableResult
  func execute(tripID: UUID, stopID: UUID) throws -> Outcome {
    var outcome = Outcome.deleted

    try repository.updateTrip(tripID) { trip in
      guard let index = trip.index(ofStop: stopID) else {
        throw DomainError.journalUnavailable
      }
      let stop = trip.stops[index]

      if stop.kind == .destination {
        throw DomainError(
          "This is where you are heading. Make another stop the destination first."
        )
      }

      if stop.isVisited {
        // Archiving would take it out of the plan while `openVisit` still points at
        // it, leaving the traveller unable to find the stop that blocks finishing.
        guard stop.visit?.isOpen != true else {
          throw DomainError("Record leaving \(stop.name) before taking it out of the plan.")
        }
        trip.stops[index].isArchived = true
        outcome = .archived
      } else {
        trip.stops.remove(at: index)
        for noteIndex in trip.notes.indices where trip.notes[noteIndex].stopID == stopID {
          trip.notes[noteIndex].stopID = nil
        }
        outcome = .deleted
      }
    }
    return outcome
  }
}

/// Plans the same place again, as a separate stop.
///
/// Returning somewhere is a second visit to a second stop, so each stay keeps its
/// own arrival, departure and notes rather than overwriting the first.
struct DuplicateStop {
  let repository: JournalRepository

  @discardableResult
  func execute(tripID: UUID, stopID: UUID) throws -> Stop {
    guard let source = repository.journal.trip(tripID)?.stop(stopID) else {
      throw DomainError.journalUnavailable
    }
    return try SaveStop(repository: repository).execute(tripID: tripID, stop: source.replanned())
  }
}
