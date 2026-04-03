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
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity")
                        .font(.title2.weight(.semibold))

                    if let runID = appState.currentRunID {
                        Label("Access run \(runID.prefix(12))", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
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
                        Button("Refresh") { showRefreshConfirm = true }
                            .controlSize(.small)
                            .disabled(appState.isGranting)

                        Button("End Access", role: .destructive) {
                            Task { await appState.endAccess() }
                        }
                        .controlSize(.small)
                        .disabled(appState.isGranting)
                    } else {
                        Button("Grant to Claude") {
                            if hasSeenGuardrail {
                                Task { await appState.grantAccess() }
                            } else {
                                showGuardrail = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(appState.sources.isEmpty || appState.isGranting)
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
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            // Mode picker
            HStack {
                Picker("", selection: $viewMode) {
                    Text("Live").tag(0)
                    Text("Session Replay").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                if viewMode == 1 {
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
                            Text("\(run.runID.prefix(12)) \u{00B7} \(run.startedAt.prefix(10))").tag(run.runID)
                        }
                    }
                    .frame(width: 220)
                    .onAppear { Task { await appState.loadCompletedRuns() } }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // Content
            let displayEntries = viewMode == 0 ? filteredEntries : replayEntries
            if displayEntries.isEmpty {
                ContentUnavailableView {
                    Label("No Activity", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Start an access run to see file modifications here")
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(displayEntries) { entry in
                        ActivityRow(
                            entry: entry,
                            isExpanded: expandedEntry == entry.id,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedEntry == entry.id {
                                        expandedEntry = nil
                                    } else {
                                        expandedEntry = entry.id
                                        Task {
                                            let lines = await appState.loadDiff(for: entry)
                                            diffLines[entry.id] = lines
                                        }
                                    }
                                }
                            },
                            onRestore: { Task { await appState.restoreEntry(entry) } },
                            diffLines: diffLines[entry.id] ?? []
                        )
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var filteredEntries: [ActivityEntry] {
        appState.activityEntries
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let entry: ActivityEntry
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRestore: () -> Void
    let diffLines: [ManifoldKit.DiffLine]

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(entry.timeString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .frame(width: 55, alignment: .leading)

                Text(entry.agent)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(agentColor)
                    .frame(width: 60, alignment: .leading)

                HStack(spacing: 4) {
                    if entry.isSensitive {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .imageScale(.small)
                            .foregroundStyle(.yellow)
                    }
                    Text(entry.changeType.rawValue)
                        .font(.subheadline)
                    Text(entry.filePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if isHovered {
                    Button(restoreLabel) { onRestore() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(entry.isSensitive ? .red : .accentColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { isHovered = $0 }

            if isExpanded {
                DiffView(lines: diffLines)
                    .padding(.leading, 65)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
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

    init(lines: [ManifoldKit.DiffLine] = []) {
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty {
                Text("No diff available")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(lines) { line in
                    DiffLineView(line: line)
                }
            }
        }
        .padding(10)
        .background(.quinary, in: .rect(cornerRadius: 6))
    }
}

struct DiffLineView: View {
    let line: ManifoldKit.DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(prefix)
                .frame(width: 14, alignment: .center)
            Text(line.text)
            Spacer()
        }
        .font(.caption.monospaced())
        .foregroundStyle(color)
        .lineLimit(1)
        .padding(.vertical, 1)
    }

    private var prefix: String {
        switch line.type {
        case .context: return " "
        case .addition: return "+"
        case .removal: return "-"
        }
    }

    private var color: Color {
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
