import SwiftUI

@main
struct ManifoldApp: App {
    @StateObject private var appState = AppState()

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
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 900, height: 600)
    }
}
