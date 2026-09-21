import Foundation

/// Records arriving at a stop, or corrects the times of a stay.
///
/// Arriving marks the stop visited the moment it is saved. Reaching the destination
/// does not end the trip: the traveller decides when the journey is over.
struct RecordVisit {
  let repository: JournalRepository
  let dates: DateProvider

  func arriveNow(tripID: UUID, stopID: UUID) throws {
    try execute(tripID: tripID, stopID: stopID, arrival: dates.now, departure: nil)
  }

  func leaveNow(tripID: UUID, stopID: UUID) throws {
    guard let arrival = repository.journal.trip(tripID)?.stop(stopID)?.visit?.arrival else {
      throw DomainError("Record arriving here before leaving.")
    }
    try execute(tripID: tripID, stopID: stopID, arrival: arrival, departure: dates.now)
  }

  func execute(tripID: UUID, stopID: UUID, arrival: Date, departure: Date?) throws {
    try repository.updateTrip(tripID) { trip in
      guard let index = trip.index(ofStop: stopID) else {
        throw DomainError.journalUnavailable
      }
      try VisitValidator.validate(
        arrival: arrival,
        departure: departure,
        stopID: stopID,
        in: trip,
        now: dates.now
      )
      trip.stops[index].visit = Visit(arrival: arrival, departure: departure)
      trip.stops[index].skipReason = nil
    }
  }
}

/// Takes a visit back off a stop.
///
/// Notes written there are not collateral: the traveller chooses whether they stay
/// in the journal as trip notes or go with the visit.
struct RemoveVisit {
  let repository: JournalRepository
  let attachments: AttachmentStore

  enum NoteHandling: Equatable {
    case keepAsTripNotes
    case deleteWithVisit
  }

  func execute(tripID: UUID, stopID: UUID, notes handling: NoteHandling) throws {
    var removedPhotoIDs: [AttachmentID] = []

    try repository.updateTrip(tripID) { trip in
      guard let index = trip.index(ofStop: stopID) else {
        throw DomainError.journalUnavailable
      }
      trip.stops[index].visit = nil
      trip.stops[index].skipReason = nil

      switch handling {
      case .keepAsTripNotes:
        for noteIndex in trip.notes.indices where trip.notes[noteIndex].stopID == stopID {
          trip.notes[noteIndex].stopID = nil
        }
      case .deleteWithVisit:
        removedPhotoIDs = trip.notes.filter { $0.stopID == stopID }.flatMap(\.photoIDs)
        trip.notes.removeAll { $0.stopID == stopID }
      }
    }

    attachments.remove(removedPhotoIDs)
  }
}

/// Marks a stop as one the traveller decided to pass by, or undoes that.
///
/// A skipped stop is not a visited one, and it is not a failure either — the reason
/// is kept with it rather than appended to the traveller's own notes.
struct SkipStop {
  let repository: JournalRepository

  func skip(tripID: UUID, stopID: UUID, reason: String) throws {
    let reason = reason.trimmed
    guard !reason.isEmpty else {
      throw DomainError("Add a short reason for passing this stop by.")
    }

    try repository.updateTrip(tripID) { trip in
      guard let index = trip.index(ofStop: stopID) else {
        throw DomainError.journalUnavailable
      }
      guard trip.stops[index].visit == nil else {
        throw DomainError("You have already been here. Remove the visit first.")
      }
      trip.stops[index].skipReason = reason
    }
  }

  func undo(tripID: UUID, stopID: UUID) throws {
    try repository.updateTrip(tripID) { trip in
      guard let index = trip.index(ofStop: stopID) else {
        throw DomainError.journalUnavailable
      }
      trip.stops[index].skipReason = nil
    }
  }
}
