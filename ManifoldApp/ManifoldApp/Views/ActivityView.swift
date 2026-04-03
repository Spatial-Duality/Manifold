import SwiftUI
import ManifoldKit

struct ActivityView: View {
    @EnvironmentObject var appState: AppState
    @State private var expandedEntry: UUID?
    @State private var showGuardrail = false
    @State private var showRefreshConfirm = false
    @State private var diffLines: [UUID: [ManifoldKit.DiffLine]] = [:]
    @AppStorage("hasSeenGuardrail") private var hasSeenGuardrail = false
    @State private var viewMode = 0
    @State private var selectedReplayRun: String?
    @State private var replayEntries: [ActivityEntry] = []

    var body: some View {
        NavigationStack {
            Group {
                let displayEntries = viewMode == 0 ? appState.activityEntries : replayEntries

                if displayEntries.isEmpty {
                    ContentUnavailableView(
                        "No Activity",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Grant access to start tracking file modifications.")
                    )
                } else {
                    List {
                        ForEach(displayEntries) { entry in
                            ActivityRow(
                                entry: entry,
                                isExpanded: expandedEntry == entry.id,
                                onToggle: {
                                    withAnimation {
                                        if expandedEntry == entry.id {
                                            expandedEntry = nil
                                        } else {
                                            expandedEntry = entry.id
                                            Task {
                                                diffLines[entry.id] = await appState.loadDiff(for: entry)
                                            }
                                        }
                                    }
                                },
                                onRestore: { Task { await appState.restoreEntry(entry) } },
                                diffLines: diffLines[entry.id] ?? []
                            )
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                // Mode picker in center
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $viewMode) {
                        Text("Live").tag(0)
                        Text("Replay").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                // Replay run picker
                if viewMode == 1 {
                    ToolbarItem(placement: .automatic) {
                        Picker("Run", selection: Binding(
                            get: { selectedReplayRun ?? "" },
                            set: {
                                selectedReplayRun = $0.isEmpty ? nil : $0
                                if let runID = selectedReplayRun {
                                    Task { replayEntries = await appState.loadSessionReplay(runID: runID) }
                                }
                            }
                        )) {
                            Text("Select run...").tag("")
                            ForEach(appState.completedRuns) { run in
                                Text("\(run.runID.prefix(12))").tag(run.runID)
                            }
                        }
                        .onAppear { Task { await appState.loadCompletedRuns() } }
                    }
                }

                // Primary action: Grant or End
                if appState.hasActiveRun {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("End Access", systemImage: "stop.circle") {
                            Task { await appState.endAccess() }
                        }
                        .disabled(appState.isGranting)
                    }

                    ToolbarItem(placement: .automatic) {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            showRefreshConfirm = true
                        }
                        .disabled(appState.isGranting)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Grant to Claude", systemImage: "play.circle") {
                            if hasSeenGuardrail {
                                Task { await appState.grantAccess() }
                            } else {
                                showGuardrail = true
                            }
                        }
                        .disabled(appState.sources.isEmpty || appState.isGranting)
                    }
                }
            }
            .sheet(isPresented: $showGuardrail) {
                GuardrailNotice {
                    hasSeenGuardrail = true
                    showGuardrail = false
                    Task { await appState.grantAccess() }
                }
            }
            .confirmationDialog("Refresh workspace?", isPresented: $showRefreshConfirm, titleVisibility: .visible) {
                Button("Refresh and Continue") { Task { await appState.refreshAccess() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This re-syncs from your source files. Unpromoted changes are preserved in version history.")
            }
        }
    }
}

// MARK: - Activity Row (clean, no glass on content)

struct ActivityRow: View {
    let entry: ActivityEntry
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRestore: () -> Void
    let diffLines: [ManifoldKit.DiffLine]

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.timeString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .frame(width: 55, alignment: .leading)

                Text(entry.agent)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(agentColor)

                if entry.isSensitive {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .imageScale(.small)
                        .foregroundStyle(.yellow)
                }

                Text(entry.changeType.rawValue)
                    .font(.callout)

                Text(entry.filePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { isHovered = $0 }

            if isExpanded {
                DiffView(lines: diffLines)
                    .padding(.leading, 55)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(restoreLabel) { onRestore() }
                .tint(entry.isSensitive ? .red : .accentColor)
        }
    }

    private var agentColor: Color {
        switch entry.agent.lowercased() {
        case "cowork": return .blue
        case "codex": return .purple
        default: return .secondary
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

// MARK: - Diff View

struct DiffView: View {
    let lines: [ManifoldKit.DiffLine]

    var body: some View {
        if lines.isEmpty {
            Text("No diff available")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    HStack(spacing: 0) {
                        Text(prefix(for: line))
                            .frame(width: 14, alignment: .center)
                        Text(line.text)
                        Spacer()
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(color(for: line))
                    .lineLimit(1)
                    .padding(.vertical, 1)
                }
            }
            .padding(8)
            .background(.quinary, in: .rect(cornerRadius: 6))
        }
    }

    private func prefix(for line: ManifoldKit.DiffLine) -> String {
        switch line.type {
        case .context: return " "
        case .addition: return "+"
        case .removal: return "-"
        }
    }

    private func color(for line: ManifoldKit.DiffLine) -> Color {
        switch line.type {
        case .context: return .secondary
        case .addition: return .green
        case .removal: return .red
        }
    }
}

#Preview("Activity") {
    ActivityView()
        .environmentObject(AppState())
        .frame(width: 600, height: 500)
}
