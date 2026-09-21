import Foundation

/// Turns dates, distances and durations into the strings the app shows.
///
/// Formatters are built once and reused. The old code created a `DateFormatter` on
/// every call, which is the sort of thing that only shows up as a stutter halfway
/// down a long journal.
final class Formatters {
  private let dayAndTime: DateFormatter
  private let fullDayAndTime: DateFormatter
  private let dayOnly: DateFormatter
  private let monthLabel: DateFormatter
  private let decimal: NumberFormatter

  let uses24HourTime: Bool

  init(uses24HourTime: Bool, locale: Locale = .current, calendar: Calendar = .current) {
    self.uses24HourTime = uses24HourTime

    func make(_ template: String) -> DateFormatter {
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.calendar = calendar
      // A template lets the system order the parts the way the traveller's region
      // expects, while the app still decides whether the clock is 12- or 24-hour.
      formatter.setLocalizedDateFormatFromTemplate(template)
      return formatter
    }

    let time = uses24HourTime ? "HH:mm" : "h:mm a"
    dayAndTime = make("MMMd \(time)")
    fullDayAndTime = make("MMMdyyyy \(time)")
    dayOnly = make("MMMd")
    monthLabel = make("MMMMM")

    decimal = NumberFormatter()
    decimal.locale = locale
    decimal.numberStyle = .decimal
    decimal.maximumFractionDigits = 1
  }

  // MARK: - Dates

  func dateAndTime(_ date: Date) -> String {
    dayAndTime.string(from: date)
  }

  func fullDateAndTime(_ date: Date) -> String {
    fullDayAndTime.string(from: date)
  }

  func day(_ date: Date) -> String {
    dayOnly.string(from: date)
  }

  func monthInitial(_ date: Date) -> String {
    monthLabel.string(from: date)
  }

  // MARK: - Numbers

  func number(_ value: Double) -> String {
    decimal.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
  }

  /// A reading with its unit, or a plain statement that there is not one.
  ///
  /// "Not recorded" is used everywhere rather than a dash or a zero, because a trip
  /// without an odometer reading travelled a distance the journal simply does not
  /// know.
  func distance(_ value: Double?, unit: DistanceUnit) -> String {
    guard let value else { return "Not recorded" }
    return "\(number(value)) \(unit.shortName)"
  }

  func odometer(_ value: Double?, unit: DistanceUnit) -> String {
    guard let value else { return "Not recorded" }
    return "\(number(value)) \(unit.shortName)"
  }

  // MARK: - Durations

  /// A span in days, hours and minutes.
  ///
  /// Always described as elapsed time in the surrounding copy: it includes every
  /// stop, and this app never claims to know how much of it was spent driving.
  func duration(_ interval: TimeInterval?) -> String {
    guard let interval, interval >= 0 else { return "—" }

    let totalMinutes = Int(interval / 60)
    let days = totalMinutes / (60 * 24)
    let hours = (totalMinutes / 60) % 24
    let minutes = totalMinutes % 60

    if days > 0 {
      return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
    }
    if hours > 0 {
      return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
    return "\(minutes)m"
  }

  /// How far ahead of departure a reminder fires.
  func leadTime(_ interval: TimeInterval) -> String {
    let hours = interval / 3600
    if hours >= 24, hours.truncatingRemainder(dividingBy: 24) == 0 {
      let days = Int(hours / 24)
      return days == 1 ? "1 day before" : "\(days) days before"
    }
    if hours == 1 { return "1 hour before" }
    if hours.truncatingRemainder(dividingBy: 1) == 0 {
      return "\(Int(hours)) hours before"
    }
    return "\(number(hours)) hours before"
  }
}
