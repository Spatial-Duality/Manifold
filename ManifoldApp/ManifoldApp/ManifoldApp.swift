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
            // Connection status
            if store.isConnected, let agent = store.connectedAgent {
                Text("\(agent) connected")
            } else {
                Text("No agents connected")
            }

            Divider()

            // Quick stats
            Text("\(store.approvedSources.count) sources | \(store.activityEntries.count) events")

            Divider()

            // Recent activity
            if store.activityEntries.isEmpty {
                Text("No recent activity")
            } else {
                ForEach(store.activityEntries.prefix(5)) { entry in
                    let label = entry.action.replacingOccurrences(of: "_", with: " ")
                    let detail = entry.filePath.map { " — " + URL(fileURLWithPath: $0).lastPathComponent } ?? ""
                    Text(label + detail)
                }
            }

            Divider()

            Button("Open Manifold") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "Manifold" || $0.isKeyWindow }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    // Open a new window
                    NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)
                }
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
