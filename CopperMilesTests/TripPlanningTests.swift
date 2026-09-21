import XCTest

@testable import CopperMiles

/// The rules that decide whether a plan is ready to be started.
final class TripValidatorTests: XCTestCase {
  private let vehicleID = UUID()

  func testCompletePlanPasses() throws {
    XCTAssertNoThrow(try TripValidator.validatePlanned(Fixture.plannedTrip(vehicleID: vehicleID)))
  }

  func testPlanNeedsAName() {
    var trip = Fixture.plannedTrip(vehicleID: vehicleID)
    trip.name = "   "
    XCTAssertThrowsError(try TripValidator.validatePlanned(trip))
  }

  func testPlanNeedsAVehicle() {
    var trip = Fixture.plannedTrip(vehicleID: vehicleID)
    trip.vehicleID = nil
    XCTAssertThrowsError(try TripValidator.validatePlanned(trip))
  }

  func testPlanNeedsExactlyOneDestination() {
    var trip = Fixture.plannedTrip(vehicleID: vehicleID)
    trip.stops.append(Fixture.destination("Somewhere else"))
    XCTAssertThrowsError(try TripValidator.validatePlanned(trip))

    trip.stops = [Stop(name: "Halfway café", kind: .food)]
    XCTAssertThrowsError(try TripValidator.validatePlanned(trip))
  }

  func testDestinationMustBeLast() {
    var trip = Fixture.plannedTrip(vehicleID: vehicleID)
    trip.stops = [Fixture.destination(), Stop(name: "Halfway café", kind: .food)]
    XCTAssertThrowsError(try TripValidator.validatePlanned(trip))
  }

  func testNormalisingMovesTheDestinationLast() throws {
    var trip = Fixture.plannedTrip(vehicleID: vehicleID)
    trip.stops = [Fixture.destination(), Stop(name: "Halfway café", kind: .food)]

    let normalised = try TripValidator.normalised(trip)

    XCTAssertEqual(normalised.stops.last?.kind, .destination)
    XCTAssertEqual(normalised.stops.count, 2)
  }

  func testExpectedEndMustFollowDeparture() {
    var trip = Fixture.plannedTrip(vehicleID: vehicleID)
    trip.expectedEnd = trip.plannedDeparture
    XCTAssertThrowsError(try TripValidator.validatePlanned(trip))
  }

  func testTravellersStayWithinRange() {
    var trip = Fixture.plannedTrip(vehicleID: vehicleID)
    trip.travellers = 12
    XCTAssertThrowsError(try TripValidator.validatePlanned(trip))
  }

  // MARK: - Planned arrivals

  func testArrivalBeforeDepartureIsReported() {
    var trip = Fixture.plannedTrip(vehicleID: vehicleID)
    trip.stops[0].plannedArrival = trip.plannedDeparture?.addingTimeInterval(-Fixture.hours(1))

    let conflicts = TripValidator.scheduleConflicts(in: trip)

    XCTAssertEqual(conflicts.count, 1)
    XCTAssertEqual(conflicts.first?.stopName, "Halfway café")
  }

  func testArrivalsOutOfOrderAreReported() {
    let departure = Fixture.now.addingTimeInterval(Fixture.days(2))
    var trip = Fixture.plannedTrip(
      vehicleID: vehicleID,
      stops: [
        Stop(name: "First", kind: .food, plannedArrival: departure.addingTimeInterval(Fixture.hours(5))),
        Stop(name: "Second", kind: .rest, plannedArrival: departure.addingTimeInterval(Fixture.hours(2))),
        Fixture.destination(),
      ]
    )
    trip.plannedDeparture = departure

    let conflicts = TripValidator.scheduleConflicts(in: trip)

    XCTAssertEqual(conflicts.map(\.stopName), ["Second"])
  }

  func testOrderedArrivalsAreAccepted() {
    let departure = Fixture.now.addingTimeInterval(Fixture.days(2))
    var trip = Fixture.plannedTrip(
      vehicleID: vehicleID,
      stops: [
        Stop(name: "First", kind: .food, plannedArrival: departure.addingTimeInterval(Fixture.hours(2))),
        Stop(name: "Second", kind: .rest, plannedArrival: departure.addingTimeInterval(Fixture.hours(5))),
        Fixture.destination(),
      ]
    )
    trip.plannedDeparture = departure

    XCTAssertTrue(TripValidator.scheduleConflicts(in: trip).isEmpty)
  }

