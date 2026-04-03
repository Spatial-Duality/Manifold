import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    let openMainWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status + open button
            HStack {
                statusIndicator
                Spacer()
                Button("Open Manifold") {
                    openMainWindow()
                }
                .font(.callout)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Recent activity
            if appState.activityEntries.isEmpty {
                Text("No recent activity")
                    .font(.callout)
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

            // Quick actions
            Button {
                openMainWindow()
                appState.selectedSidebar = .activity
            } label: {
                Label("View Activity", systemImage: "clock.arrow.circlepath")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Button {
                openMainWindow()
                appState.selectedSidebar = .files
            } label: {
                Label("Manage Sources", systemImage: "folder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            Button("Quit Manifold") {
                NSApplication.shared.terminate(nil)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .active(let agent, _):
                Text("\(agent) access granted")
                    .font(.caption.weight(.medium))
            case .warning(let message):
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.yellow)
            }
        }
    }

    private var statusColor: Color {
        switch appState.agentStatus {
        case .inactive: return .gray
        case .active: return .accentColor
        case .warning: return .yellow
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
                if entry.isSensitive {
                    Label(entry.fileName, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .lineLimit(1)
                        .symbolRenderingMode(.multicolor)
                } else {
                    Text(entry.fileName)
                        .font(.callout)
                        .lineLimit(1)
                }
                Text("\(entry.changeType.rawValue) \(entry.timeString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isHovered {
                Button("Restore", action: onRestore)
                    .font(.caption2)
                    .foregroundStyle(entry.isSensitive ? Color.red : Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
