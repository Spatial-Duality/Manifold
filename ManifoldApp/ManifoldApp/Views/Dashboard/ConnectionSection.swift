import SwiftUI

struct ConnectionSection: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Circle()
                    .fill(store.isConnected ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(store.isConnected ? "Connected" : "Disconnected")
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isConnected ? "\(store.connectedAgent ?? "Agent") connected" : "No agents connected")
                        .font(.body.weight(.medium))
                    if store.isConnected {
                        Text("Monitoring file access")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if !store.mcpInstalled {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        .accessibilityLabel("Warning")
                    Text("MCP server not installed").foregroundStyle(.secondary)
                    Spacer()
                    Button("Install") { store.installMCP() }.controlSize(.small)
                }
            }
        } header: {
            Text("Connection")
        }
    }
}
