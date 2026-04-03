import SwiftUI
import UserNotifications

@main
struct ManifoldApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main window — always openable
        WindowGroup(id: "main") {
            if appState.hasCompletedOnboarding {
                ContentView()
                    .environmentObject(appState)
                    .frame(minWidth: 700, minHeight: 500)
            } else {
                OnboardingView()
                    .environmentObject(appState)
                    .frame(minWidth: 500, minHeight: 400)
            }
        }
        .defaultSize(width: 900, height: 600)

        // Menu bar — always visible
        MenuBarExtra {
            MenuBarView(openMainWindow: {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            })
            .environmentObject(appState)
        } label: {
            Label("Manifold", systemImage: appState.menuBarIcon)
        }
    }
}
