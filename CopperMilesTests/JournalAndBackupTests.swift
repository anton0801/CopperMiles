import XCTest

@testable import CopperMiles

/// Reporting on the journal.
final class TravelSummaryTests: XCTestCase {
  private func finishedTrip(
    vehicleID: UUID,
    daysAgo: Double,
    distance: Double?,
    outcome: TripOutcome = .completed,
    isArchived: Bool = false
  ) -> Trip {
    let start = Fixture.now.addingTimeInterval(-Fixture.days(daysAgo))
    var trip = Fixture.plannedTrip(vehicleID: vehicleID)
    trip.status = .completed
    trip.actualStart = start
    trip.actualEnd = start.addingTimeInterval(Fixture.hours(10))
    trip.outcome = outcome
    trip.isArchived = isArchived
    if let distance {
      trip.startOdometer = 1_000
      trip.endOdometer = 1_000 + distance
    }
    return trip
  }

  private func makeSummary(_ journal: Journal) -> BuildTravelSummary {
    let repository = InMemoryJournalRepository(journal)
    return BuildTravelSummary(
      repository: repository,
      entries: FindJournalEntries(repository: repository, dates: Fixture.dates),
      dates: Fixture.dates
    )
  }

  func testOnlyTrustworthyReadingsCountTowardsDistance() {
    let vehicle = Fixture.vehicle()
    let journal = Journal(
      vehicles: [vehicle],
      trips: [
        finishedTrip(vehicleID: vehicle.id, daysAgo: 5, distance: 400),
        finishedTrip(vehicleID: vehicle.id, daysAgo: 10, distance: nil),
      ]
    )

    let summary = makeSummary(journal).execute(JournalFilter())

    XCTAssertEqual(summary.finishedTrips, 2)
    XCTAssertEqual(summary.tripsWithDistance, 1)
    XCTAssertEqual(summary.recordedDistance, 400, accuracy: 0.01)
  }

  func testDistancesAreConvertedToTheReportUnit() {
    var vehicle = Fixture.vehicle()
    vehicle.unit = .miles
    var journal = Journal(
      vehicles: [vehicle],
      trips: [finishedTrip(vehicleID: vehicle.id, daysAgo: 5, distance: 100)]
    )
    journal.settings.reportUnit = .kilometres

    let summary = makeSummary(journal).execute(JournalFilter())

    XCTAssertEqual(summary.recordedDistance, 160.9344, accuracy: 0.01)
    XCTAssertEqual(summary.reportUnit, .kilometres)
  }

  func testArchivedTripsStayOutOfReports() {
    let vehicle = Fixture.vehicle()
    let journal = Journal(
      vehicles: [vehicle],
      trips: [
        finishedTrip(vehicleID: vehicle.id, daysAgo: 5, distance: 400),
        finishedTrip(vehicleID: vehicle.id, daysAgo: 6, distance: 100, isArchived: true),
      ]
    )

    let excluded = makeSummary(journal).execute(JournalFilter())
    XCTAssertEqual(excluded.finishedTrips, 1)
    XCTAssertEqual(excluded.recordedDistance, 400, accuracy: 0.01)

    let included = makeSummary(journal).execute(JournalFilter(includesArchived: true))
    XCTAssertEqual(included.finishedTrips, 2)
    XCTAssertEqual(included.recordedDistance, 500, accuracy: 0.01)
  }

  func testUnfinishedTripsAreNotCounted() {
    let vehicle = Fixture.vehicle()
    let journal = Journal(
      vehicles: [vehicle],
      trips: [
        Fixture.plannedTrip(vehicleID: vehicle.id),
        Fixture.activeTrip(vehicleID: vehicle.id),
        finishedTrip(vehicleID: vehicle.id, daysAgo: 5, distance: 400),
      ]
    )

    let summary = makeSummary(journal).execute(JournalFilter())

    XCTAssertEqual(summary.finishedTrips, 1)
  }

  func testEndedEarlyCountsAsFinished() {
    let vehicle = Fixture.vehicle()
    let journal = Journal(
      vehicles: [vehicle],
      trips: [
        finishedTrip(vehicleID: vehicle.id, daysAgo: 5, distance: 400),
        finishedTrip(vehicleID: vehicle.id, daysAgo: 6, distance: 50, outcome: .endedEarly),
      ]
    )

    let summary = makeSummary(journal).execute(JournalFilter())

    XCTAssertEqual(summary.finishedTrips, 2)
    XCTAssertEqual(summary.completedTrips, 1)
    XCTAssertEqual(summary.endedEarlyTrips, 1)
  }

