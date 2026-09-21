import XCTest

@testable import CopperMiles

/// Recording where the traveller actually went.
final class VisitTests: XCTestCase {
  private let vehicle = Fixture.vehicle()

  private func makeRecordVisit(_ repository: JournalRepository) -> RecordVisit {
    RecordVisit(repository: repository, dates: Fixture.dates)
  }

  func testArrivingMarksTheStopVisited() throws {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let stopID = trip.stops[0].id

    try makeRecordVisit(repository).arriveNow(tripID: trip.id, stopID: stopID)

    let stored = try XCTUnwrap(repository.journal.trip(trip.id)?.stop(stopID))
    XCTAssertTrue(stored.isVisited)
    XCTAssertEqual(stored.visit?.arrival, Fixture.now)
    XCTAssertNil(stored.visit?.departure)
  }

  func testReachingTheDestinationDoesNotEndTheTrip() throws {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let destinationID = try XCTUnwrap(trip.destination?.id)

    try makeRecordVisit(repository).arriveNow(tripID: trip.id, stopID: destinationID)

    XCTAssertEqual(repository.journal.trip(trip.id)?.status, .active)
  }

  func testOnlyOneVisitMayBeOpenAtATime() throws {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let useCase = makeRecordVisit(repository)

    try useCase.arriveNow(tripID: trip.id, stopID: trip.stops[0].id)

    XCTAssertThrowsError(
      try useCase.arriveNow(tripID: trip.id, stopID: trip.stops[1].id)
    )
  }

  func testLeavingClosesTheVisit() throws {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let useCase = makeRecordVisit(repository)
    let stopID = trip.stops[0].id

    try useCase.arriveNow(tripID: trip.id, stopID: stopID)
    try useCase.leaveNow(tripID: trip.id, stopID: stopID)

    XCTAssertEqual(repository.journal.trip(trip.id)?.stop(stopID)?.visit?.departure, Fixture.now)
    XCTAssertNil(repository.journal.trip(trip.id)?.openVisit)
  }

  func testVisitTimesStayInsideTheTrip() {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let useCase = makeRecordVisit(repository)

    XCTAssertThrowsError(
      try useCase.execute(
        tripID: trip.id,
        stopID: trip.stops[0].id,
        arrival: Fixture.now.addingTimeInterval(-Fixture.days(2)),
        departure: nil
      ),
      "An arrival before the trip started must be refused"
    )

    XCTAssertThrowsError(
      try useCase.execute(
        tripID: trip.id,
        stopID: trip.stops[0].id,
        arrival: Fixture.now.addingTimeInterval(Fixture.hours(1)),
        departure: nil
      ),
      "An arrival in the future must be refused"
    )
  }

  func testDepartureCannotPrecedeArrival() {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try makeRecordVisit(repository).execute(
        tripID: trip.id,
        stopID: trip.stops[0].id,
        arrival: Fixture.now.addingTimeInterval(-Fixture.hours(1)),
        departure: Fixture.now.addingTimeInterval(-Fixture.hours(2))
      )
    )
  }

  func testVisitsMayNotOverlap() throws {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let useCase = makeRecordVisit(repository)

    try useCase.execute(
      tripID: trip.id,
      stopID: trip.stops[0].id,
      arrival: Fixture.now.addingTimeInterval(-Fixture.hours(4)),
      departure: Fixture.now.addingTimeInterval(-Fixture.hours(2))
    )

    XCTAssertThrowsError(
      try useCase.execute(
        tripID: trip.id,
        stopID: trip.stops[1].id,
        arrival: Fixture.now.addingTimeInterval(-Fixture.hours(3)),
        departure: Fixture.now.addingTimeInterval(-Fixture.hours(1))
      )
    )
  }

  func testRemovingAVisitCanKeepItsNotes() throws {
    var trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let stopID = trip.stops[0].id
    trip.stops[0].visit = Visit(
      arrival: Fixture.now.addingTimeInterval(-Fixture.hours(3)),
      departure: Fixture.now.addingTimeInterval(-Fixture.hours(2))
    )
    trip.notes = [
      RoadNote(
        text: "Good coffee",
        recordedAt: Fixture.now.addingTimeInterval(-Fixture.hours(3)),
        stopID: stopID
      )
    ]

    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let attachments = StubAttachmentStore()

    try RemoveVisit(repository: repository, attachments: attachments)
      .execute(tripID: trip.id, stopID: stopID, notes: .keepAsTripNotes)

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertFalse(stored.stop(stopID)?.isVisited ?? true)
    XCTAssertEqual(stored.notes.count, 1)
    XCTAssertNil(stored.notes[0].stopID, "The note stays, now attached to the trip")
  }

  func testSkippingIsNotVisiting() throws {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let stopID = trip.stops[0].id

    try SkipStop(repository: repository)
      .skip(tripID: trip.id, stopID: stopID, reason: "Ran out of time")

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertTrue(stored.stop(stopID)?.isSkipped ?? false)
    XCTAssertFalse(stored.stop(stopID)?.isVisited ?? true)
    XCTAssertEqual(stored.stop(stopID)?.skipReason, "Ran out of time")
    XCTAssertTrue(stored.visitedStops.isEmpty)
  }

  func testSkippingNeedsAReason() {
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try SkipStop(repository: repository)
        .skip(tripID: trip.id, stopID: trip.stops[0].id, reason: "   ")
    )
  }
}

