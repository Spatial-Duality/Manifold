import SwiftUI
import ManifoldKit

struct SourceDetailView: View {
    @EnvironmentObject var store: ManifoldStore
    let workspace: WorkspaceRecord

    @State private var activeRun: RunRecord?
    @State private var runs: [RunRecord] = []
    @State private var selectedAgent = "cowork"
    @State private var selectedDuration: TimeInterval = 0

    private let durations: [(String, TimeInterval)] = [
        ("Unlimited", 0), ("1 hour", 3600), ("4 hours", 14400), ("8 hours", 28800),
    ]

    var body: some View {
        List {
            // Path
            Section {
                LabeledContent("Path") {
                    Text(workspace.rootPath)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Status") {
                    StatusBadge(
                        text: workspace.status.uppercased(),
                        color: workspace.status == "active" ? .green : .gray
                    )
                }
                LabeledContent("Agent") { AgentBadge(agent: workspace.agent) }
                LabeledContent("Added") { Text(workspace.createdAt.prefix(10)) }
            }

            // Access Control
            Section("Access") {
                if let run = activeRun {
                    LabeledContent("Current run") {
                        Text(run.runID).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    LabeledContent("Started") { TimeLabel(iso8601: run.startedAt) }
                    Button("End Access", role: .destructive) {
                        Task { await store.endRun(runID: run.runID); await loadData() }
                    }
                } else {
                    Picker("Agent", selection: $selectedAgent) {
                        Text("Cowork").tag("cowork")
                        Text("Codex").tag("codex")
                    }
                    Picker("Duration", selection: $selectedDuration) {
                        ForEach(durations, id: \.1) { label, val in
                            Text(label).tag(val)
                        }
                    }
                    Button("Grant Access") {
                        Task {
                            if selectedDuration > 0 {
                                await store.startTimeLimitedRun(workspaceID: workspace.workspaceID, agent: selectedAgent, duration: selectedDuration)
                            } else {
                                await store.startRun(workspaceID: workspace.workspaceID, agent: selectedAgent)
                            }
                            await loadData()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // Run History
            Section("Run History") {
                if runs.isEmpty {
                    Text("No runs yet").foregroundStyle(.tertiary)
                } else {
                    ForEach(runs, id: \.runID) { run in
                        HStack {
                            AgentBadge(agent: run.agent)
                            Spacer()
                            TimeLabel(iso8601: run.startedAt)
                            StatusBadge(
                                text: run.isActive ? "ACTIVE" : "CLOSED",
                                color: run.isActive ? .green : .gray
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle(URL(fileURLWithPath: workspace.rootPath).lastPathComponent)
        .navigationSubtitle(workspace.status == "active" ? "Access granted" : "Idle")
        .task { await loadData() }
    }

    private func loadData() async {
        activeRun = await store.activeRunForWorkspace(workspace.workspaceID)
        runs = await store.runsForWorkspace(workspace.workspaceID)
    }
}
