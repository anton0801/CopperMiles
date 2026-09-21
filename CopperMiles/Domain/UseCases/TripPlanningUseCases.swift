import Foundation

/// Adds a trip or stores an edit to one.
///
/// A draft may be saved in any state of incompleteness; asking for Planned applies
/// the full set of rules, because a planned trip is one that can be started.
struct SaveTrip {
  let repository: JournalRepository
  let reminders: RefreshTripReminders

  @discardableResult
  func execute(_ trip: Trip, asPlanned: Bool) throws -> Trip {
    let existing = repository.journal.trip(trip.id)
    var candidate = try TripValidator.normalised(trip)

    if candidate.status.isPlanning {
      candidate.status = asPlanned ? .planned : .draft
    }

    if existing == nil, candidate.checklist.isEmpty {
      candidate.checklist = repository.journal.vehicle(candidate.vehicleID)?.newChecklist() ?? []
    }

    if asPlanned {
      try TripValidator.validatePlanned(candidate)
    }

    // A trip that is no longer being planned can never ring: cancelling here keeps
    // the stored flags honest even if the scheduler is unreachable.
    if !candidate.status.isPlanning || candidate.isArchived {
      candidate.reminders = candidate.reminders.map(\.cancelled)
    }

    try repository.apply { journal in
      if let index = journal.trips.firstIndex(where: { $0.id == candidate.id }) {
        journal.trips[index] = candidate
      } else {
        journal.trips.append(candidate)
      }
    }

    let departureMoved = existing?.plannedDeparture != candidate.plannedDeparture
    if !candidate.reminders.isEmpty, departureMoved || !candidate.status.isPlanning {
      Task { await reminders.execute(tripID: candidate.id) }
    }

    return candidate
  }
}

/// Builds a fresh draft from a trip the traveller enjoyed.
///
/// The new plan keeps the vehicle, the places and the shape of the checklist, and
/// none of the journey already travelled: no dates, no odometer, no visits, no ticks.
/// Pinned notes come across as written preparation hints, not as events.
struct DuplicateTrip {
  let repository: JournalRepository

  func execute(tripID: UUID, carryingHints hintIDs: Set<UUID> = []) throws -> Trip {
    guard let source = repository.journal.trip(tripID) else {
      throw DomainError.journalUnavailable
    }

    var copy = source.duplicated()
    let hints = source.notes
      .filter { $0.isPinnedForRepeat && hintIDs.contains($0.id) }
      .map(\.text)

    if !hints.isEmpty {
      let heading = "Worth remembering from last time:"
      let block = ([heading] + hints.map { "· \($0)" }).joined(separator: "\n")
      copy.note = copy.note.isEmpty ? block : copy.note + "\n\n" + block
    }
    return copy
  }
}

/// Puts a plan aside without losing it.
struct CancelTrip {
  let repository: JournalRepository
  let reminders: ReminderScheduling

  func execute(tripID: UUID) throws {
    guard let trip = repository.journal.trip(tripID) else {
      throw DomainError.journalUnavailable
    }
    guard trip.status.isPlanning else {
      throw DomainError(
        trip.status == .active
          ? "This trip is under way. Finish it rather than cancelling it."
          : "Only a plan that has not started can be cancelled."
      )
    }

    let reminderIDs = trip.reminders.map(\.id)

    try repository.updateTrip(tripID) { trip in
      trip.status = .cancelled
      trip.reminders = trip.reminders.map(\.cancelled)
    }

    // Clearing the stored flags is not enough: a notification the system has
    // already accepted would still arrive for a trip that is no longer happening.
    reminders.cancel(ids: reminderIDs)
  }
}

/// Removes a trip and everything attached to it.
struct DeleteTrip {
  let repository: JournalRepository
  let attachments: AttachmentStore
  let reminders: ReminderScheduling

  /// What will go with the trip, listed before the traveller confirms.
  struct Contents: Equatable {
    let stops: Int
    let notes: Int
    let photos: Int
    let reminders: Int
  }

  func contents(tripID: UUID) -> Contents? {
    guard let trip = repository.journal.trip(tripID) else { return nil }
    return Contents(
      stops: trip.stops.count,
      notes: trip.notes.count,
      photos: trip.notes.reduce(0) { $0 + $1.photoIDs.count },
      reminders: trip.reminders.count
    )
  }

  func execute(tripID: UUID) throws {
    guard let trip = repository.journal.trip(tripID) else {
      throw DomainError.journalUnavailable
    }
    guard trip.status != .active else {
      throw DomainError("Finish the trip under way before deleting it.")
    }

    let photoIDs = trip.notes.flatMap(\.photoIDs)
    let reminderIDs = trip.reminders.map(\.id)

    try repository.apply { journal in
      journal.trips.removeAll { $0.id == tripID }
    }

    reminders.cancel(ids: reminderIDs)
    attachments.remove(photoIDs)
  }
}

/// Keeps a finished trip out of the everyday journal, or brings it back.
struct SetTripArchived {
  let repository: JournalRepository
  let reminders: ReminderScheduling

  func execute(tripID: UUID, isArchived: Bool) throws {
    guard let trip = repository.journal.trip(tripID) else {
      throw DomainError.journalUnavailable
    }
    guard trip.status != .active else {
      throw DomainError("Finish the trip under way before archiving it.")
    }

    try repository.updateTrip(tripID) { trip in
      trip.isArchived = isArchived
      if isArchived {
        trip.reminders = trip.reminders.map(\.cancelled)
      }
    }

    if isArchived {
      reminders.cancel(ids: trip.reminders.map(\.id))
    }
  }
}
