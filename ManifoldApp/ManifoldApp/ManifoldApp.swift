import SwiftUI

@main
struct ManifoldApp: App {
    @StateObject private var store = ManifoldStore()

    var body: some Scene {
        WindowGroup(id: "dashboard") {
            DashboardView()
                .environmentObject(store)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 800, height: 600)
        .windowStyle(.automatic)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            Label("Manifold", systemImage: store.connectionIcon)
        }
    }
}