  func testTheChartCoversTwelveMonthsIncludingEmptyOnes() {
    let vehicle = Fixture.vehicle()
    let journal = Journal(
      vehicles: [vehicle],
      trips: [finishedTrip(vehicleID: vehicle.id, daysAgo: 5, distance: 400)]
    )

    let summary = makeSummary(journal).execute(JournalFilter())

    XCTAssertEqual(summary.monthlyCounts.count, 12)
    XCTAssertEqual(summary.monthlyCounts.map(\.count).reduce(0, +), 1)
  }
}

/// Converting a vehicle's readings.
final class VehicleUnitTests: XCTestCase {
  func testConversionRoundTrips() {
    let kilometres = 100.0
    let miles = DistanceUnit.kilometres.converting(kilometres, to: .miles)
    XCTAssertEqual(DistanceUnit.miles.converting(miles, to: .kilometres), kilometres, accuracy: 0.0001)
  }

  func testConvertingRewritesEveryReadingForThatVehicle() throws {
    let vehicle = Fixture.vehicle(unit: .kilometres)
    let other = Fixture.vehicle(name: "Little blue camper", unit: .kilometres)

    var trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    trip.status = .completed
    trip.actualStart = Fixture.now.addingTimeInterval(-Fixture.days(3))
    trip.actualEnd = Fixture.now.addingTimeInterval(-Fixture.days(2))
    trip.startOdometer = 100
    trip.endOdometer = 200
    trip.outcome = .completed

    var otherTrip = Fixture.plannedTrip(vehicleID: other.id)
    otherTrip.status = .completed
    otherTrip.actualStart = Fixture.now.addingTimeInterval(-Fixture.days(5))
    otherTrip.actualEnd = Fixture.now.addingTimeInterval(-Fixture.days(4))
    otherTrip.startOdometer = 100
    otherTrip.endOdometer = 200
    otherTrip.outcome = .completed

    let repository = InMemoryJournalRepository(
      Journal(vehicles: [vehicle, other], trips: [trip, otherTrip])
    )

    try ConvertVehicleUnit(repository: repository).execute(vehicleID: vehicle.id, to: .miles)

    let converted = try XCTUnwrap(repository.journal.trip(trip.id))
    XCTAssertEqual(converted.startOdometer ?? 0, 62.137, accuracy: 0.01)
    XCTAssertEqual(repository.journal.vehicle(vehicle.id)?.unit, .miles)

    let untouched = try XCTUnwrap(repository.journal.trip(otherTrip.id))
    XCTAssertEqual(untouched.startOdometer, 100, "Another vehicle's readings are not touched")
  }

  func testConversionIsUnavailableDuringAnActiveTrip() {
    let vehicle = Fixture.vehicle()
    let repository = InMemoryJournalRepository(
      Journal(vehicles: [vehicle], trips: [Fixture.activeTrip(vehicleID: vehicle.id)])
    )

    XCTAssertThrowsError(
      try ConvertVehicleUnit(repository: repository).execute(vehicleID: vehicle.id, to: .miles)
    )
  }

  func testAVehicleWithTripsIsNotDeleted() {
    let vehicle = Fixture.vehicle()
    let repository = InMemoryJournalRepository(
      Journal(vehicles: [vehicle], trips: [Fixture.plannedTrip(vehicleID: vehicle.id)])
    )

    XCTAssertThrowsError(
      try DeleteVehicle(repository: repository, attachments: StubAttachmentStore())
        .execute(vehicle.id)
    )
    XCTAssertEqual(repository.journal.vehicles.count, 1)
  }

  func testAVehicleWithoutTripsIsDeletedWithItsPhoto() throws {
    let attachments = StubAttachmentStore()
    let photoID = try attachments.store(Data("photo".utf8))
    var vehicle = Fixture.vehicle()
    vehicle.photoID = photoID

    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle]))

    try DeleteVehicle(repository: repository, attachments: attachments).execute(vehicle.id)

    XCTAssertTrue(repository.journal.vehicles.isEmpty)
    XCTAssertEqual(attachments.removedIDs, [photoID])
  }
}

