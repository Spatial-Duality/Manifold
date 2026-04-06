import SwiftUI

struct SidebarView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: Spacing.tight) {
            VStack(spacing: Spacing.tight + 2) {
                SidebarButton(
                    label: "Home",
                    icon: "house",
                    item: .home,
                    selected: store.selectedSidebarItem
                ) { store.selectedSidebarItem = .home }

                SidebarButton(
                    label: "Files",
                    icon: "doc.text.magnifyingglass",
                    item: .files,
                    selected: store.selectedSidebarItem
                ) { store.selectedSidebarItem = .files }

                SidebarButton(
                    label: "Emails",
                    icon: "envelope.badge.shield.half.filled",
                    item: .emails,
                    selected: store.selectedSidebarItem
                ) { store.selectedSidebarItem = .emails }

                SidebarButton(
                    label: "History",
                    icon: "clock.arrow.circlepath",
                    item: .history,
                    selected: store.selectedSidebarItem
                ) { store.selectedSidebarItem = .history }

                SidebarButton(
                    label: "Sources",
                    icon: "folder.badge.gearshape",
                    item: .sources,
                    selected: store.selectedSidebarItem
                ) { store.selectedSidebarItem = .sources }
            }

            Spacer()

            Divider()
                .padding(.horizontal, Spacing.standard)

            // Connection status
            HStack(spacing: Spacing.standard) {
                ColorIndicator(color: store.isConnected ? .green : .gray)
                    .accessibilityLabel(store.isConnected ? "Connected" : "Disconnected")
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.isConnected ? (store.connectedAgent ?? "Connected") : "No agents")
                        .font(.caption.weight(store.isConnected ? .medium : .regular))
                    if store.isConnected {
                        Text("Monitoring")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if !store.mcpInstalled {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow).imageScale(.small)
                        .accessibilityLabel("MCP server not installed")
                }
            }
            .padding(.horizontal, Spacing.section)
            .padding(.vertical, Spacing.standard)
        }
        .padding(.horizontal, Spacing.standard)
        .padding(.top, Spacing.standard)
        .navigationTitle("Manifold")
    }
}

private struct SidebarButton: View {
    let label: String
    let icon: String
    let item: SidebarItem
    let selected: SidebarItem?
    let action: () -> Void

    private var isSelected: Bool { selected == item }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.standard) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 18)
                    .accessibilityHidden(true)

                Label(label, systemImage: icon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, Spacing.standard)
        .padding(.trailing, Spacing.standard)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.standard))
    }
}
