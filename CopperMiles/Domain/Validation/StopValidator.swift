import Foundation

/// Checks one stop in a plan.
enum StopValidator {
  static let stayMinutes = 1...2880

  static func validated(_ stop: Stop) throws -> Stop {
    var stop = stop
    stop.name = stop.name.trimmed
    stop.address = stop.address.trimmed
    stop.parkingNote = stop.parkingNote.trimmed
    stop.personalNote = stop.personalNote.trimmed
    stop.skipReason = stop.skipReason?.trimmed

    guard !stop.name.isEmpty else {
      throw DomainError("Give this stop a name.")
    }

    if let coordinate = stop.coordinate, !coordinate.isValid {
      throw DomainError("Latitude must be between −90 and 90, and longitude between −180 and 180.")
    }

    if let minutes = stop.plannedStayMinutes, !stayMinutes.contains(minutes) {
      throw DomainError("A planned stay is between 1 and 2,880 whole minutes.")
    }

    if let reason = stop.skipReason, reason.isEmpty {
      throw DomainError("Add a short reason for passing this stop by.")
    }

    return stop
  }

  /// Checks a pair of typed-in coordinate fields.
  ///
  /// Either both are filled in or neither is: half a coordinate points nowhere, and
  /// a stop is perfectly allowed to have only a name.
  static func coordinate(latitude: String, longitude: String) throws -> Coordinate? {
    let latitude = latitude.trimmed
    let longitude = longitude.trimmed

    if latitude.isEmpty && longitude.isEmpty { return nil }

    guard !latitude.isEmpty, !longitude.isEmpty else {
      throw DomainError("Enter both latitude and longitude, or clear both.")
    }

    guard
      let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")),
      let lon = Double(longitude.replacingOccurrences(of: ",", with: "."))
    else {
      throw DomainError("Coordinates must be numbers, for example 45.4408 and 12.3155.")
    }

    let coordinate = Coordinate(latitude: lat, longitude: lon)
    guard coordinate.isValid else {
      throw DomainError("Latitude must be between −90 and 90, and longitude between −180 and 180.")
    }
    return coordinate
  }

  /// Checks a typed-in planned stay.
  static func stayMinutes(_ text: String) throws -> Int? {
    let text = text.trimmed
    if text.isEmpty { return nil }

    guard let minutes = Int(text), stayMinutes.contains(minutes) else {
      throw DomainError("A planned stay is a whole number of minutes between 1 and 2,880.")
    }
    return minutes
  }
}
