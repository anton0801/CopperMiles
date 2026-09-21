import SwiftUI

/// How much weight a button carries on its screen.
enum CMButtonProminence {
  /// The one thing this screen is for. Sun yellow, dark text.
  case primary
  /// A supporting action. Paper with a warm border.
  case secondary
  /// A quiet action that should not compete. Text only.
  case tertiary
  /// Something that removes or ends. Never the primary button on a screen.
  case destructive
}

/// The app's button.
///
/// One type covers every prominence so that a screen cannot invent a new shape, and
/// so the 44-point minimum is guaranteed rather than remembered.
struct CMButton: View {
  let title: String
  var icon: String?
  var prominence: CMButtonProminence = .primary
  var isLoading = false
  var fillsWidth = true
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      HStack(spacing: Theme.Spacing.small) {
        if fillsWidth, prominence == .primary {
          Text(title)
          Spacer(minLength: Theme.Spacing.tiny)
        } else {
          Text(title)
        }

        if isLoading {
          ProgressView().scaleEffect(0.8)
        } else if let icon {
          Image(systemName: icon).font(.system(.subheadline).weight(.bold))
        }
      }
      .font(Font.CM.bodyEmphasis)
      .padding(.horizontal, Theme.Spacing.xLarge)
      .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 52)
      .foregroundColor(foreground)
      .background(background)
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
          .strokeBorder(border, lineWidth: 1)
      )
      .opacity(isEnabled ? 1 : 0.45)
    }
    .buttonStyle(CMPressStyle())
    .disabled(isLoading)
  }

  private var foreground: Color {
    switch prominence {
    case .primary: return Theme.Colour.primaryText
    case .secondary: return Theme.Colour.primaryText
    case .tertiary: return Theme.Colour.secondaryText
    case .destructive: return Theme.Colour.danger
    }
  }

  private var background: Color {
    switch prominence {
    case .primary: return Theme.Colour.action
    case .secondary: return Theme.Colour.surface
    case .tertiary: return .clear
    case .destructive: return Theme.Colour.danger.opacity(0.08)
    }
  }

  private var border: Color {
    switch prominence {
    case .primary: return .clear
    case .secondary: return Theme.Colour.border
    case .tertiary: return .clear
    case .destructive: return Theme.Colour.danger.opacity(0.2)
    }
  }
}

/// A button-shaped label for a `NavigationLink`.
///
/// A link that should look like the screen's main action needs the button's clothes
/// without its `Button`, since wrapping a link in one would swallow the navigation.
struct CMPrimaryLinkLabel: View {
  let title: String
  var icon: String?
  var background: Color = Theme.Colour.action

  var body: some View {
    HStack(spacing: Theme.Spacing.small) {
      Text(title)
      Spacer(minLength: Theme.Spacing.tiny)
      if let icon {
        Image(systemName: icon).font(.system(.subheadline).weight(.bold))
      }
    }
    .font(Font.CM.bodyEmphasis)
    .padding(.horizontal, Theme.Spacing.xLarge)
    .frame(maxWidth: .infinity, minHeight: 52)
    .foregroundColor(Theme.Colour.primaryText)
    .background(background)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
  }
}

/// A round icon button, sized to the minimum tap target.
///
/// Used for the settings gear, a compact add button, or anything that sits in a
/// corner without room for a label. The label is never dropped — it moves to
/// VoiceOver.
struct CMIconButton: View {
  let systemImage: String
  let accessibilityLabel: String
  var prominence: CMButtonProminence = .secondary
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(.body).weight(.semibold))
        .foregroundColor(prominence == .primary ? Theme.Colour.primaryText : Theme.Colour.secondaryText)
        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
        .background(prominence == .primary ? Theme.Colour.action : Theme.Colour.surface)
        .clipShape(Circle())
        .overlay(
          Circle().strokeBorder(
            prominence == .primary ? .clear : Theme.Colour.border,
            lineWidth: 1
          )
        )
    }
    .buttonStyle(CMPressStyle())
    .accessibilityLabel(accessibilityLabel)
  }
}

/// The press feedback shared by every button: a small, quiet dip.
///
/// Deliberately a scale and opacity change rather than a bounce — the brief asks for
/// nothing that hops about.
struct CMPressStyle: ButtonStyle {
  @Environment(\.cmReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.72 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(.cm(reduceMotion: reduceMotion, duration: Theme.Duration.quick), value: configuration.isPressed)
  }
}
