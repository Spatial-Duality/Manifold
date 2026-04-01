import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            HStack {
                statusIndicator
                Spacer()
                Button("Open Manifold") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title == "Manifold" || $0.isKeyWindow }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Recent activity
            if appState.activityEntries.isEmpty {
                Text("No recent activity")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(12)
            } else {
                ForEach(appState.activityEntries.prefix(5)) { entry in
                    MenuBarActivityRow(entry: entry) {
                        Task { await appState.restoreEntry(entry) }
                    }
                }
            }

            Divider()

            Button("Quit Manifold") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .keyboardShortcut("q")
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            switch appState.agentStatus {
            case .inactive:
                Text("No active access")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .active(let agent, _):
                Text("\(agent) access granted")
                    .font(.system(size: 11, weight: .medium))
            case .warning(let message):
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var statusColor: Color {
        switch appState.agentStatus {
        case .inactive: return .gray
        case .active: return .blue
        case .warning: return .orange
        }
    }
}

struct MenuBarActivityRow: View {
    let entry: ActivityEntry
    let onRestore: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if entry.isSensitive {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                    Text(entry.fileName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                Text("\(entry.changeType.rawValue) \(entry.timeString)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isHovered {
                Button("Restore", action: onRestore)
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(entry.isSensitive ? .red : .blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
