import SwiftUI
import UserNotifications

@main
struct ManifoldApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Request notification permission for sensitive file alerts
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        // Menu bar presence
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
        }

        // Main window
        WindowGroup {
            if appState.hasCompletedOnboarding {
                ContentView()
                    .environmentObject(appState)
                    .frame(minWidth: 700, minHeight: 500)
            } else {
                OnboardingView()
                    .environmentObject(appState)
                    .frame(width: 500, height: 400)
            }
        }
        .defaultSize(width: 900, height: 600)
    }
}
