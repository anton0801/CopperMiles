import Foundation
import UserNotifications

/// Schedules departure reminders through the system notification centre.
///
/// Reminders fire on a calendar trigger rather than a countdown, so a phone that
/// slept for a week still rings at the right hour rather than an hour measured from
/// whenever the app last ran.
final class UserNotificationScheduler: ReminderScheduling {
  private let center: UNUserNotificationCenter
  private let calendar: Calendar

  init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
    self.center = center
    self.calendar = calendar
  }

  func authorization() async -> ReminderAuthorization {
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return .allowed
    case .notDetermined:
      return .notDetermined
    case .denied:
      return .denied
    @unknown default:
      return .denied
    }
  }

  func requestAuthorization() async -> ReminderAuthorization {
    let granted =
      (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    return granted ? .allowed : .denied
  }

  func schedule(_ requests: [ReminderRequest]) async -> Set<UUID> {
    var scheduled: Set<UUID> = []

    for request in requests {
      let content = UNMutableNotificationContent()
      content.title = "A little nudge from Pip"
      content.body = "\(Self.body(for: request.kind)) · \(request.tripName)"
      content.sound = .default
      content.userInfo = [
        NotificationPayload.tripIDKey: request.tripID.uuidString,
        NotificationPayload.kindKey: request.kind.rawValue,
      ]

      let components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute],
        from: request.fireDate
      )
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

      do {
        try await center.add(
          UNNotificationRequest(
            identifier: request.id.uuidString,
            content: content,
            trigger: trigger
          )
        )
        scheduled.insert(request.id)
      } catch {
        // A refusal is reported by the identifier's absence from the result, which
        // the caller turns into an honest "not scheduled" badge.
        continue
      }
    }
    return scheduled
  }

  func cancel(ids: [UUID]) {
    let identifiers = ids.map(\.uuidString)
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  func cancelAll() {
    center.removeAllPendingNotificationRequests()
    center.removeAllDeliveredNotifications()
  }

  private static func body(for kind: ReminderKind) -> String {
    switch kind {
    case .prepareCar: return "Time to get the car ready"
    case .reviewStops: return "A moment to look over your stops"
    case .packPersonalItems: return "Worth packing your things"
    }
  }
}

/// The keys a reminder carries, so tapping one opens the right screen.
enum NotificationPayload {
  static let tripIDKey = "tripID"
  static let kindKey = "reminderKind"

  /// What a tapped reminder should open.
  enum Target: Equatable {
    case checklist(tripID: UUID)
    case tripPlan(tripID: UUID)
  }

  static func target(from userInfo: [AnyHashable: Any]) -> Target? {
    guard
      let raw = userInfo[tripIDKey] as? String,
      let tripID = UUID(uuidString: raw)
    else { return nil }

    let kind = (userInfo[kindKey] as? String).flatMap(ReminderKind.init(rawValue:))
    switch kind {
    case .prepareCar, .packPersonalItems:
      return .checklist(tripID: tripID)
    case .reviewStops, .none:
      return .tripPlan(tripID: tripID)
    }
  }
}