/// Backups.
final class BackupTests: XCTestCase {
  private func makeJournal() throws -> (Journal, [AttachmentID: Data]) {
    let vehicle = Fixture.vehicle()
    var trip = Fixture.activeTrip(vehicleID: vehicle.id)
    trip.status = .completed
    trip.actualEnd = Fixture.now.addingTimeInterval(-Fixture.hours(1))
    trip.endOdometer = 10_400
    trip.outcome = .completed

    let photoID = AttachmentID()
    trip.notes = [
      RoadNote(
        text: "The layby past the second bend",
        recordedAt: Fixture.now.addingTimeInterval(-Fixture.hours(3)),
        photoIDs: [photoID]
      )
    ]

    return (
      Journal(vehicles: [vehicle], trips: [trip]),
      [photoID: Data(repeating: 0xAB, count: 512)]
    )
  }

  func testAnArchiveRoundTrips() throws {
    let (journal, attachments) = try makeJournal()
    let codec = JournalBackupCodec()

    let data = try codec.encode(BackupPayload(journal: journal, attachments: attachments))
    let restored = try codec.decode(data)

    XCTAssertEqual(restored.journal, journal)
    XCTAssertEqual(restored.attachments, attachments)
  }

  func testEncodingIsStableForTheSameJournal() throws {
    let (journal, attachments) = try makeJournal()
    let codec = JournalBackupCodec()
    let payload = BackupPayload(journal: journal, attachments: attachments)

    XCTAssertEqual(try codec.encode(payload), try codec.encode(payload))
  }

  func testAMissingPhotoIsRefused() throws {
    let (journal, _) = try makeJournal()
    let codec = JournalBackupCodec()

    // Encoded without the photo the note refers to.
    let data = try codec.encode(BackupPayload(journal: journal, attachments: [:]))

    XCTAssertThrowsError(try codec.decode(data))
  }

  func testSomethingThatIsNotABackupIsRefused() {
    XCTAssertThrowsError(try JournalBackupCodec().decode(Data("not a zip".utf8)))
  }

  func testImportIsRefusedWhileATripIsUnderWay() throws {
    let vehicle = Fixture.vehicle()
    let repository = InMemoryJournalRepository(
      Journal(vehicles: [vehicle], trips: [Fixture.activeTrip(vehicleID: vehicle.id)])
    )
    let attachments = StubAttachmentStore()
    let codec = JournalBackupCodec()
    let scheduler = StubReminderScheduler()

    let candidate = try ReadBackup(codec: codec, dates: Fixture.dates)
      .execute(try codec.encode(BackupPayload(journal: Journal())))

    let importBackup = ImportBackup(
      repository: repository,
      attachments: attachments,
      scheduler: scheduler,
      exportBackup: ExportBackup(
        repository: repository,
        attachments: attachments,
        codec: codec
      ),
      dates: Fixture.dates
    )

    XCTAssertThrowsError(
      try importBackup.execute(
        candidate,
        safetyCopyDirectory: FileManager.default.temporaryDirectory
      )
    )
  }

  func testDeletingEverythingNeedsTheExactPhrase() throws {
    let vehicle = Fixture.vehicle()
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle]))
    let useCase = DeleteAllData(
      repository: repository,
      attachments: StubAttachmentStore(),
      scheduler: StubReminderScheduler()
    )

    XCTAssertThrowsError(try useCase.execute(confirmation: "delete everything"))
    XCTAssertEqual(repository.journal.vehicles.count, 1)

    try useCase.execute(confirmation: "DELETE")
    XCTAssertTrue(repository.journal.vehicles.isEmpty)
  }
}

/// Reminders.
final class ReminderTests: XCTestCase {
  private let vehicle = Fixture.vehicle()

  private func makeRefresh(
    _ repository: JournalRepository,
    _ scheduler: StubReminderScheduler
  ) -> RefreshTripReminders {
    RefreshTripReminders(repository: repository, scheduler: scheduler, dates: Fixture.dates)
  }

  func testAnEnabledFutureReminderIsScheduled() async throws {
    var trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    trip.reminders = [TripReminder(kind: .prepareCar, leadTime: TripReminder.oneHour)]
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let scheduler = StubReminderScheduler()

    let result = await makeRefresh(repository, scheduler).execute(tripID: trip.id)

    XCTAssertEqual(result, .scheduled(count: 1))
    XCTAssertEqual(repository.journal.trip(trip.id)?.reminders.first?.isScheduled, true)
  }

