import Foundation

/// Hands a stop to the system maps app.
///
/// Copper Miles plans places, not routes: it never draws a map, estimates an arrival
/// or reads traffic. When the traveller wants directions, the chosen stop is opened
/// somewhere that does that properly.
protocol MapsLaunching: AnyObject {
  /// Opens the stop's coordinate when it has one, otherwise searches for its address.
  func open(_ stop: Stop)
}

/// How a stop will be handed over, so the interface can say what will happen.
enum MapsDestination: Equatable {
  case coordinate
  case addressSearch
  case unavailable

  init(stop: Stop) {
    if stop.coordinate != nil {
      self = .coordinate
    } else if !stop.address.isBlank {
      self = .addressSearch
    } else {
      self = .unavailable
    }
  }
}
