import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var appState: AppState
    @State private var expandedEntry: UUID?
    @State private var filterAgent: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let runID = appState.currentRunID {
                        Text("Access run \(runID.prefix(12)) — active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No active access run")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Access run controls
                HStack(spacing: 8) {
                    if appState.hasActiveRun {
                        Button("Refresh") {
                            appState.refreshAccess()
                        }
                        .controlSize(.small)

                        Button("End Access") {
                            appState.endAccess()
                        }
                        .controlSize(.small)
                        .tint(.red)
                    } else {
                        Button("Grant to Claude") {
                            appState.grantAccess()
                        }
                        .controlSize(.small)
                        .tint(.blue)
                        .disabled(appState.sources.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Timeline
            if filteredEntries.isEmpty {
                EmptyActivityView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredEntries) { entry in
                            ActivityRow(
                                entry: entry,
                                isExpanded: expandedEntry == entry.id,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedEntry = expandedEntry == entry.id ? nil : entry.id
                                    }
                                },
                                onRestore: {
                                    appState.restoreEntry(entry)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var filteredEntries: [ActivityEntry] {
        guard let agent = filterAgent else { return appState.activityEntries }
        return appState.activityEntries.filter { $0.agent == agent }
    }
}

struct ActivityRow: View {
    let entry: ActivityEntry
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRestore: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 0) {
                // Timestamp
                Text(entry.timeString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 55, alignment: .leading)

                // Agent badge
                Text(entry.agent)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(agentColor)
                    .frame(width: 60, alignment: .leading)

                // Action + file
                HStack(spacing: 4) {
                    if entry.isSensitive {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }

                    Text(entry.changeType.rawValue)
                        .font(.system(size: 12))

                    Text(entry.filePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Restore button (on hover)
                if isHovered {
                    Button(action: onRestore) {
                        Text(restoreLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(entry.isSensitive ? .red : .blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { isHovered = $0 }

            // Expanded diff
            if isExpanded {
                DiffView(beforeHash: entry.beforeHash, afterHash: entry.afterHash)
                    .padding(.leading, 65)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
            }
        }
        .background {
            if entry.isSensitive {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.yellow.opacity(0.04))
            } else if isHovered {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.03))
            }
        }
    }

    private var agentColor: Color {
        switch entry.agent.lowercased() {
        case "cowork": return .blue
        case "codex": return .purple
        case "manifold": return .gray
        default: return .primary
        }
    }

    private var restoreLabel: String {
        switch entry.changeType {
        case .created: return "Remove"
        case .modified: return "Restore"
        case .deleted: return "Recover"
        case .restored: return "Undo"
        }
    }
}

struct DiffView: View {
    let beforeHash: String?
    let afterHash: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Placeholder diff — will wire to real snapshot data
            if beforeHash != nil && afterHash != nil {
                Group {
                    DiffLine(prefix: " ", text: "async function handleRequest(req: Request) {", type: .context)
                    DiffLine(prefix: "-", text: "  const token = req.headers.get('auth')", type: .removal)
                    DiffLine(prefix: "+", text: "  const token = req.headers.get('authorization')", type: .addition)
                    DiffLine(prefix: "+", text: "  if (!token) return new Response('Unauthorized', { status: 401 })", type: .addition)
                    DiffLine(prefix: " ", text: "  // ...", type: .context)
                }
            } else {
                Text("No diff available")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

struct DiffLine: View {
    let prefix: String
    let text: String
    let type: DiffLineType

    enum DiffLineType {
        case context, addition, removal
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(prefix)
                .frame(width: 14, alignment: .center)
            Text(text)
            Spacer()
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(color)
        .lineLimit(1)
        .padding(.vertical, 1)
    }

    private var color: Color {
        switch type {
        case .context: return .secondary.opacity(0.6)
        case .addition: return .green
        case .removal: return .red
        }
    }
}

struct EmptyActivityView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No activity yet")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Start an agent session to see file modifications here")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