  func testNotificationsOffLeavesTheReminderSavedButUnscheduled() async throws {
    var trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    trip.reminders = [TripReminder(kind: .prepareCar)]
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let scheduler = StubReminderScheduler()
    scheduler.authorizationState = .denied

    let result = await makeRefresh(repository, scheduler).execute(tripID: trip.id)

    XCTAssertEqual(result, .notificationsOff)
    let stored = try XCTUnwrap(repository.journal.trip(trip.id)?.reminders.first)
    XCTAssertTrue(stored.isEnabled, "The traveller's preference is kept")
    XCTAssertFalse(stored.isScheduled, "But nothing pretends it will arrive")
  }

  func testAReminderInThePastIsNotScheduled() async throws {
    var trip = Fixture.plannedTrip(vehicleID: vehicle.id)
    // The departure is two days out, so a three-day lead has already gone by.
    trip.reminders = [TripReminder(kind: .prepareCar, leadTime: Fixture.days(3))]
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let scheduler = StubReminderScheduler()

    let result = await makeRefresh(repository, scheduler).execute(tripID: trip.id)

    XCTAssertEqual(result, .nothingToSchedule)
    XCTAssertTrue(scheduler.scheduledRequests.isEmpty)
  }

  func testAnActiveTripSchedulesNothing() async throws {
    var trip = Fixture.activeTrip(vehicleID: vehicle.id)
    trip.reminders = [TripReminder(kind: .prepareCar)]
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    let scheduler = StubReminderScheduler()

    let result = await makeRefresh(repository, scheduler).execute(tripID: trip.id)

    XCTAssertEqual(result, .nothingToSchedule)
  }
}

/// Guarding the recorded readings.
final class VehicleUnitLockTests: XCTestCase {
  func testTheUnitCannotBeSwitchedOnceTheVehicleHasTrips() throws {
    var vehicle = Fixture.vehicle(unit: .kilometres)
    let repository = InMemoryJournalRepository(
      Journal(vehicles: [vehicle], trips: [Fixture.plannedTrip(vehicleID: vehicle.id)])
    )
    let saveVehicle = SaveVehicle(repository: repository, attachments: StubAttachmentStore())

    vehicle.unit = .miles
    XCTAssertThrowsError(
      try saveVehicle.execute(vehicle),
      "Switching the unit would reinterpret every reading already stored"
    )
    XCTAssertEqual(repository.journal.vehicle(vehicle.id)?.unit, .kilometres)
  }

  func testTheUnitIsFreeToChangeBeforeTheFirstTrip() throws {
    var vehicle = Fixture.vehicle(unit: .kilometres)
    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle]))
    let saveVehicle = SaveVehicle(repository: repository, attachments: StubAttachmentStore())

    vehicle.unit = .miles
    _ = try saveVehicle.execute(vehicle)

    XCTAssertEqual(repository.journal.vehicle(vehicle.id)?.unit, .miles)
  }

  func testOtherEditsStillSaveOnAVehicleWithTrips() throws {
    var vehicle = Fixture.vehicle(unit: .kilometres)
    let repository = InMemoryJournalRepository(
      Journal(vehicles: [vehicle], trips: [Fixture.plannedTrip(vehicleID: vehicle.id)])
    )
    let saveVehicle = SaveVehicle(repository: repository, attachments: StubAttachmentStore())

    vehicle.name = "The amber estate"
    _ = try saveVehicle.execute(vehicle)

    XCTAssertEqual(repository.journal.vehicle(vehicle.id)?.name, "The amber estate")
  }
}

/// Keeping records and preferences apart.
final class DeleteAllDataTests: XCTestCase {
  func testPreferencesSurviveAndOnboardingIsNotReplayed() throws {
    var journal = Journal(vehicles: [Fixture.vehicle()])
    journal.settings = AppSettings(
      reportUnit: .miles,
      uses24HourTime: true,
      prefersReducedMotion: true,
      exportOptions: ExportOptions(includesAddresses: true),
      hasSeenOnboarding: true
    )
    let repository = InMemoryJournalRepository(journal)

    try DeleteAllData(
      repository: repository,
      attachments: StubAttachmentStore(),
      scheduler: StubReminderScheduler()
    ).execute(confirmation: "DELETE")

    let settings = repository.journal.settings
    XCTAssertTrue(repository.journal.vehicles.isEmpty)
    XCTAssertTrue(repository.journal.trips.isEmpty)
    XCTAssertTrue(settings.hasSeenOnboarding, "Deleting records must not replay onboarding")
    XCTAssertEqual(settings.reportUnit, .miles)
    XCTAssertTrue(settings.uses24HourTime)
    XCTAssertTrue(settings.prefersReducedMotion)
    XCTAssertTrue(settings.exportOptions.includesAddresses)
  }
}

