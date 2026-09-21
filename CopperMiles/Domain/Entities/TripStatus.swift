import Foundation

/// Where a trip sits in its life cycle.
///
/// The progression is `draft → planned → active → completed`, with `cancelled`
/// available as an exit from the two planning states. Only one trip in the whole
/// journal may be `active` at a time.
enum TripStatus: String, CaseIterable, Equatable {
  case draft
  case planned
  case active
  case completed
  case cancelled

  /// A trip that is still being arranged and may be edited freely.
  var isPlanning: Bool { self == .draft || self == .planned }

  /// A trip that has a recorded actual start, so visits and notes may attach to it.
  var hasStarted: Bool { self == .active || self == .completed }
}

/// How a trip ended, recorded by the traveller at the finish step.
enum TripOutcome: String, CaseIterable, Equatable {
  case completed
  case endedEarly
}
