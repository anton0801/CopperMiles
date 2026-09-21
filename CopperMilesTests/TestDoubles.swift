import Foundation

@testable import CopperMiles

/// A journal held in memory, with the same transaction behaviour as the real one.
///
/// A change that throws leaves the journal untouched, which is the property most of
/// these tests are really checking.
final class InMemoryJournalRepository: JournalRepository {
  private(set) var journal: Journal

  /// Set to make saving fail, so a test can prove nothing was half-applied.
  var saveError: Error?

  init(_ journal: Journal = Journal()) {
    self.journal = journal
  }

  func apply(_ change: (inout Journal) throws -> Void) throws {
    var candidate = journal
    try change(&candidate)
    if let saveError { throw saveError }
    journal = candidate
  }

  func replace(with journal: Journal) throws {
    if let saveError { throw saveError }
    self.journal = journal
  }
}

/// Records what was stored and removed, without touching the disk.
final class StubAttachmentStore: AttachmentStore {
  private(set) var stored: [AttachmentID: Data] = [:]
  private(set) var removedIDs: [AttachmentID] = []

  func data(for id: AttachmentID) -> Data? {
    stored[id]
  }

  func store(_ data: Data) throws -> AttachmentID {
    let id = AttachmentID()
    stored[id] = data
    return id
  }

  func restore(_ data: Data, as id: AttachmentID) throws {
    stored[id] = data
  }

  func remove(_ ids: [AttachmentID]) {
    removedIDs.append(contentsOf: ids)
    ids.forEach { stored.removeValue(forKey: $0) }
  }

  func removeOrphans(keeping referenced: Set<AttachmentID>) {
    for id in stored.keys where !referenced.contains(id) {
      stored.removeValue(forKey: id)
      removedIDs.append(id)
    }
  }
}

/// Reports what it was asked to schedule, and can be told to refuse.
final class StubReminderScheduler: ReminderScheduling {
  var authorizationState: ReminderAuthorization = .allowed
  var acceptsRequests = true

  private(set) var scheduledRequests: [ReminderRequest] = []
  private(set) var cancelledIDs: [UUID] = []
  private(set) var didCancelAll = false

  func authorization() async -> ReminderAuthorization {
    authorizationState
  }

  func requestAuthorization() async -> ReminderAuthorization {
    authorizationState == .notDetermined ? .allowed : authorizationState
  }

  func schedule(_ requests: [ReminderRequest]) async -> Set<UUID> {
    scheduledRequests.append(contentsOf: requests)
    return acceptsRequests ? Set(requests.map(\.id)) : []
  }

  func cancel(ids: [UUID]) {
    cancelledIDs.append(contentsOf: ids)
  }

  func cancelAll() {
    didCancelAll = true
  }
}

// MARK: - Fixtures

enum Fixture {
  /// A fixed "now" so that every date in a test reads as an offset from one moment.
  static let now = Date(timeIntervalSince1970: 1_750_000_000)

  static var dates: DateProvider { FixedDateProvider(now) }

  static func minutes(_ count: Double) -> TimeInterval { count * 60 }
  static func hours(_ count: Double) -> TimeInterval { count * 3600 }
  static func days(_ count: Double) -> TimeInterval { count * 86_400 }

  static func vehicle(
    name: String = "The orange estate",
    unit: DistanceUnit = .kilometres
  ) -> Vehicle {
    Vehicle(
      name: name,
      unit: unit,
      preparationTemplate: [
        PreparationItem(name: "Check tyres", isImportant: true),
        PreparationItem(name: "Water", group: .personal),
      ]
    )
  }

  static func destination(_ name: String = "Harbour cottage") -> Stop {
    Stop(name: name, kind: .destination)
  }

  /// A plan that satisfies every rule, ready to be broken one field at a time.
  ///
  /// Its important check is already ticked, so a test that is about something else
  /// is not stopped by the open-items confirmation. The test for that rule unticks
  /// it on purpose.
  static func plannedTrip(vehicleID: UUID, stops: [Stop]? = nil) -> Trip {
    Trip(
      name: "A weekend by the coast",
      vehicleID: vehicleID,
      status: .planned,
      plannedDeparture: now.addingTimeInterval(days(2)),
      startPlace: "Home",
      travellers: 2,
      stops: stops ?? [Stop(name: "Halfway café", kind: .food), destination()],
      checklist: [PreparationItem(name: "Check tyres", isImportant: true, isChecked: true)]
    )
  }

  static func activeTrip(vehicleID: UUID, stops: [Stop]? = nil) -> Trip {
    var trip = plannedTrip(vehicleID: vehicleID, stops: stops)
    trip.status = .active
    trip.actualStart = now.addingTimeInterval(-hours(6))
    trip.startOdometer = 10_000
    return trip
  }

  static func journal(with trips: [Trip] = [], vehicles: [Vehicle] = []) -> Journal {
    Journal(vehicles: vehicles, trips: trips)
  }
}