/// Backups that cannot be restored must never be written.
final class BackupIntegrityTests: XCTestCase {
  func testExportRefusesWhenAReferencedPhotoCannotBeRead() throws {
    let vehicle = Fixture.vehicle()
    var trip = Fixture.activeTrip(vehicleID: vehicle.id)
    trip.status = .completed
    trip.actualEnd = Fixture.now.addingTimeInterval(-Fixture.hours(1))
    trip.outcome = .completed
    trip.notes = [
      RoadNote(
        text: "A memory with a photo",
        recordedAt: Fixture.now.addingTimeInterval(-Fixture.hours(2)),
        photoIDs: [AttachmentID()]
      )
    ]

    let repository = InMemoryJournalRepository(Journal(vehicles: [vehicle], trips: [trip]))
    // The store holds nothing, so the referenced photo is unreadable.
    let exportBackup = ExportBackup(
      repository: repository,
      attachments: StubAttachmentStore(),
      codec: JournalBackupCodec()
    )

    XCTAssertThrowsError(
      try exportBackup.execute(),
      "An archive the decoder would reject must not be produced in the first place"
    )
  }

  func testAFailedReplaceLeavesNotificationsAlone() throws {
    let vehicle = Fixture.vehicle()
    let repository = InMemoryJournalRepository(
      Journal(vehicles: [vehicle], trips: [Fixture.plannedTrip(vehicleID: vehicle.id)])
    )
    let attachments = StubAttachmentStore()
    let codec = JournalBackupCodec()
    let scheduler = StubReminderScheduler()

    let candidate = try ReadBackup(codec: codec, dates: Fixture.dates)
      .execute(try codec.encode(BackupPayload(journal: Journal())))

    let importBackup = ImportBackup(
      repository: repository,
      attachments: attachments,
      scheduler: scheduler,
      exportBackup: ExportBackup(
        repository: repository,
        attachments: attachments,
        codec: codec
      ),
      dates: Fixture.dates
    )

    repository.saveError = DomainError("The disk is full.")

    XCTAssertThrowsError(
      try importBackup.execute(
        candidate,
        safetyCopyDirectory: FileManager.default.temporaryDirectory
      )
    )
    XCTAssertFalse(
      scheduler.didCancelAll,
      "The journal is unchanged, so its reminders must still stand"
    )
    XCTAssertEqual(repository.journal.trips.count, 1)
  }
}

/// The journal document.
final class JournalFileStoreTests: XCTestCase {
  private var directory = FileManager.default.temporaryDirectory

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private var url: URL { directory.appendingPathComponent("journal.json") }

  func testAJournalRoundTrips() throws {
    let store = JournalFileStore(url: url)
    let vehicle = Fixture.vehicle()
    let journal = Journal(vehicles: [vehicle], trips: [Fixture.plannedTrip(vehicleID: vehicle.id)])

    try store.save(journal)

    XCTAssertEqual(try store.load(), journal)
  }

  func testAMissingFileOpensEmpty() throws {
    XCTAssertEqual(try JournalFileStore(url: url).load(), Journal())
  }

  func testAFileFromAnotherVersionIsLeftWhereItIs() throws {
    try Data(#"{"version":99,"vehicles":[],"trips":[],"settings":{}}"#.utf8).write(to: url)

    XCTAssertThrowsError(try JournalFileStore(url: url).load())
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: url.path),
      "A file this build cannot read is still the traveller's journal"
    )
  }

  func testAnUnreadableFileIsSetAsideRatherThanLost() throws {
    try Data("this is not json".utf8).write(to: url)

    XCTAssertThrowsError(try JournalFileStore(url: url).load())
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

    let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertEqual(kept.filter { $0.hasPrefix("journal-unreadable-") }.count, 1)
  }
}