  // MARK: - Overlaps

  func testOverlappingPlansForTheSameVehicleAreFound() {
    var first = Fixture.plannedTrip(vehicleID: vehicleID)
    first.expectedEnd = first.plannedDeparture?.addingTimeInterval(Fixture.days(3))

    var second = Fixture.plannedTrip(vehicleID: vehicleID)
    second.plannedDeparture = first.plannedDeparture?.addingTimeInterval(Fixture.days(1))

    let journal = Journal(trips: [first])

    XCTAssertEqual(TripValidator.overlappingTrips(with: second, in: journal).map(\.id), [first.id])
  }

  func testPlansForDifferentVehiclesDoNotOverlap() {
    var first = Fixture.plannedTrip(vehicleID: vehicleID)
    first.expectedEnd = first.plannedDeparture?.addingTimeInterval(Fixture.days(3))

    var second = Fixture.plannedTrip(vehicleID: UUID())
    second.plannedDeparture = first.plannedDeparture

    XCTAssertTrue(TripValidator.overlappingTrips(with: second, in: Journal(trips: [first])).isEmpty)
  }
}

/// Repeating a plan.
final class DuplicateTripTests: XCTestCase {
  func testDuplicateKeepsThePlanAndDropsTheJourney() throws {
    let vehicle = Fixture.vehicle()
    var trip = Fixture.activeTrip(vehicleID: vehicle.id)
    trip.stops[0].visit = Visit(arrival: Fixture.now.addingTimeInterval(-Fixture.hours(3)), departure: nil)
    trip.stops[1].skipReason = "Ran out of time"
    trip.checklist[0].isChecked = true
    trip.actualEnd = Fixture.now
    trip.endOdometer = 10_400
    trip.outcome = .completed
    trip.status = .completed

    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let copy = try DuplicateTrip(repository: repository).execute(tripID: trip.id)

    XCTAssertEqual(copy.status, .draft)
    XCTAssertEqual(copy.vehicleID, vehicle.id)
    XCTAssertEqual(copy.stops.count, trip.stops.count)
    XCTAssertNil(copy.plannedDeparture)
    XCTAssertNil(copy.actualStart)
    XCTAssertNil(copy.actualEnd)
    XCTAssertNil(copy.startOdometer)
    XCTAssertNil(copy.endOdometer)
    XCTAssertNil(copy.outcome)
    XCTAssertTrue(copy.stops.allSatisfy { $0.visit == nil })
    XCTAssertTrue(copy.stops.allSatisfy { !$0.isSkipped })
    XCTAssertTrue(copy.stops.allSatisfy { $0.plannedArrival == nil })
    XCTAssertTrue(copy.checklist.allSatisfy { !$0.isChecked })
    XCTAssertTrue(copy.reminders.isEmpty)
    XCTAssertTrue(copy.notes.isEmpty)
  }

  func testDuplicateGivesEveryRecordAFreshIdentity() throws {
    let vehicle = Fixture.vehicle()
    let trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    let copy = try DuplicateTrip(repository: repository).execute(tripID: trip.id)

    XCTAssertNotEqual(copy.id, trip.id)
    XCTAssertTrue(Set(copy.stops.map(\.id)).isDisjoint(with: Set(trip.stops.map(\.id))))
    XCTAssertTrue(Set(copy.checklist.map(\.id)).isDisjoint(with: Set(trip.checklist.map(\.id))))
  }

  func testPinnedNotesComeAcrossAsWrittenHints() throws {
    let vehicle = Fixture.vehicle()
    var trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let pinned = RoadNote(
      text: "Parking round the back",
      recordedAt: Fixture.now.addingTimeInterval(-Fixture.hours(2)),
      isPinnedForRepeat: true
    )
    let ordinary = RoadNote(
      text: "Nothing special",
      recordedAt: Fixture.now.addingTimeInterval(-Fixture.hours(1))
    )
    trip.notes = [pinned, ordinary]

    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let copy = try DuplicateTrip(repository: repository)
      .execute(tripID: trip.id, carryingHints: [pinned.id])

    XCTAssertTrue(copy.note.contains("Parking round the back"))
    XCTAssertFalse(copy.note.contains("Nothing special"))
    // A hint is advice, never an event in the new trip.
    XCTAssertTrue(copy.notes.isEmpty)
  }
}

