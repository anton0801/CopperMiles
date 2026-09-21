import Combine
import Foundation
import SwiftUI

/// What the interface reads and what it can do, in one object.
///
/// This replaces the old store that loaded files, applied rules, scheduled
/// notifications and formatted dates all at once. Here it only holds the current
/// journal, hands screens the use cases, and turns a thrown rule into something the
/// traveller can read. The work itself belongs to the layers underneath.
@MainActor
final class AppEnvironment: ObservableObject {

  /// The journal as it stands. Every screen reads from this one snapshot, so a
  /// change made in a sheet is visible behind it the moment it is saved.
  @Published private(set) var journal: Journal

  /// The message currently being shown to the traveller, if any.
  @Published var message: AppMessage?

  let repository: FileJournalRepository
  let attachments: AttachmentStore
  let maps: MapsLaunching
  let location: LocationProviding
  let dates: DateProvider
  let useCases: UseCases

  /// Formatters rebuilt whenever the clock preference changes, so a 24-hour journal
  /// does not need every screen to remember to ask.
  private(set) var formatters: Formatters

  init(
    repository: FileJournalRepository = FileJournalRepository(),
    attachments: AttachmentStore = FileAttachmentStore(),
    scheduler: ReminderScheduling = UserNotificationScheduler(),
    backupCodec: BackupCoding = JournalBackupCodec(),
    maps: MapsLaunching = AppleMapsLauncher(),
    location: LocationProviding? = nil,
    dates: DateProvider = SystemDateProvider()
  ) {
    self.repository = repository
    self.attachments = attachments
    self.maps = maps
    self.location = location ?? CoreLocationProvider()
    self.dates = dates
    self.journal = repository.journal
    self.formatters = Formatters(uses24HourTime: repository.journal.settings.uses24HourTime)
    self.useCases = UseCases(
      repository: repository,
      attachments: attachments,
      scheduler: scheduler,
      backupCodec: backupCodec,
      dates: dates
    )

    repository.onChange = { [weak self] journal in
      self?.journalDidChange(journal)
    }

    if let failure = repository.loadFailure {
      message = .error(failure.message)
    }
  }

  private func journalDidChange(_ journal: Journal) {
    if journal.settings.uses24HourTime != self.journal.settings.uses24HourTime {
      formatters = Formatters(uses24HourTime: journal.settings.uses24HourTime)
    }
    self.journal = journal
  }

  // MARK: - Running work

  /// Runs an operation, showing anything it throws.
  ///
  /// Returns whether it succeeded, so a caller can dismiss a sheet only when the
  /// save actually went through — the single most common mistake in the code this
  /// replaces was closing an editor on a rule that had just refused the change.
  @discardableResult
  func perform(_ operation: () throws -> Void) -> Bool {
    do {
      try operation()
      return true
    } catch {
      message = .error(describe(error))
      return false
    }
  }

  @discardableResult
  func perform(_ operation: () async throws -> Void) async -> Bool {
    do {
      try await operation()
      return true
    } catch {
      message = .error(describe(error))
      return false
    }
  }

  /// Runs an operation that produces something, returning `nil` when it was refused.
  func performReturning<Value>(_ operation: () throws -> Value) -> Value? {
    do {
      return try operation()
    } catch {
      message = .error(describe(error))
      return nil
    }
  }

  func show(_ message: AppMessage) {
    self.message = message
  }

  private func describe(_ error: Error) -> String {
    (error as? DomainError)?.message ?? error.localizedDescription
  }

  // MARK: - Convenience

  var settings: AppSettings { journal.settings }
  var activeTrip: Trip? { journal.activeTrip }

  func trip(_ id: UUID) -> Trip? { journal.trip(id) }
  func vehicle(_ id: UUID?) -> Vehicle? { journal.vehicle(id) }

  func vehicleName(_ id: UUID?) -> String {
    journal.vehicle(id)?.name ?? "No vehicle chosen"
  }

  /// The unit a trip's readings are in, falling back to the report unit so a figure
  /// is never shown without one.
  func unit(forTrip trip: Trip) -> DistanceUnit {
    journal.vehicle(trip.vehicleID)?.unit ?? settings.reportUnit
  }

  func updateSettings(_ change: (inout AppSettings) -> Void) {
    perform { try useCases.updateSettings.execute(change) }
  }
}

/// Something the app needs to tell the traveller.
///
/// Presented as an alert at the root rather than as a banner inside each screen, so
/// a message cannot be hidden behind a sheet that is still open.
struct AppMessage: Identifiable, Equatable {
  enum Tone: Equatable {
    case error
    case success
  }

  let id = UUID()
  let tone: Tone
  let title: String
  let body: String

  static func error(_ body: String) -> AppMessage {
    AppMessage(tone: .error, title: "That didn’t go through", body: body)
  }

  static func success(_ title: String, _ body: String) -> AppMessage {
    AppMessage(tone: .success, title: title, body: body)
  }
}
