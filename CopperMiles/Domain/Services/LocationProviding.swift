import Foundation

/// Supplies the device's current position, once, on request.
///
/// There is no continuous tracking anywhere in this app: a coordinate is captured
/// only when the traveller taps for it while editing a stop, and refusing permission
/// simply leaves the manual fields available.
protocol LocationProviding: AnyObject {
  func currentCoordinate() async throws -> Coordinate
}

extension DomainError {
  static let locationDenied = DomainError(
    "Location access is off. You can type the coordinates in, or turn access on in Settings."
  )

  static let locationUnavailable = DomainError(
    "Your location could not be read just now. Try again, or type the coordinates in."
  )
}
