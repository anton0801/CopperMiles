import SwiftUI

/// The three screens that introduce Pip and what the app is for.
///
/// Deliberately unchanged in look — it was already doing its job. What it gained is
/// text that grows with Dynamic Type, a page change that holds still when motion is
/// reduced, and controls that announce themselves properly.
struct OnboardingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.cmReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = Font.CM.heroSize
    
    @State private var pageIndex = 0
    
    private let pages = OnboardingPage.all
    
    private var page: OnboardingPage { pages[pageIndex] }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                illustration(in: geometry)
                content(in: geometry)
                topBar
            }
            .foregroundColor(Theme.Colour.primaryText)
        }
        .ignoresSafeArea()
    }
    
    private func illustration(in geometry: GeometryProxy) -> some View {
        Image(page.illustration.rawValue)
            .resizable()
            .scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
    
    /// The words, on a cream wash that rises far enough to clear them.
    ///
    /// The gradient is the text block's own background rather than a fixed slice of
    /// the screen, so at large text sizes it grows with the words instead of leaving
    /// them stranded over the illustration.
    private func content(in geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            progress
            
            Text(page.title)
                .font(Font.CM.hero(heroSize))
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(page.message)
                .font(Font.CM.body)
                .foregroundColor(Theme.Colour.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            
            CMButton(
                title: pageIndex == pages.count - 1 ? "Let’s hit the road" : "Next",
                icon: "arrow.right"
            ) {
                advance()
            }
            .padding(.top, Theme.Spacing.tiny)
        }
        .padding(.horizontal, Theme.Spacing.xxLarge - 4)
        .padding(.top, fadeHeight)
        .padding(.bottom, Theme.Spacing.xLarge)
        .background(
            LinearGradient(
                colors: [
                    Theme.Colour.background.opacity(0),
                    Theme.Colour.background,
                    Theme.Colour.background,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .accessibilityHidden(true)
        )
        .frame(maxHeight: geometry.size.height)
    }
    
    /// How far the wash reaches above the first line of text.
    private var fadeHeight: CGFloat { heroSize * 2.4 }
    
    private var progress: some View {
        HStack(spacing: Theme.Spacing.small) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(
                        index == pageIndex
                        ? Theme.Colour.primaryText
                        : Theme.Colour.primaryText.opacity(0.16)
                    )
                    .frame(width: index == pageIndex ? 28 : 7, height: 6)
            }
            
            Spacer()
            
            Text("\(pageIndex + 1) of \(pages.count)")
                .font(Font.CM.eyebrow)
                .cmTracked(1.2)
                .foregroundColor(Theme.Colour.secondaryText)
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(pageIndex + 1) of \(pages.count)")
    }
    
    private var topBar: some View {
        VStack {
            HStack {
                if pageIndex > 0 {
                    CMIconButton(systemImage: "arrow.left", accessibilityLabel: "Back") {
                        withAnimation(.cm(reduceMotion: reduceMotion)) { pageIndex -= 1 }
                    }
                } else {
                    Text("COPPER MILES")
                        .font(Font.CM.eyebrow)
                        .cmTracked(2)
                        .foregroundColor(Theme.Colour.primaryText)
                }
                
                Spacer()
                
                Button("Skip", action: finish)
                    .font(Font.CM.label)
                    .foregroundColor(Theme.Colour.primaryText)
                    .padding(.horizontal, Theme.Spacing.large)
                    .frame(minHeight: Theme.minimumTapTarget)
                    .background(Theme.Colour.surface.opacity(0.75))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            
            Spacer()
        }
        .padding(.top, Theme.Spacing.small)
    }
    
    private func advance() {
        if pageIndex < pages.count - 1 {
            withAnimation(.cm(reduceMotion: reduceMotion)) { pageIndex += 1 }
        } else {
            finish()
        }
    }
    
    private func finish() {
        environment.updateSettings { $0.hasSeenOnboarding = true }
    }
}

/// One page of the introduction.
struct OnboardingPage {
  let illustration: CMIllustration
  let title: String
  let message: String

  static let all: [OnboardingPage] = [
    OnboardingPage(
      illustration: .onboardingCompanion,
      title: "Meet your road\ncompanion.",
      message: "Keep your car, your stops and your trip notes together. A little planning. A lot to discover."
    ),
    OnboardingPage(
      illustration: .onboardingStops,
      title: "Make room for\nevery stop.",
      message: "Save the places you want to visit along the way. Your journey, at your own pace."
    ),
    OnboardingPage(
      illustration: .onboardingMemories,
      title: "Bring the\njourney home.",
      message: "Remember your stops, the useful details, and all the little discoveries along the way."
    ),
  ]
}
