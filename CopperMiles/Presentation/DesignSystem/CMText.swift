import SwiftUI

/// The small tracked capitals that sit above a title.
struct CMEyebrow: View {
  let text: String
  var colour: Color = Theme.Colour.secondaryText

  var body: some View {
    Text(text.uppercased())
      .font(Font.CM.eyebrow)
      .cmTracked(1.6)
      .foregroundColor(colour)
  }
}

/// The title block at the top of a screen.
///
/// Illustrations are decorative and hidden from VoiceOver: the words carry the
/// meaning, and Pip is there for warmth.
struct CMScreenHeader<Trailing: View>: View {
  let eyebrow: String
  let title: String
  var subtitle: String?
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.medium) {
      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        CMEyebrow(text: eyebrow)

        Text(title)
          .font(Font.CM.screenTitle)
          .foregroundColor(Theme.Colour.primaryText)
          .fixedSize(horizontal: false, vertical: true)

        if let subtitle {
          Text(subtitle)
            .font(Font.CM.callout)
            .foregroundColor(Theme.Colour.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      trailing
    }
    .accessibilityElement(children: .combine)
  }
}

extension CMScreenHeader where Trailing == EmptyView {
  init(eyebrow: String, title: String, subtitle: String? = nil) {
    self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
  }
}

/// A heading between sections of a screen, with an optional count on the right.
struct CMSectionHeader<Accessory: View>: View {
  let title: String
  var detail: String?
  @ViewBuilder var accessory: Accessory

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
      Text(title)
        .font(Font.CM.sectionTitle)
        .foregroundColor(Theme.Colour.primaryText)

      Spacer(minLength: Theme.Spacing.small)

      if let detail {
        Text(detail)
          .font(Font.CM.footnote)
          .foregroundColor(Theme.Colour.secondaryText)
      }
      accessory
    }
  }
}

extension CMSectionHeader where Accessory == EmptyView {
  init(title: String, detail: String? = nil) {
    self.init(title: title, detail: detail) { EmptyView() }
  }
}

/// A small status badge.
struct CMTag: View {
  let text: String
  var colour: Color = Theme.Colour.secondaryText

  var body: some View {
    Text(text.uppercased())
      .font(Font.CM.badge)
      .cmTracked(0.8)
      .foregroundColor(colour)
      .padding(.horizontal, Theme.Spacing.small)
      .padding(.vertical, Theme.Spacing.tiny + 2)
      .background(colour.opacity(0.12))
      .clipShape(Capsule())
  }
}

/// A short explanatory line under a control.
///
/// Used constantly in this app, because most of its rules are worth a sentence: what
/// "elapsed" includes, why a unit is locked, what an export will carry.
struct CMHint: View {
  let text: String
  var icon: String?
  var tone: Tone = .neutral

  enum Tone {
    case neutral
    case warning
    case positive
  }

  var body: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.small) {
      if let icon {
        Image(systemName: icon)
          .font(.system(.caption))
          .foregroundColor(colour)
      }
      Text(text)
        .font(Font.CM.footnote)
        .foregroundColor(colour)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var colour: Color {
    switch tone {
    case .neutral: return Theme.Colour.secondaryText
    case .warning: return Theme.Colour.danger
    case .positive: return Theme.Colour.success
    }
  }
}

/// What a screen shows before the traveller has put anything in it.
///
/// Always names the next step rather than just reporting that there is nothing here.
struct CMEmptyState<Action: View>: View {
  let illustration: CMIllustration
  var illustrationSize: CGFloat = 120
  let title: String
  let message: String
  @ViewBuilder var action: Action

  var body: some View {
    VStack(spacing: Theme.Spacing.large) {
      CMAsset(illustration, width: illustrationSize, height: illustrationSize)

      Text(title)
        .font(Font.CM.cardTitle)
        .foregroundColor(Theme.Colour.primaryText)
        .multilineTextAlignment(.center)

      Text(message)
        .font(Font.CM.callout)
        .foregroundColor(Theme.Colour.secondaryText)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      action
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Theme.Spacing.xxLarge)
    .padding(.horizontal, Theme.Spacing.large)
  }
}

extension CMEmptyState where Action == EmptyView {
  init(
    illustration: CMIllustration,
    illustrationSize: CGFloat = 120,
    title: String,
    message: String
  ) {
    self.init(
      illustration: illustration,
      illustrationSize: illustrationSize,
      title: title,
      message: message
    ) { EmptyView() }
  }
}
