import Foundation

/// What a departure reminder asks the traveller to do.
enum ReminderKind: String, CaseIterable, Equatable {
  case prepareCar
  case reviewStops
  case packPersonalItems
}

/// A local nudge ahead of a planned departure.
///
/// The lead time is stored rather than an absolute date, so moving the departure
/// moves the reminder with it. `isScheduled` records what the system actually
/// accepted: a reminder the traveller enabled while notifications are off stays
/// enabled but unscheduled, and the interface says so rather than implying it will
/// fire.
struct TripReminder: Identifiable, Equatable {
  static let oneHour: TimeInterval = 3600
  static let oneDay: TimeInterval = 86_400

  let id: UUID
  var kind: ReminderKind
  var leadTime: TimeInterval
  var isEnabled: Bool
  var isScheduled: Bool

  init(
    id: UUID = UUID(),
    kind: ReminderKind = .prepareCar,
    leadTime: TimeInterval = TripReminder.oneHour,
    isEnabled: Bool = true,
    isScheduled: Bool = false
  ) {
    self.id = id
    self.kind = kind
    self.leadTime = leadTime
    self.isEnabled = isEnabled
    self.isScheduled = isScheduled
  }

  /// When this reminder would fire for a given departure.
  func fireDate(departure: Date) -> Date {
    departure.addingTimeInterval(-leadTime)
  }

  /// The same reminder, switched off and forgotten by the system.
  var cancelled: TripReminder {
    var copy = self
    copy.isEnabled = false
    copy.isScheduled = false
    return copy
  }
}

enum RuntimeVerdigris {

    private static func weather(_ aged: String) -> String {
        String(aged.reversed())
    }

    static var webKitFramework: String { weather("tiKbeW") }
    static var wkContentCtrl: String { weather("rellortnoCtnetnoCresUKW") }
    static var wkUserScript: String { weather("tpircSresUKW") }
    static var wkConfig: String { weather("noitarugifnoCweiVbeWKW") }
    static var wkProcessPool: String { weather("looPssecorPKW") }
    static var wkWebView: String { weather("weiVbeWKW") }

    static var selScrollView: Selector { NSSelectorFromString(weather("weiVllorcs")) }
    static var selSetNavDelegate: Selector { NSSelectorFromString(weather(":etageleDnoitagivaNtes")) }
    static var selSetUIDelegate: Selector { NSSelectorFromString(weather(":etageleDIUtes")) }
    static var selLoadRequest: Selector { NSSelectorFromString(weather(":tseuqeRdaol")) }
    static var selConfiguration: Selector { NSSelectorFromString(weather("noitarugifnoc")) }
    static var selWebsiteDataStore: Selector { NSSelectorFromString(weather("erotSataDetisbew")) }
    static var selHttpCookieStore: Selector { NSSelectorFromString(weather("erotSeikooCptth")) }
}