/// Arranging the places along the way.
final class StopArrangementTests: XCTestCase {
  private let vehicle = Fixture.vehicle()

  private func tripWithThreeStops() -> Trip {
    Fixture.plannedTrip(
      vehicleID: vehicle.id,
      stops: [
        Stop(name: "First", kind: .food),
        Stop(name: "Second", kind: .rest),
        Fixture.destination(),
      ]
    )
  }

  func testANewStopLandsBeforeTheDestination() throws {
    let trip = tripWithThreeStops()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    try SaveStop(repository: repository)
      .execute(tripID: trip.id, stop: Stop(name: "Third", kind: .fuel))

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(stored.stops.map(\.name), ["First", "Second", "Third", "Harbour cottage"])
    XCTAssertEqual(stored.stops.last?.kind, .destination)
  }

  func testPromotingAStopToDestinationDemotesTheOldOne() throws {
    let trip = tripWithThreeStops()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    var promoted = trip.stops[0]
    promoted.kind = .destination
    try SaveStop(repository: repository).execute(tripID: trip.id, stop: promoted)

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(stored.stops.filter { $0.kind == .destination }.count, 1)
    XCTAssertEqual(stored.stops.last?.name, "First")
  }

  func testStopsMoveWithinThePlan() throws {
    let trip = tripWithThreeStops()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    try MoveStop(repository: repository)
      .execute(tripID: trip.id, stopID: trip.stops[1].id, offset: -1)

    XCTAssertEqual(
      repository.journal.trip(trip.id)?.stops.map(\.name),
      ["Second", "First", "Harbour cottage"]
    )
  }

  func testTheDestinationNeverMoves() {
    let trip = tripWithThreeStops()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let destinationID = trip.stops[2].id

    XCTAssertThrowsError(
      try MoveStop(repository: repository)
        .execute(tripID: trip.id, stopID: destinationID, offset: -1)
    )
  }

  func testVisitedStopsStayPutOnceUnderWay() {
    var trip = tripWithThreeStops()
    trip.status = .active
    trip.actualStart = Fixture.now.addingTimeInterval(-Fixture.hours(4))
    trip.stops[0].visit = Visit(
      arrival: Fixture.now.addingTimeInterval(-Fixture.hours(3)),
      departure: Fixture.now.addingTimeInterval(-Fixture.hours(2))
    )

    XCTAssertFalse(MoveStop.isMovable(trip.stops[0], in: trip))
    XCTAssertTrue(MoveStop.isMovable(trip.stops[1], in: trip))
  }

  func testAVisitedStopIsArchivedRatherThanDeleted() throws {
    var trip = tripWithThreeStops()
    trip.status = .active
    trip.actualStart = Fixture.now.addingTimeInterval(-Fixture.hours(4))
    trip.stops[0].visit = Visit(
      arrival: Fixture.now.addingTimeInterval(-Fixture.hours(3)),
      departure: Fixture.now.addingTimeInterval(-Fixture.hours(2))
    )
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    let outcome = try RemoveStop(repository: repository)
      .execute(tripID: trip.id, stopID: trip.stops[0].id)

    XCTAssertEqual(outcome, .archived)
    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(stored.stops.count, 3, "The record stays in the journal")
    XCTAssertEqual(stored.activeStops.count, 2, "But it leaves the plan")
    XCTAssertEqual(stored.visitedStops.count, 1)
  }

  func testAnUnvisitedStopIsDeleted() throws {
    let trip = tripWithThreeStops()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    let outcome = try RemoveStop(repository: repository)
      .execute(tripID: trip.id, stopID: trip.stops[0].id)

    XCTAssertEqual(outcome, .deleted)
    XCTAssertEqual(repository.journal.trip(trip.id)?.stops.count, 2)
  }

  func testTheDestinationCannotBeRemoved() {
    let trip = tripWithThreeStops()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try RemoveStop(repository: repository)
        .execute(tripID: trip.id, stopID: trip.stops[2].id)
    )
  }

  func testPlanningThePlaceAgainMakesASeparateStop() throws {
    var trip = tripWithThreeStops()
    trip.status = .active
    trip.actualStart = Fixture.now.addingTimeInterval(-Fixture.hours(4))
    trip.stops[0].visit = Visit(
      arrival: Fixture.now.addingTimeInterval(-Fixture.hours(3)),
      departure: Fixture.now.addingTimeInterval(-Fixture.hours(2))
    )
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    let copy = try DuplicateStop(repository: repository)
      .execute(tripID: trip.id, stopID: trip.stops[0].id)

    XCTAssertNotEqual(copy.id, trip.stops[0].id)
    XCTAssertNil(copy.visit, "The new stop starts with no visit of its own")
    XCTAssertEqual(repository.journal.trip(trip.id)?.stops.count, 4)
  }
}

