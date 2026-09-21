import SwiftUI

extension Font {

  /// The type scale, built on the system text styles.
  ///
  /// Every face here is derived from a text style rather than a fixed point size,
  /// which is what makes the whole app grow with the traveller's Dynamic Type
  /// setting. A literal `.system(size: 15)` would look right on one phone and lock
  /// the interface out of accessibility sizes on every other.
  enum CM {
    /// The big rounded statement on Home and at the top of onboarding.
    ///
    /// Larger than `.largeTitle` on its own, which is why it is sized through
    /// `@ScaledMetric` at the call site rather than fixed here — see `heroSize`.
    static func hero(_ size: CGFloat) -> Font {
      .system(size: size, weight: .heavy, design: .rounded)
    }

    /// The point size the hero uses at the default text size. Pass it through
    /// `@ScaledMetric(relativeTo: .largeTitle)` so it still grows with the setting.
    static let heroSize: CGFloat = 40

    /// A screen's own title.
    static let screenTitle = Font.system(.title, design: .rounded).weight(.heavy)
    /// The headline of a card.
    static let cardTitle = Font.system(.title3, design: .rounded).weight(.bold)
    /// A section heading within a screen.
    static let sectionTitle = Font.system(.headline, design: .rounded).weight(.bold)
    /// A large figure in a statistic tile.
    static let statistic = Font.system(.title, design: .rounded).weight(.heavy)

    static let body = Font.system(.body)
    static let bodyEmphasis = Font.system(.body).weight(.semibold)
    static let callout = Font.system(.callout)
    static let label = Font.system(.subheadline).weight(.medium)
    static let labelEmphasis = Font.system(.subheadline).weight(.semibold)
    static let footnote = Font.system(.footnote)
    static let caption = Font.system(.caption)

    /// The small tracked capitals above a title.
    static let eyebrow = Font.system(.caption2, design: .rounded).weight(.heavy)
    /// Text inside a tag or badge.
    static let badge = Font.system(.caption2, design: .rounded).weight(.bold)
  }
}

extension Text {
  /// Widens the letter spacing of eyebrows and badges.
  ///
  /// Declared on `Text` rather than on `View`: the `View` form of `tracking` only
  /// arrived in iOS 16, and this app runs from iOS 15.
  func cmTracked(_ amount: CGFloat = 1.2) -> Text {
    tracking(amount)
  }
}

extension Animation {
  /// The app's standard transition, or none at all when motion should be reduced.
  ///
  /// The traveller can ask for stillness in two places — the system's Reduce Motion
  /// and the app's own switch — and both are honoured through this one call so no
  /// screen can forget.
  static func cm(reduceMotion: Bool, duration: Double = Theme.Duration.standard) -> Animation? {
    reduceMotion ? nil : .easeOut(duration: duration)
  }
}
