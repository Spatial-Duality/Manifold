import SwiftUI
import ManifoldKit

struct MenuBarView: View {
    @EnvironmentObject var store: ManifoldStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status
            HStack {
                Circle()
                    .fill(store.isConnected ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                if let agent = store.connectedAgent {
                    Text("\(agent) connected")
                        .font(.caption.weight(.medium))
                } else {
                    Text("No agents connected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Quick stats
            HStack(spacing: 8) {
                Text("\(store.approvedSources.count) sources")
                Text("\(store.activityEntries.count) events")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider()

            // Recent activity
            if store.activityEntries.isEmpty {
                Text("No recent activity")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(12)
            } else {
                ForEach(store.activityEntries.prefix(5)) { entry in
                    HStack {
                        Text(entry.action.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                        if let path = entry.filePath {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
            }

            Divider()

            Button("Open Manifold") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Button("Quit Manifold") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .frame(width: 260)
    }
}
