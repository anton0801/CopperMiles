import SwiftUI

struct LoadingView: View {
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 500

            ZStack {
                Image("main_background_for_app")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                CMJourneyLoader()
                    .scaleEffect(compact ? 0.65 : min(1, geometry.size.width / 320))
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height * (compact ? 0.80 : 0.76)
                    )
            }
        }
        .ignoresSafeArea()
    }
}

struct CMJourneyLoader: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cmReduceMotion) private var appReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            let time = reduceMotion ? 0 : max(0, timeline.date.timeIntervalSince(startedAt))

            VStack(spacing: 14) {
                JourneyScene(time: time)
                    .frame(width: 280, height: 136)

                HStack(spacing: 9) {
                    Text("Loading")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))

                    HStack(spacing: 5) {
                        ForEach(0..<3) { index in
                            let pulse = reduceMotion ? 0.65 : (sin(time * .pi * 2 / 1.2 - Double(index) * 0.8) + 1) / 2
                            Circle()
                                .fill(Theme.Colour.action)
                                .frame(width: 4, height: 4)
                                .opacity(0.3 + pulse * 0.7)
                                .offset(y: reduceMotion ? 0 : -pulse * 3)
                        }
                    }
                }
            }
            .frame(width: 280)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading Copper Miles"))
        .allowsHitTesting(false)
    }
}

private struct JourneyScene: View {
    let time: TimeInterval

    private var bounce: Double { sin(time * .pi * 2 / 0.8) }
    private var hop: Double { (1 - cos(time * .pi * 2 / 1.6)) / 2 }

    var body: some View {
        ZStack {
            // A quiet pool of warm light anchors the illustrations to the road.
            Ellipse()
                .fill(Theme.Colour.accent.opacity(0.16))
                .frame(width: 190, height: 28)
                .blur(radius: 14)
                .position(x: 141, y: 112)

            road
                .position(x: 140, y: 124)

            speedLines

            Ellipse()
                .fill(Color.black.opacity(0.24))
                .frame(width: 46, height: 7)
                .scaleEffect(x: 1 - hop * 0.18, y: 1)
                .opacity(1 - hop * 0.3)
                .position(x: 76, y: 113)

            CMAsset(.pipOnTheRoad, width: 76, height: 92)
                .rotationEffect(.degrees(-3 + hop * 6), anchor: .bottom)
                .offset(y: -hop * 7)
                .position(x: 76, y: 68)

            CMAsset(.compactCar, width: 132, height: 108)
                .rotationEffect(.degrees(bounce * 1.2), anchor: .bottom)
                .offset(y: bounce * 1.6)
                .position(x: 164, y: 67)

            // Two little wing strokes echo Pip without competing with the mascot.
            JourneyBird(lift: sin(time * .pi * 2 / 0.8) * 3)
                .stroke(Theme.Colour.action.opacity(0.75), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 16, height: 9)
                .offset(y: sin(time * .pi * 2 / 2.4) * 3)
                .position(x: 206, y: 17)

            JourneyBird(lift: sin(time * .pi * 2 / 0.8 + 1) * 2)
                .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 12, height: 7)
                .offset(y: sin(time * .pi * 2 / 2.4 + 1) * 2)
                .position(x: 229, y: 28)
        }
        .accessibilityHidden(true)
    }

    private var road: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.07))
                .frame(height: 17)

            HStack(spacing: 17) {
                ForEach(0..<11) { _ in
                    Capsule()
                        .fill(Theme.Colour.action.opacity(0.75))
                        .frame(width: 15, height: 2)
                }
            }
            // One complete dash interval makes every wrap visually seamless.
            .offset(x: CGFloat(time.truncatingRemainder(dividingBy: 0.6) / 0.6) * 32)
        }
        .frame(width: 244, height: 17)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.18),
                    .init(color: .white, location: 0.82),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private var speedLines: some View {
        ForEach(0..<3) { index in
            let phase = (time / 0.9 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            Capsule()
                .fill(index == 1 ? Theme.Colour.action : Color.white)
                .frame(width: index == 1 ? 17 : 11, height: 2)
                .opacity(sin(phase * .pi) * 0.45)
                .position(x: 225 + phase * 28, y: 63 + Double(index) * 13)
        }
    }
}

private struct JourneyBird: Shape {
    var lift: Double

    func path(in rect: CGRect) -> Path {
        Path { path in
            let center = CGPoint(x: rect.midX, y: rect.maxY)
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + lift))
            path.addQuadCurve(to: center, control: CGPoint(x: rect.midX * 0.7, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + lift),
                control: CGPoint(x: rect.midX * 1.3, y: rect.minY)
            )
        }
    }
}
//
//#Preview("Launch loader") {
//    LoadingView()
//}
//
//#Preview("Reduced motion") {
//    LoadingView()
//        .environment(\.cmReduceMotion, true)
//}
