import Foundation

/// Checks a note written on the road.
enum RoadNoteValidator {
  static func validated(_ note: RoadNote, in trip: Trip, now: Date) throws -> RoadNote {
    var note = note
    note.text = note.text.trimmed

    guard !note.text.isEmpty else {
      throw DomainError("Write something to remember.")
    }
    guard note.text.count <= RoadNote.maximumCharacters else {
      throw DomainError("A note holds up to 2,000 characters.")
    }
    guard note.photoIDs.count <= RoadNote.maximumPhotos else {
      throw DomainError("A note carries up to three photos.")
    }

    guard let start = trip.actualStart else {
      throw DomainError(
        "Road notes belong to a trip that has started. Use the trip note while you are still planning."
      )
    }
    guard note.recordedAt >= start else {
      throw DomainError("This time falls before the trip started.")
    }
    guard note.recordedAt <= now else {
      throw DomainError("A note cannot be recorded in the future.")
    }
    if let end = trip.actualEnd, note.recordedAt > end {
      throw DomainError("This time falls after the trip ended.")
    }
    if let stopID = note.stopID, trip.stop(stopID) == nil {
      throw DomainError("The stop this note belongs to is no longer in the plan.")
    }

    return note
  }
}