/// Saving a trip.
final class SaveTripTests: XCTestCase {
  private func makeSaveTrip(_ repository: JournalRepository) -> SaveTrip {
    let scheduler = StubReminderScheduler()
    return SaveTrip(
      repository: repository,
      reminders: RefreshTripReminders(
        repository: repository,
        scheduler: scheduler,
        dates: Fixture.dates
      )
    )
  }

  func testDraftMayBeIncomplete() throws {
    let repository = InMemoryJournalRepository()
    let draft = Trip(name: "Somewhere with a river")

    let saved = try makeSaveTrip(repository).execute(draft, asPlanned: false)

    XCTAssertEqual(saved.status, .draft)
    XCTAssertEqual(repository.journal.trips.count, 1)
  }

  func testPlannedTripMustBeComplete() {
    let repository = InMemoryJournalRepository()
    let incomplete = Trip(name: "Half an idea")

    XCTAssertThrowsError(try makeSaveTrip(repository).execute(incomplete, asPlanned: true))
    XCTAssertTrue(repository.journal.trips.isEmpty, "A refused plan must not be stored")
  }

  func testNewTripTakesTheVehiclesChecklist() throws {
    let vehicle = Fixture.vehicle()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle]))
    var trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    trip.checklist = []

    let saved = try makeSaveTrip(repository).execute(trip, asPlanned: true)

    XCTAssertEqual(saved.checklist.map(\.name), vehicle.preparationTemplate.map(\.name))
    XCTAssertTrue(saved.checklist.allSatisfy { !$0.isChecked })
  }

  func testEditingATripKeepsItsOwnChecklist() throws {
    let vehicle = Fixture.vehicle()
    var trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    trip.checklist = [PreparationItem(name: "My own check", isChecked: true)]
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    trip.name = "A different name"
    let saved = try makeSaveTrip(repository).execute(trip, asPlanned: true)

    XCTAssertEqual(saved.checklist.map(\.name), ["My own check"])
    XCTAssertTrue(saved.checklist[0].isChecked)
  }

  func testSavingTrimsText() throws {
    let vehicle = Fixture.vehicle()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle]))
    var trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    trip.name = "  A weekend by the coast  "
    trip.startPlace = " Home "

    let saved = try makeSaveTrip(repository).execute(trip, asPlanned: true)

    XCTAssertEqual(saved.name, "A weekend by the coast")
    XCTAssertEqual(saved.startPlace, "Home")
  }
}

/// Cancelling a plan.
final class CancelTripTests: XCTestCase {
  func testCancellingKeepsTheRecordAndWithdrawsItsNotifications() throws {
    let vehicle = Fixture.vehicle()
    var trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    let reminder = TripReminder(kind: .prepareCar, isScheduled: true)
    trip.reminders = [reminder]

    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let scheduler = StubReminderScheduler()

    try CancelTrip(repository: repository, reminders: scheduler).execute(tripID: trip.id)

    let stored = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(stored.status, .cancelled, "The plan stays in the list")
    XCTAssertEqual(stored.reminders.first?.isEnabled, false)
    XCTAssertEqual(stored.reminders.first?.isScheduled, false)
    XCTAssertEqual(
      scheduler.cancelledIDs,
      [reminder.id],
      "A notification the system already holds must be withdrawn, not just flagged off"
    )
  }

  func testATripUnderWayCannotBeCancelled() {
    let vehicle = Fixture.vehicle()
    let trip = Fixture.activeTrip(vehicleID: vehicle.id)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))

    XCTAssertThrowsError(
      try CancelTrip(repository: repository, reminders: StubReminderScheduler())
        .execute(tripID: trip.id)
    )
    XCTAssertEqual(repository.journal.trip(trip.id)?.status, .active)
  }
}