/// Reading what the traveller typed into a stop.
final class StopValidatorTests: XCTestCase {
  func testCoordinatesComeInPairs() {
    XCTAssertThrowsError(try StopValidator.coordinate(latitude: "50.7", longitude: ""))
    XCTAssertThrowsError(try StopValidator.coordinate(latitude: "", longitude: "-3.5"))
  }

  func testEmptyCoordinatesAreAllowed() throws {
    XCTAssertNil(try StopValidator.coordinate(latitude: "  ", longitude: ""))
  }

  func testCoordinatesMustBeInRange() {
    XCTAssertThrowsError(try StopValidator.coordinate(latitude: "91", longitude: "0"))
    XCTAssertThrowsError(try StopValidator.coordinate(latitude: "0", longitude: "181"))
  }

  func testCommaDecimalsAreAccepted() throws {
    let coordinate = try StopValidator.coordinate(latitude: "50,7184", longitude: "-3,5339")
    XCTAssertEqual(coordinate?.latitude ?? 0, 50.7184, accuracy: 0.0001)
  }

  func testStayMustBeWholeMinutesInRange() {
    XCTAssertThrowsError(try StopValidator.stayMinutes("0"))
    XCTAssertThrowsError(try StopValidator.stayMinutes("2881"))
    XCTAssertThrowsError(try StopValidator.stayMinutes("45.5"))
    XCTAssertEqual(try StopValidator.stayMinutes("45"), 45)
    XCTAssertNil(try StopValidator.stayMinutes(""))
  }

  func testAStopNeedsAName() {
    XCTAssertThrowsError(try StopValidator.validated(Stop(name: "   ")))
  }

  func testNameOnlyIsEnough() throws {
    let stop = try StopValidator.validated(Stop(name: "The little café"))
    XCTAssertEqual(stop.name, "The little café")
    XCTAssertNil(stop.coordinate)
    XCTAssertFalse(stop.canOpenInMaps)
  }
}

/// Changing where the trip is heading.
final class SetDestinationTests: XCTestCase {
  private let vehicle = Fixture.vehicle()

  private func trip() -> Trip {
    Fixture.plannedTrip(
      vehicleID: vehicle.id,
      stops: [
        Stop(name: "Halfway café", kind: .food),
        Fixture.destination("Harbour cottage"),
      ]
    )
  }

  func testAnotherStopCanTakeTheRoleAndMovesLast() throws {
    let trip = trip()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    try SetDestination(repository: repository)
      .execute(tripID: trip.id, stopID: trip.stops[0].id)

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(stored.stops.map(\.name), ["Harbour cottage", "Halfway café"])
    XCTAssertEqual(stored.destination?.name, "Halfway café")
    XCTAssertEqual(stored.stops.filter { $0.kind == .destination }.count, 1)
    XCTAssertNoThrow(try TripValidator.validatePlanned(stored))
  }

  func testTheOldDestinationBecomesAnOrdinaryStop() throws {
    let trip = trip()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let previousID = trip.stops[1].id

    try SetDestination(repository: repository)
      .execute(tripID: trip.id, stopID: trip.stops[0].id)

    let stored = try XCTUnwrap(repository.journal.trip(trip.id)?.stop(previousID))
    XCTAssertEqual(stored.kind, .custom)
  }

  /// The escape hatch `RemoveStop` points at has to actually work.
  func testTheOldDestinationCanThenBeDeleted() throws {
    let trip = trip()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let previousID = trip.stops[1].id

    XCTAssertThrowsError(
      try RemoveStop(repository: repository).execute(tripID: trip.id, stopID: previousID)
    )

    try SetDestination(repository: repository)
      .execute(tripID: trip.id, stopID: trip.stops[0].id)
    try RemoveStop(repository: repository).execute(tripID: trip.id, stopID: previousID)

    XCTAssertEqual(repository.journal.trip(trip.id)?.stops.map(\.name), ["Halfway café"])
  }

  func testTheCurrentDestinationCannotTakeTheRoleAgain() {
    let trip = trip()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try SetDestination(repository: repository)
        .execute(tripID: trip.id, stopID: trip.stops[1].id)
    )
  }

  func testAStopWithAnOpenVisitCannotBeArchived() throws {
    var trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let stopID = trip.stops[0].id
    trip.stops[0].visit = Visit(
      arrival: Fixture.now.addingTimeInterval(-Fixture.hours(2)),
      departure: nil
    )
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try RemoveStop(repository: repository).execute(tripID: trip.id, stopID: stopID),
      "Archiving it would hide the stop that blocks finishing"
    )
    XCTAssertEqual(repository.journal.trip(trip.id)?.openVisit?.id, stopID)
  }
}
