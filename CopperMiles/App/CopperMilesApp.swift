import SwiftUI
import UIKit

@main
struct CopperMilesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment()
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
        }
    }
}

/// Dresses the UIKit chrome SwiftUI still draws for us.
///
/// Navigation and tab bars are the two places the system's own colours would show
/// through on a cream background, so they are set once at launch rather than patched
/// screen by screen.
enum SystemAppearance {
    static func apply() {
        let background = UIColor(Theme.Colour.background)
        let surface = UIColor(Theme.Colour.surface)
        let primaryText = UIColor(Theme.Colour.primaryText)
        let secondaryText = UIColor(Theme.Colour.secondaryText)
        let accent = UIColor(Theme.Colour.accent)
        
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = background
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: primaryText]
        navigation.largeTitleTextAttributes = [.foregroundColor: primaryText]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = surface
        tabBar.stackedLayoutAppearance.normal.iconColor = secondaryText
        tabBar.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: secondaryText]
        tabBar.stackedLayoutAppearance.selected.iconColor = accent
        tabBar.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: primaryText]
        UITabBar.appearance().standardAppearance = tabBar
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabBar
        }
        
        // Below iOS 16 a `TextEditor` has no way to clear its own background from
        // SwiftUI, so the shared appearance carries the card colour for it.
        UITextView.appearance().backgroundColor = .clear
    }
}
