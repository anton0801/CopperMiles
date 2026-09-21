import SwiftUI

private struct ReduceMotionKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Whether this screen should hold still.
  ///
  /// Set once at the root from the system's Reduce Motion **and** the app's own
  /// switch, so a component only has to ask one question and cannot honour one
  /// setting while ignoring the other.
  var cmReduceMotion: Bool {
    get { self[ReduceMotionKey.self] }
    set { self[ReduceMotionKey.self] = newValue }
  }
}
