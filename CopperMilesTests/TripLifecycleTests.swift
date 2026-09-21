import XCTest

@testable import CopperMiles

/// Turning a plan into a journey.
final class StartTripTests: XCTestCase {
  private var vehicle = Fixture.vehicle()
  private var repository = InMemoryJournalRepository()
  private var scheduler = StubReminderScheduler()

  private func makeStartTrip() -> StartTrip {
    StartTrip(repository: repository, dates: Fixture.dates, reminders: scheduler)
  }

  private func seed(_ trips: [Trip]) {
    repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: trips))
    scheduler = StubReminderScheduler()
  }

  func testStartingRecordsTheActualStartAndTurnsTheTripActive() throws {
    let trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    seed([trip])
    let start = Fixture.now.addingTimeInterval(-Fixture.minutes(10))

    try makeStartTrip().execute(
      StartTrip.Request(tripID: trip.id, actualStart: start, startOdometer: 12_345)
    )

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(stored.status, .active)
    XCTAssertEqual(stored.actualStart, start)
    XCTAssertEqual(stored.startOdometer, 12_345)
  }

  func testOnlyOneTripCanBeUnderWay() throws {
    let running = Fixture.activeTrip(vehicleID: vehicle.id)
    let waiting = Fixture.plannedTrip(vehicleID: vehicle.id)
    seed([running, waiting])

    XCTAssertThrowsError(
      try makeStartTrip().execute(
        StartTrip.Request(tripID: waiting.id, actualStart: Fixture.now)
      )
    )
    XCTAssertEqual(repository.journal.trip(waiting.id)?.status, .planned)
  }

  func testStartCannotBeInTheFuture() {
    let trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    seed([trip])

    XCTAssertThrowsError(
      try makeStartTrip().execute(
        StartTrip.Request(
          tripID: trip.id,
          actualStart: Fixture.now.addingTimeInterval(Fixture.hours(1))
        )
      )
    )
  }

  func testOpenImportantChecksNeedConfirming() throws {
    var trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    trip.checklist = [PreparationItem(name: "Check tyres", isImportant: true, isChecked: false)]
    seed([trip])

    XCTAssertThrowsError(
      try makeStartTrip().execute(
        StartTrip.Request(tripID: trip.id, actualStart: Fixture.now)
      )
    )

    try makeStartTrip().execute(
      StartTrip.Request(
        tripID: trip.id,
        actualStart: Fixture.now,
        allowsOpenImportantItems: true
      )
    )
    XCTAssertEqual(repository.journal.trip(trip.id)?.status, .active)
  }

  func testReadingBelowThePreviousOneNeedsAnExplanation() throws {
    var finished = Fixture.plannedTrip(vehicleID: vehicle.id)
    finished.status = .completed
    finished.actualStart = Fixture.now.addingTimeInterval(-Fixture.days(5))
    finished.actualEnd = Fixture.now.addingTimeInterval(-Fixture.days(4))
    finished.startOdometer = 50_000
    finished.endOdometer = 50_400
    finished.outcome = .completed

    let next = Fixture.plannedTrip(vehicleID: vehicle.id)
    seed([finished, next])

    XCTAssertThrowsError(
      try makeStartTrip().execute(
        StartTrip.Request(tripID: next.id, actualStart: Fixture.now, startOdometer: 400)
      )
    )

    try makeStartTrip().execute(
      StartTrip.Request(
        tripID: next.id,
        actualStart: Fixture.now,
        startOdometer: 400,
        explanation: .odometerReplaced
      )
    )
    XCTAssertEqual(repository.journal.trip(next.id)?.odometerExplanation, .odometerReplaced)
  }

  func testStartingCancelsTheTripsReminders() throws {
    var trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    let reminder = TripReminder(kind: .prepareCar)
    trip.reminders = [reminder]
    seed([trip])

    try makeStartTrip().execute(
      StartTrip.Request(tripID: trip.id, actualStart: Fixture.now)
    )

    XCTAssertEqual(scheduler.cancelledIDs, [reminder.id])
    XCTAssertEqual(repository.journal.trip(trip.id)?.reminders.first?.isEnabled, false)
  }
}

/// Bringing a journey home.
final class FinishTripTests: XCTestCase {
  private let vehicle = Fixture.vehicle()

  private func makeFinishTrip(_ repository: JournalRepository) -> FinishTrip {
    FinishTrip(repository: repository, dates: Fixture.dates)
  }

  func testFinishingStoresTheOutcome() throws {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    try makeFinishTrip(repository).execute(
      FinishTrip.Request(
        tripID: trip.id,
        actualEnd: Fixture.now,
        endOdometer: 10_412,
        finalNote: "Worth doing again."
      )
    )

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(stored.status, .completed)
    XCTAssertEqual(stored.outcome, .completed)
    XCTAssertEqual(stored.recordedDistance, 412)
    XCTAssertEqual(stored.finalNote, "Worth doing again.")
  }

