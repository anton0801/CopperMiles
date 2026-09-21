import SwiftUI

/// A label and its value, side by side.
///
/// The workhorse of every detail screen. The value wraps rather than truncating,
/// because a stop name or a vehicle name is exactly the thing the traveller came to
/// read.
struct CMInfoRow: View {
  let icon: String
  let title: String
  let value: String
  var valueColour: Color = Theme.Colour.primaryText

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
      Image(systemName: icon)
        .font(.system(.footnote))
        .foregroundColor(Theme.Colour.secondaryText)
        .frame(width: 20, alignment: .center)

      Text(title)
        .font(Font.CM.callout)
        .foregroundColor(Theme.Colour.secondaryText)

      Spacer(minLength: Theme.Spacing.medium)

      Text(value)
        .font(Font.CM.labelEmphasis)
        .foregroundColor(valueColour)
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, Theme.Spacing.cardPadding)
    .padding(.vertical, Theme.Spacing.medium)
    .accessibilityElement(children: .combine)
  }
}

/// A row that drills into another screen.
struct CMNavigationRow<Destination: View>: View {
  let icon: String
  let title: String
  var detail: String?
  var tint: Color = Theme.Colour.secondaryText
  @ViewBuilder var destination: () -> Destination

  var body: some View {
    NavigationLink(destination: destination) {
      CMRowContent(icon: icon, title: title, detail: detail, tint: tint, showsChevron: true)
    }
    .buttonStyle(.plain)
  }
}

/// A row that performs an action in place.
struct CMActionRow: View {
  let icon: String
  let title: String
  var detail: String?
  var tint: Color = Theme.Colour.secondaryText
  var isDestructive = false
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      CMRowContent(
        icon: icon,
        title: title,
        detail: detail,
        tint: isDestructive ? Theme.Colour.danger : tint,
        titleColour: isDestructive ? Theme.Colour.danger : Theme.Colour.primaryText,
        showsChevron: false
      )
      .opacity(isEnabled ? 1 : 0.45)
    }
    .buttonStyle(CMPressStyle())
  }
}

/// The shared innards of a navigation or action row.
struct CMRowContent: View {
  let icon: String
  let title: String
  var detail: String?
  var tint: Color = Theme.Colour.secondaryText
  var titleColour: Color = Theme.Colour.primaryText
  var showsChevron = false

  var body: some View {
    HStack(spacing: Theme.Spacing.medium) {
      Image(systemName: icon)
        .font(.system(.body))
        .foregroundColor(tint)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
        Text(title)
          .font(Font.CM.label)
          .foregroundColor(titleColour)
          .multilineTextAlignment(.leading)

        if let detail {
          Text(detail)
            .font(Font.CM.footnote)
            .foregroundColor(Theme.Colour.secondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: Theme.Spacing.small)

      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(.caption).weight(.semibold))
          .foregroundColor(Theme.Colour.secondaryText.opacity(0.6))
      }
    }
    .padding(.horizontal, Theme.Spacing.cardPadding)
    .padding(.vertical, Theme.Spacing.medium)
    .frame(minHeight: Theme.minimumTapTarget)
    .contentShape(Rectangle())
  }
}

/// A switch with its own explanation underneath.
struct CMToggleRow: View {
  let title: String
  var hint: String?
  @Binding var isOn: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
      Toggle(isOn: $isOn) {
        Text(title)
          .font(Font.CM.label)
          .foregroundColor(Theme.Colour.primaryText)
      }
      .tint(Theme.Colour.success)

      if let hint {
        Text(hint)
          .font(Font.CM.footnote)
          .foregroundColor(Theme.Colour.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, Theme.Spacing.cardPadding)
    .padding(.vertical, Theme.Spacing.medium)
    .frame(minHeight: Theme.minimumTapTarget)
  }
}

/// A large figure with its label, for the summary tiles.
struct CMStatistic: View {
  let value: String
  let label: String
  var tint: Color = Theme.Colour.primaryText

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
      Text(value)
        .font(Font.CM.statistic)
        .foregroundColor(tint)
        .minimumScaleFactor(0.6)
        .lineLimit(1)

      Text(label)
        .font(Font.CM.footnote)
        .foregroundColor(Theme.Colour.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// A bar showing how far the checklist has come.
///
/// An empty checklist reads as "no checklist" rather than as a full bar: nothing to
/// do is not the same as everything done.
struct CMProgressBar: View {
  let progress: ChecklistProgress

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Theme.Colour.primaryText.opacity(0.08))

        if let fraction = progress.fraction, fraction > 0 {
          Capsule()
            .fill(Theme.Colour.success)
            .frame(width: max(6, geometry.size.width * fraction))
        }
      }
    }
    .frame(height: 8)
    .accessibilityElement()
    .accessibilityLabel("Preparation")
    .accessibilityValue(
      progress.isEmpty
        ? "No checklist"
        : "\(progress.checked) of \(progress.total) ready"
    )
  }
}
