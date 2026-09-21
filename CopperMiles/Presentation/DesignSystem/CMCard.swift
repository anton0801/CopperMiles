import SwiftUI

/// A sheet of paper resting on the cream background.
///
/// Cards are the app's only grouping device. Keeping them in one type is what makes
/// every screen agree on corner radius, padding and the weight of the shadow.
struct CMCard<Content: View>: View {
  var padding: CGFloat = Theme.Spacing.cardPadding
  var background: Color = Theme.Colour.surface
  var isHighlighted = false
  @ViewBuilder var content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(padding)
      .background(background)
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
          .strokeBorder(
            isHighlighted ? Theme.Colour.accent.opacity(0.35) : Theme.Colour.border,
            lineWidth: isHighlighted ? 1.5 : 1
          )
      )
      .shadow(
        color: Theme.Shadow.colour,
        radius: Theme.Shadow.radius,
        y: Theme.Shadow.offsetY
      )
  }
}

/// A hairline between rows inside a card.
///
/// Inset from the leading edge so it reads as a separator between items rather than
/// as a line cutting the card in two.
struct CMDivider: View {
  var isInset = true

  var body: some View {
    Rectangle()
      .fill(Theme.Colour.separator)
      .frame(height: 1)
      .padding(.leading, isInset ? Theme.Spacing.cardPadding : 0)
  }
}

/// A card holding one row per element, divided.
///
/// Most lists in the app are built from a collection, so this covers them without
/// any bookkeeping at the call site. A card of unlike rows is written out as a plain
/// `CMCard` with dividers where the author wants them — explicit beats clever when
/// there are only ever two or three of them.
struct CMRowList<Element: Identifiable, Row: View>: View {
  let elements: [Element]
  @ViewBuilder var row: (Element) -> Row

  var body: some View {
    CMCard(padding: 0) {
      VStack(spacing: 0) {
        ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
          row(element)
          if index < elements.count - 1 {
            CMDivider()
          }
        }
      }
    }
  }
}
