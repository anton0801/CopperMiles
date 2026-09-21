import Foundation

/// The unit a vehicle's odometer is read in.
///
/// A vehicle's unit is fixed once it has recorded a trip; the report unit in
/// Settings is a separate, freely changeable presentation choice. Conversion is
/// therefore always explicit, and never rewrites a stored reading unless the
/// traveller asks for it in the conversion preview.
enum DistanceUnit: String, CaseIterable, Equatable {
  case kilometres
  case miles

  private static let metresPerMile = 1609.344
  private static let metresPerKilometre = 1000.0

  private var metresPerUnit: Double {
    switch self {
    case .kilometres: return Self.metresPerKilometre
    case .miles: return Self.metresPerMile
    }
  }

  func converting(_ value: Double, to unit: DistanceUnit) -> Double {
    guard self != unit else { return value }
    return value * metresPerUnit / unit.metresPerUnit
  }
}