  func testAnOpenVisitBlocksFinishing() {
    var trip = Fixture.activeTrip(vehicleID: vehicle.id)
    trip.stops[0].visit = Visit(
      arrival: Fixture.now.addingTimeInterval(-Fixture.hours(2)),
      departure: nil
    )
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try makeFinishTrip(repository).execute(
        FinishTrip.Request(tripID: trip.id, actualEnd: Fixture.now)
      )
    )
    XCTAssertEqual(repository.journal.trip(trip.id)?.status, .active)
  }

  func testEndMustFollowEveryRecordedEvent() {
    var trip = Fixture.activeTrip(vehicleID: vehicle.id)
    trip.notes = [
      RoadNote(text: "A late note", recordedAt: Fixture.now.addingTimeInterval(-Fixture.minutes(5)))
    ]
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try makeFinishTrip(repository).execute(
        FinishTrip.Request(
          tripID: trip.id,
          actualEnd: Fixture.now.addingTimeInterval(-Fixture.hours(1))
        )
      )
    )
  }

  func testEndCannotBeInTheFuture() {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try makeFinishTrip(repository).execute(
        FinishTrip.Request(
          tripID: trip.id,
          actualEnd: Fixture.now.addingTimeInterval(Fixture.hours(1))
        )
      )
    )
  }

  func testEndingEarlyNeedsAReason() {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try makeFinishTrip(repository).execute(
        FinishTrip.Request(tripID: trip.id, actualEnd: Fixture.now, outcome: .endedEarly)
      )
    )

    XCTAssertNoThrow(
      try makeFinishTrip(repository).execute(
        FinishTrip.Request(
          tripID: trip.id,
          actualEnd: Fixture.now,
          outcome: .endedEarly,
          endReason: "The rain set in."
        )
      )
    )
  }

  func testEndReadingBelowStartNeedsADiscontinuity() throws {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try makeFinishTrip(repository).execute(
        FinishTrip.Request(tripID: trip.id, actualEnd: Fixture.now, endOdometer: 5)
      )
    )

    try makeFinishTrip(repository).execute(
      FinishTrip.Request(
        tripID: trip.id,
        actualEnd: Fixture.now,
        endOdometer: 5,
        hasReadingDiscontinuity: true
      )
    )

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertNil(stored.recordedDistance, "A replaced odometer leaves the distance unknown")
  }

  func testUnreachedStopsStayUnreached() throws {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    try makeFinishTrip(repository).execute(
      FinishTrip.Request(tripID: trip.id, actualEnd: Fixture.now)
    )

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(stored.unvisitedStops.count, stored.activeStops.count)
    XCTAssertTrue(stored.visitedStops.isEmpty)
    XCTAssertTrue(stored.skippedStops.isEmpty)
  }
}

/// Correcting a finished trip.
final class EditTripSummaryTests: XCTestCase {
  private let vehicle = Fixture.vehicle()

  private func finishedTrip() -> Trip {
    var trip = Fixture.activeTrip(vehicleID: vehicle.id)
    trip.status = .completed
    trip.actualEnd = Fixture.now.addingTimeInterval(-Fixture.hours(1))
    trip.endOdometer = 10_400
    trip.outcome = .completed
    trip.stops[0].visit = Visit(
      arrival: Fixture.now.addingTimeInterval(-Fixture.hours(5)),
      departure: Fixture.now.addingTimeInterval(-Fixture.hours(4))
    )
    return trip
  }

  func testEventsOutsideTheNewIntervalAreReportedRatherThanMoved() throws {
    let trip = finishedTrip()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let useCase = EditTripSummary(repository: repository, dates: Fixture.dates)

    let request = EditTripSummary.Request(
      tripID: trip.id,
      actualStart: Fixture.now.addingTimeInterval(-Fixture.hours(2)),
      startOdometer: 10_000,
      ending: FinishTrip.Request(
        tripID: trip.id,
        actualEnd: Fixture.now.addingTimeInterval(-Fixture.hours(1)),
        endOdometer: 10_400
      )
    )

    XCTAssertFalse(useCase.conflicts(for: request).isEmpty)
    XCTAssertThrowsError(try useCase.execute(request))

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(stored.actualStart, trip.actualStart, "Nothing is moved on the traveller's behalf")
  }

  func testAValidCorrectionIsStored() throws {
    let trip = finishedTrip()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let useCase = EditTripSummary(repository: repository, dates: Fixture.dates)

    let newStart = Fixture.now.addingTimeInterval(-Fixture.hours(7))
    try useCase.execute(
      EditTripSummary.Request(
        tripID: trip.id,
        actualStart: newStart,
        startOdometer: 9_000,
        ending: FinishTrip.Request(
          tripID: trip.id,
          actualEnd: Fixture.now.addingTimeInterval(-Fixture.minutes(30)),
          endOdometer: 9_500
        )
      )
    )

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(stored.actualStart, newStart)
    XCTAssertEqual(stored.recordedDistance, 500)
    XCTAssertEqual(stored.status, .completed)
  }
}
