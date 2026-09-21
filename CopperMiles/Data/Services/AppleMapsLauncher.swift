import Foundation
import MapKit
import UIKit

/// Hands a stop to Apple Maps.
///
/// A stop with a coordinate opens at that point. A stop with only an address is
/// handed over as a search, because the app has not resolved it and should not
/// pretend it knows exactly where that café is — the traveller confirms the place in
/// Maps.
final class AppleMapsLauncher: MapsLaunching {
  private let application: UIApplication

  init(application: UIApplication = .shared) {
    self.application = application
  }

  func open(_ stop: Stop) {
    switch MapsDestination(stop: stop) {
    case .coordinate:
      guard let coordinate = stop.coordinate else { return }
      let placemark = MKPlacemark(
        coordinate: CLLocationCoordinate2D(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        )
      )
      let item = MKMapItem(placemark: placemark)
      item.name = stop.name
      item.openInMaps()

    case .addressSearch:
      var components = URLComponents()
      components.scheme = "https"
      components.host = "maps.apple.com"
      components.path = "/"
      components.queryItems = [URLQueryItem(name: "q", value: stop.address)]
      guard let url = components.url else { return }
      application.open(url)

    case .unavailable:
      break
    }
  }
}
