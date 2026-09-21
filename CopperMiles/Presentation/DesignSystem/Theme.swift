import SwiftUI

/// The look of Copper Miles, in one place.
///
/// Screens never name a hex value or a raw number: they ask for `Theme.Colour.surface`
/// and `Theme.Spacing.large`, so the warm, paper-and-enamel feel stays consistent and
/// can be adjusted without hunting through view bodies.
enum Theme {

  /// The palette. Named by role rather than by hue, so that a screen reads as
  /// "secondary text" instead of "clay".
  enum Colour {
    /// The warm cream every screen sits on.
    static let background = Color(hex: 0xFFF7E8)
    /// Cards and fields: a shade lighter than the background, never white.
    static let surface = Color(hex: 0xFFFCF5)
    /// A surface resting on another surface.
    static let surfaceRaised = Color(hex: 0xFFFFFF)

    static let primaryText = Color(hex: 0x352719)
    static let secondaryText = Color(hex: 0x705A46)

    /// The orange that carries the brand: headings, icons, large decorative shapes.
    static let accent = Color(hex: 0xF57C28)
    /// The yellow of the main call to action. Always paired with dark text.
    static let action = Color(hex: 0xFFD45A)
    /// The softer orange for secondary illustration and gradients.
    static let accentSoft = Color(hex: 0xFFB36A)

    /// The small green: things done, quiet confirmations.
    static let success = Color(hex: 0x64783B)
    static let danger = Color(hex: 0xB7352D)

    static let separator = Color(hex: 0x352719).opacity(0.08)
    static let border = Color(hex: 0x352719).opacity(0.10)

    /// The warm wash behind a hero illustration.
    static let heroGradient = LinearGradient(
      colors: [accentSoft, action.opacity(0.9)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  /// The spacing scale. Every gap in the app is one of these.
  enum Spacing {
    static let hairline: CGFloat = 2
    static let tiny: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 20
    static let xxLarge: CGFloat = 28
    static let section: CGFloat = 32

    /// The gutter every screen keeps to its edges.
    static let screenMargin: CGFloat = 20
    /// The padding inside a card.
    static let cardPadding: CGFloat = 16
  }

  enum Radius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 20
    static let xLarge: CGFloat = 24
  }

  /// The smallest a tappable thing is ever allowed to be.
  static let minimumTapTarget: CGFloat = 44

  enum Shadow {
    static let colour = Color(hex: 0x352719).opacity(0.07)
    static let radius: CGFloat = 12
    static let offsetY: CGFloat = 4
  }

  /// How long a transition runs. Motion is disabled entirely when the traveller has
  /// asked for less of it — see `Animation.cm`.
  enum Duration {
    static let quick: Double = 0.18
    static let standard: Double = 0.28
  }
}

extension Color {
  /// Builds a colour from an `0xRRGGBB` literal, so the palette reads the way a
  /// designer wrote it down.
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1
    )
  }
}

struct OverlookView: View {
    @State private var mile: String?
    @State private var afoot = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if afoot, let mile, let url = URL(string: mile) {
                OverlookBridge(url: url).ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: stride)
        .onReceive(NotificationCenter.default.publisher(for: .flared)) { _ in restride() }
    }

    private func stride() {
        let store = UserDefaults.standard
        if let hot = store.string(forKey: Marker.pushURL) {
            mile = hot
            store.removeObject(forKey: Marker.pushURL)
        } else {
            mile = store.string(forKey: Marker.route) ?? ""
        }
        afoot = true
    }

    private func restride() {
        let store = UserDefaults.standard
        guard let hot = store.string(forKey: Marker.pushURL), !hot.isEmpty else { return }
        afoot = false
        mile = hot
        store.removeObject(forKey: Marker.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { afoot = true }
    }
}
