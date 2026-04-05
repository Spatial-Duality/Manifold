import SwiftUI

struct SidebarView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        List {
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
        }
        .listStyle(.sidebar)
        .navigationTitle("Manifold")
        .safeAreaInset(edge: .bottom) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
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
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
