import SwiftUI

/// The twelve drawn assets, named once.
///
/// A typed case per asset means a screen cannot ask for a file that is not in the
/// catalogue, and the compiler catches a rename that a string literal would turn
/// into a silently blank space.
enum CMIllustration: String {
  case onboardingCompanion = "cm_onboarding_companion"
  case onboardingStops = "cm_onboarding_stops"
  case onboardingMemories = "cm_onboarding_memories"

  case pipHome = "cm_pip_home"
  case pipOnTheRoad = "cm_pip_road"
  case pipTripComplete = "cm_pip_trip_complete"

  case compactCar = "cm_compact_car"
  case departureCalendar = "cm_departure_calendar"
  case roadSign = "cm_road_sign"
  case stopMarker = "cm_stop_marker"
  case preparationBoard = "cm_preparation_board"
  case roadNotebook = "cm_road_notebook"
}

/// Draws one of the illustrations at a given size.
///
/// Always hidden from VoiceOver. These are decoration around text that already says
/// what the screen is for, and announcing "road sign" between a heading and a button
/// would only get in the way.
struct CMAsset: View {
  let illustration: CMIllustration
  var width: CGFloat
  var height: CGFloat

  init(_ illustration: CMIllustration, width: CGFloat, height: CGFloat) {
    self.illustration = illustration
    self.width = width
    self.height = height
  }

  var body: some View {
    Image(illustration.rawValue)
      .resizable()
      .scaledToFit()
      .frame(width: width, height: height)
      .accessibilityHidden(true)
  }
}

/// A photo the traveller attached, loaded from the attachment store.
///
/// Images are read through the store's cache rather than carried around in the
/// journal, so a long list of journal entries stays light.
struct CMPhoto: View {
  let id: AttachmentID
  var contentMode: ContentMode = .fill

  @EnvironmentObject private var environment: AppEnvironment

  var body: some View {
    Group {
      if let data = environment.attachments.data(for: id), let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      } else {
        Rectangle()
          .fill(Theme.Colour.accentSoft.opacity(0.18))
          .overlay(
            Image(systemName: "photo")
              .font(.system(.title3))
              .foregroundColor(Theme.Colour.secondaryText.opacity(0.6))
          )
      }
    }
    .accessibilityLabel("Photo")
  }
}
