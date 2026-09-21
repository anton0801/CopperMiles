import Foundation

/// Whether the system will deliver reminders at all.
enum ReminderAuthorization: Equatable {
  case notDetermined
  case allowed
  case denied
}

/// One reminder the app asks the system to deliver.
struct ReminderRequest: Equatable {
  let id: UUID
  let tripID: UUID
  let kind: ReminderKind
  let tripName: String
  let fireDate: Date
}

/// Delivers departure reminders.
///
/// The scheduler reports back which requests the system actually accepted, because a
/// reminder the traveller switched on while notifications are off must be shown as
/// enabled but unscheduled rather than as something that will arrive.
protocol ReminderScheduling: AnyObject {
  func authorization() async -> ReminderAuthorization

  func requestAuthorization() async -> ReminderAuthorization

  /// Schedules the requests and returns the identifiers that were accepted.
  func schedule(_ requests: [ReminderRequest]) async -> Set<UUID>

  func cancel(ids: [UUID])

  func cancelAll()
}
