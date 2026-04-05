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
        .listStyle(.inset)
        .navigationTitle("Dashboard")
        .navigationSubtitle(store.isConnected ? "Protected" : "Idle")
        .task { await store.loadSummary() }
    }
}
