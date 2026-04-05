import SwiftUI
import ManifoldKit

struct DashboardView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        List {
            ConnectionSection()
            SourcesSection()
            EmailSection()
            RecentActivitySection()
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("Dashboard")
        .navigationSubtitle(store.isConnected ? "Protected" : "Idle")
        .toolbar {
            Button("Add Source", systemImage: "folder.badge.plus") {
                store.addSourceFromPicker()
            }
        }
        .task { await store.loadSummary() }
    }
}
