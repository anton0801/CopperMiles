import SwiftUI

/// The scaffold every screen sits in.
///
/// Holds the cream background, the screen margin and the rhythm between blocks, so
/// that no screen has to restate them and none of them can drift apart.
struct CMScreen<Content: View>: View {
  var spacing: CGFloat = Theme.Spacing.xLarge
  var showsIndicators = false
  @ViewBuilder var content: Content

  var body: some View {
    ScrollView(.vertical, showsIndicators: showsIndicators) {
      VStack(alignment: .leading, spacing: spacing) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Theme.Spacing.screenMargin)
      .padding(.top, Theme.Spacing.large)
      .padding(.bottom, Theme.Spacing.section)
    }
    .background(Theme.Colour.background.ignoresSafeArea())
  }
}

/// A screen that keeps its main action within reach.
///
/// Long forms scroll, but the thing the traveller came to do stays pinned at the
/// bottom on a soft band, so "Save" is never a scroll away.
struct CMScreenWithAction<Content: View, Action: View>: View {
  var spacing: CGFloat = Theme.Spacing.xLarge
  @ViewBuilder var content: Content
  @ViewBuilder var action: Action

  var body: some View {
    VStack(spacing: 0) {
      CMScreen(spacing: spacing) {
        content
      }

      VStack(spacing: 0) {
        CMDivider(isInset: false)
        action
          .padding(.horizontal, Theme.Spacing.screenMargin)
          .padding(.top, Theme.Spacing.medium)
          .padding(.bottom, Theme.Spacing.small)
      }
      .background(Theme.Colour.background)
    }
    .background(Theme.Colour.background.ignoresSafeArea())
  }
}

/// A form presented as a sheet.
///
/// Cancel sits in the navigation bar and the save action is pinned at the foot, so
/// the two are never confused and neither drifts off-screen while typing.
struct CMEditorSheet<Content: View>: View {
  let title: String
  var saveTitle: String = "Save"
  var saveIcon: String? = "checkmark"
  var isSaveEnabled = true
  let onSave: () -> Void
  let onCancel: () -> Void
  @ViewBuilder var content: Content

  var body: some View {
    NavigationView {
      CMScreenWithAction {
        content
      } action: {
        CMButton(title: saveTitle, icon: saveIcon, prominence: .primary, action: onSave)
          .disabled(!isSaveEnabled)
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel", action: onCancel)
            .foregroundColor(Theme.Colour.secondaryText)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { CMKeyboard.dismiss() }
        }
      }
    }
    .navigationViewStyle(.stack)
    .interactiveDismissDisabled()
  }
}

enum CMKeyboard {
  /// Resigns the first responder, for the keyboard toolbar's Done button.
  static func dismiss() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }
}
