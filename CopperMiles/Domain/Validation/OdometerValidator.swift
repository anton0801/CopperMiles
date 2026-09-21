import Foundation

/// Checks odometer readings, which the journal's distances depend on.
enum OdometerValidator {
  /// Reads a typed-in value. An empty field means "not recorded", which is always
  /// allowed: a trip is worth keeping even without its numbers.
  static func reading(_ text: String) throws -> Double? {
    let text = text.trimmed
    if text.isEmpty { return nil }

    guard
      let value = Double(text.replacingOccurrences(of: ",", with: ".")),
      value.isFinite,
      value >= 0
    else {
      throw DomainError("An odometer reading is a number of 0 or more.")
    }
    return value
  }

  static func validate(_ value: Double?) throws {
    guard let value else { return }
    guard value.isFinite, value >= 0 else {
      throw DomainError("An odometer reading is a number of 0 or more.")
    }
  }

  /// A new start reading below the last one known for the vehicle needs a reason,
  /// so the journal never quietly contains a distance that could not have happened.
  static func validateStartReading(
    _ value: Double?,
    previous: Journal.OdometerRecord?,
    explanation: OdometerExplanation?
  ) throws {
    try validate(value)
    guard let value, let previous, value < previous.value, explanation == nil else { return }
    throw DomainError(
      "This reading is below the last one recorded for this vehicle. "
        + "Choose Corrected Reading or Odometer Replaced to explain it."
    )
  }
}
