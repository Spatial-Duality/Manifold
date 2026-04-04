import SwiftUI

@main
struct ManifoldApp: App {
    @StateObject private var store = ManifoldStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .environmentObject(store)
                .frame(minWidth: 780, minHeight: 520)
        }
        .defaultSize(width: 960, height: 640)
        .windowStyle(.automatic)

        MenuBarExtra("Manifold", systemImage: store.menuBarIcon) {
            if store.isConnected, let agent = store.connectedAgent {
                Text("\(agent) connected")
            } else {
                Text("No agents connected")
            }
            Divider()
            Text("\(store.approvedSources.count) sources")
            Divider()
            Button("Open Manifold") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("o")
            Button("Quit Manifold") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SetupView()
                .environmentObject(store)
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}
