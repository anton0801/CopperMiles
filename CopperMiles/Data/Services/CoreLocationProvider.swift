import CoreLocation
import Foundation

/// Reads the device's position once, when the traveller asks for it.
///
/// There is no background updating and no monitoring: the manager is asked for a
/// single fix while a stop is being edited, and it stops as soon as that fix, or a
/// refusal, comes back.
@MainActor
final class CoreLocationProvider: NSObject, LocationProviding {
  private let manager = CLLocationManager()
  private var pending: CheckedContinuation<Coordinate, Error>?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func currentCoordinate() async throws -> Coordinate {
    if pending != nil {
      throw DomainError("Still looking for your location. One moment.")
    }

    return try await withCheckedThrowingContinuation { continuation in
      pending = continuation

      switch manager.authorizationStatus {
      case .notDetermined:
        manager.requestWhenInUseAuthorization()
      case .restricted, .denied:
        finish(.failure(DomainError.locationDenied))
      case .authorizedWhenInUse, .authorizedAlways:
        manager.requestLocation()
      @unknown default:
        finish(.failure(DomainError.locationUnavailable))
      }
    }
  }

  private func finish(_ result: Result<Coordinate, Error>) {
    guard let continuation = pending else { return }
    pending = nil
    continuation.resume(with: result)
  }
}

extension CoreLocationProvider: @preconcurrency CLLocationManagerDelegate {
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard pending != nil else { return }

    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      manager.requestLocation()
    case .denied, .restricted:
      finish(.failure(DomainError.locationDenied))
    case .notDetermined:
      break
    @unknown default:
      finish(.failure(DomainError.locationUnavailable))
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      finish(.failure(DomainError.locationUnavailable))
      return
    }
    finish(
      .success(
        Coordinate(
          latitude: location.coordinate.latitude,
          longitude: location.coordinate.longitude
        )
      )
    )
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finish(.failure(DomainError.locationUnavailable))
  }
}
