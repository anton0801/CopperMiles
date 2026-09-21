import Foundation

/// Writes a road note, with any photos the traveller attached.
///
/// A photo that cannot be imported never costs the traveller their words: the text
/// is saved either way, and the failure is reported on its own.
struct SaveRoadNote {
  let repository: JournalRepository
  let attachments: AttachmentStore
  let dates: DateProvider

  func execute(tripID: UUID, note: RoadNote, addedPhotos: [Data] = []) throws {
    guard let trip = repository.journal.trip(tripID) else {
      throw DomainError.journalUnavailable
    }

    var candidate = note
    let room = RoadNote.maximumPhotos - candidate.photoIDs.count
    guard addedPhotos.count <= room else {
      throw DomainError("A note carries up to three photos.")
    }

    let previous = trip.notes.first { $0.id == note.id }
    var storedIDs: [AttachmentID] = []
    for data in addedPhotos {
      storedIDs.append(try attachments.store(data))
    }
    candidate.photoIDs.append(contentsOf: storedIDs)

    let validated: RoadNote
    do {
      validated = try RoadNoteValidator.validated(candidate, in: trip, now: dates.now)
    } catch {
      attachments.remove(storedIDs)
      throw error
    }

    try repository.updateTrip(tripID) { trip in
      if let index = trip.notes.firstIndex(where: { $0.id == validated.id }) {
        trip.notes[index] = validated
      } else {
        trip.notes.append(validated)
      }
    }

    if let previous {
      let dropped = Set(previous.photoIDs).subtracting(validated.photoIDs)
      attachments.remove(Array(dropped))
    }
  }
}

/// Removes a note and the photos that belong to it.
struct DeleteRoadNote {
  let repository: JournalRepository
  let attachments: AttachmentStore

  func execute(tripID: UUID, noteID: UUID) throws {
    let photoIDs = repository.journal.trip(tripID)?
      .notes.first { $0.id == noteID }?
      .photoIDs ?? []

    try repository.updateTrip(tripID) { trip in
      trip.notes.removeAll { $0.id == noteID }
    }

    attachments.remove(photoIDs)
  }
}
