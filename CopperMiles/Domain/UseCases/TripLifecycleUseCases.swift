import Foundation

/// Turns a plan into a journey under way.
///
/// Confirming is one step: the trip becomes active and its actual start is recorded
/// together, so tapping twice cannot open a second session.
struct StartTrip {
  let repository: JournalRepository
  let dates: DateProvider
  let reminders: ReminderScheduling

  struct Request {
    var tripID: UUID
    var actualStart: Date
    var startOdometer: Double?
    var explanation: OdometerExplanation?
    var allowsOpenImportantItems: Bool

    init(
      tripID: UUID,
      actualStart: Date,
      startOdometer: Double? = nil,
      explanation: OdometerExplanation? = nil,
      allowsOpenImportantItems: Bool = false
    ) {
      self.tripID = tripID
      self.actualStart = actualStart
      self.startOdometer = startOdometer
      self.explanation = explanation
      self.allowsOpenImportantItems = allowsOpenImportantItems
    }
  }

  func execute(_ request: Request) throws {
    let journal = repository.journal
    guard let trip = journal.trip(request.tripID) else {
      throw DomainError.journalUnavailable
    }
    guard trip.status == .planned else {
      throw DomainError(
        trip.status == .active
          ? "This trip is already under way."
          : "Save this trip as Planned before starting it."
      )
    }
    if let active = journal.activeTrip, active.id != trip.id {
      throw DomainError("\(active.name) is already under way. Continue or finish it first.")
    }

    try TripValidator.validatePlanned(trip)

    guard request.actualStart <= dates.now else {
      throw DomainError("The actual start cannot be in the future.")
    }
    guard request.allowsOpenImportantItems || trip.openImportantItems.isEmpty else {
      throw DomainError("Some important checks are still open. Confirm that you want to set off.")
    }

    try OdometerValidator.validateStartReading(
      request.startOdometer,
      previous: journal.latestOdometerReading(forVehicle: trip.vehicleID),
      explanation: request.explanation
    )

    let reminderIDs = trip.reminders.map(\.id)

    try repository.updateTrip(request.tripID) { trip in
      trip.status = .active
      trip.actualStart = request.actualStart
      trip.startOdometer = request.startOdometer
      trip.odometerExplanation = request.explanation
      trip.reminders = trip.reminders.map(\.cancelled)
    }

    reminders.cancel(ids: reminderIDs)
  }
}

/// Brings a journey home.
///
/// Confirming stores the outcome and closes the trip once. Later corrections go
/// through `EditTripSummary`, which re-checks that every recorded event still fits
/// inside the interval.
struct FinishTrip {
  let repository: JournalRepository
  let dates: DateProvider

  struct Request {
    var tripID: UUID
    var actualEnd: Date
    var endOdometer: Double?
    var outcome: TripOutcome
    var endReason: String
    var hasReadingDiscontinuity: Bool
    var finalNote: String

    init(
      tripID: UUID,
      actualEnd: Date,
      endOdometer: Double? = nil,
      outcome: TripOutcome = .completed,
      endReason: String = "",
      hasReadingDiscontinuity: Bool = false,
      finalNote: String = ""
    ) {
      self.tripID = tripID
      self.actualEnd = actualEnd
      self.endOdometer = endOdometer
      self.outcome = outcome
      self.endReason = endReason
      self.hasReadingDiscontinuity = hasReadingDiscontinuity
      self.finalNote = finalNote
    }
  }

  func execute(_ request: Request) throws {
    try repository.updateTrip(request.tripID) { trip in
      guard trip.status == .active else {
        throw DomainError("Only a trip under way can be finished.")
      }
      try Self.applyEnding(request, to: &trip, now: dates.now)
    }
  }

  /// Shared with summary editing, which reopens a finished trip, applies the same
  /// ending rules and closes it again.
  static func applyEnding(_ request: Request, to trip: inout Trip, now: Date) throws {
    guard let start = trip.actualStart else {
      throw DomainError("This trip has no recorded start.")
    }
    guard trip.openVisit == nil else {
      throw DomainError("Record leaving \(trip.openVisit?.name ?? "your last stop") first.")
    }
    guard request.actualEnd >= start else {
      throw DomainError("The end cannot come before the start.")
    }
    guard request.actualEnd <= now else {
      throw DomainError("The end cannot be in the future.")
    }
    if let last = trip.lastRecordedEvent, request.actualEnd < last {
      throw DomainError("The end must come after everything you recorded on the road.")
    }

    try OdometerValidator.validate(request.endOdometer)
    if let start = trip.startOdometer,
      let end = request.endOdometer,
      end < start,
      !request.hasReadingDiscontinuity
    {
      throw DomainError(
        "The end reading is below the start. Correct it, or mark that the odometer was replaced."
      )
    }

    let reason = request.endReason.trimmed
    guard request.outcome != .endedEarly || !reason.isEmpty else {
      throw DomainError("Add a short reason for ending early.")
    }

    trip.actualEnd = request.actualEnd
    trip.endOdometer = request.endOdometer
    trip.outcome = request.outcome
    trip.endReason = reason
    trip.hasReadingDiscontinuity = request.hasReadingDiscontinuity
    trip.finalNote = request.finalNote.trimmed
    trip.status = .completed
  }
}

/// Corrects a finished trip's times and readings.
///
/// Changing the interval never silently moves a visit or a note. Anything that would
/// fall outside is listed first, and the traveller corrects those records themselves.
struct EditTripSummary {
  let repository: JournalRepository
  let dates: DateProvider

  struct Request {
    var tripID: UUID
    var actualStart: Date
    var startOdometer: Double?
    var ending: FinishTrip.Request
  }

  /// Records that would no longer fit inside a proposed interval.
  struct Conflict: Identifiable, Equatable {
    let id: UUID
    let description: String
  }

  func conflicts(for request: Request) -> [Conflict] {
    guard let trip = repository.journal.trip(request.tripID) else { return [] }
    let range = request.actualStart...max(request.actualStart, request.ending.actualEnd)

    var conflicts: [Conflict] = []
    for stop in trip.stops {
      guard let visit = stop.visit else { continue }
      if !range.contains(visit.arrival) {
        conflicts.append(Conflict(id: stop.id, description: "Arrival at \(stop.name)"))
      } else if let departure = visit.departure, !range.contains(departure) {
        conflicts.append(Conflict(id: stop.id, description: "Leaving \(stop.name)"))
      }
    }
    for note in trip.notes where !range.contains(note.recordedAt) {
      conflicts.append(
        Conflict(id: note.id, description: "Note “\(note.text.prefix(40))”")
      )
    }
    return conflicts
  }

  func execute(_ request: Request) throws {
    let conflicts = conflicts(for: request)
    guard conflicts.isEmpty else {
      throw DomainError(
        "These records fall outside the new times. Correct them first:\n"
          + conflicts.map { "· \($0.description)" }.joined(separator: "\n")
      )
    }

    try repository.updateTrip(request.tripID) { trip in
      guard trip.status == .completed else {
        throw DomainError("Only a finished trip has a summary to edit.")
      }
      guard request.actualStart <= dates.now else {
        throw DomainError("The start cannot be in the future.")
      }
      try OdometerValidator.validate(request.startOdometer)

      trip.actualStart = request.actualStart
      trip.startOdometer = request.startOdometer
      try FinishTrip.applyEnding(request.ending, to: &trip, now: dates.now)
    }
  }
}
