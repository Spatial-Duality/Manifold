import SwiftUI

struct SidebarView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 2) {
            SidebarButton(
                label: "Dashboard",
                icon: "gauge.open.with.lines.needle.33percent",
                item: .dashboard,
                selected: store.selectedSidebarItem
            ) { store.selectedSidebarItem = .dashboard }

            SidebarButton(
                label: "Files",
                icon: "doc.text.magnifyingglass",
                item: .files,
                selected: store.selectedSidebarItem
            ) { store.selectedSidebarItem = .files }

            SidebarButton(
                label: "Activity",
                icon: "waveform.path.ecg",
                item: .activity,
                selected: store.selectedSidebarItem
            ) { store.selectedSidebarItem = .activity }

            SidebarButton(
                label: "Versions",
                icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                item: .versions,
                selected: store.selectedSidebarItem
            ) { store.selectedSidebarItem = .versions }

            Spacer()

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(store.isConnected ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
                Text(store.isConnected ? (store.connectedAgent ?? "Connected") : "No agents")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.mcpInstalled {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow).imageScale(.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .navigationTitle("Manifold")
    }
}

struct SidebarButton: View {
    let label: String
    let icon: String
    let item: SidebarItem
    let selected: SidebarItem?
    let action: () -> Void

    private var isSelected: Bool { selected == item }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
