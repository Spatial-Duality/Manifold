import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: ManifoldStore

    var body: some View {
        List(selection: $store.selectedSection) {
            ForEach(SidebarSection.allCases) { section in
                Label(section.label, systemImage: section.icon)
                    .tag(section as SidebarSection?)
                    .badge(badgeCount(for: section))
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Manifold")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Circle()
                    .fill(store.isConnected ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(store.isConnected ? (store.connectedAgent ?? "Connected") : "No agents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func badgeCount(for section: SidebarSection) -> Int {
        switch section {
        case .sources: return store.approvedSources.count
        case .versions: return store.allTrackedFiles.count
        default: return 0
        }
    }
}
