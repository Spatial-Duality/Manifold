import SwiftUI
import ManifoldKit

struct SourceDetailView: View {
    @EnvironmentObject var store: ManifoldStore
    let workspace: WorkspaceRecord

    @State private var activeRun: RunRecord?
    @State private var runs: [RunRecord] = []
    @State private var selectedAgent = "cowork"
    @State private var selectedDuration: TimeInterval = 0 // 0 = unlimited

    private let agents = ["cowork", "codex"]
    private let durations: [(String, TimeInterval)] = [
        ("Unlimited", 0),
        ("1 hour", 3600),
        ("4 hours", 14400),
        ("8 hours", 28800),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.rootPath)
                        .font(.headline.monospaced())
                        .textSelection(.enabled)
                    HStack(spacing: 12) {
                        StatusBadge(
                            text: workspace.status.uppercased(),
                            color: workspace.status == "active" ? .green : .gray
                        )
                        Text("Created \(workspace.createdAt.prefix(10))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal)

                Divider()

                // Access Control
                if let run = activeRun {
                    // Active run
                    GroupBox("Active Access") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                AgentBadge(agent: run.agent)
                                Spacer()
                                TimeLabel(iso8601: run.startedAt)
                            }
                            Text("Run: \(run.runID)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                            Button("End Access", role: .destructive) {
                                Task {
                                    await store.endRun(runID: run.runID)
                                    await loadData()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(4)
                    }
                    .padding(.horizontal)
                } else {
                    // Grant access
                    GroupBox("Grant Access") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Agent", selection: $selectedAgent) {
                                ForEach(agents, id: \.self) { Text($0.capitalized) }
                            }
                            .pickerStyle(.segmented)

                            Picker("Duration", selection: $selectedDuration) {
                                ForEach(durations, id: \.1) { label, val in
                                    Text(label).tag(val)
                                }
                            }

                            Button("Grant Access") {
                                Task {
                                    if selectedDuration > 0 {
                                        await store.startTimeLimitedRun(
                                            workspaceID: workspace.workspaceID,
                                            agent: selectedAgent,
                                            duration: selectedDuration
                                        )
                                    } else {
                                        await store.startRun(
                                            workspaceID: workspace.workspaceID,
                                            agent: selectedAgent
                                        )
                                    }
                                    await loadData()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(4)
                    }
                    .padding(.horizontal)
                }

                Divider()

                // Run History
                GroupBox("Run History") {
                    if runs.isEmpty {
                        Text("No runs yet")
                            .font(.caption).foregroundStyle(.tertiary)
                            .padding(4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(runs, id: \.runID) { run in
                                HStack {
                                    AgentBadge(agent: run.agent)
                                    TimeLabel(iso8601: run.startedAt)
                                    Spacer()
                                    StatusBadge(
                                        text: run.status.uppercased(),
                                        color: run.isActive ? .green : .gray
                                    )
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                                if run.runID != runs.last?.runID {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(URL(fileURLWithPath: workspace.rootPath).lastPathComponent)
        .task { await loadData() }
    }

    private func loadData() async {
        activeRun = await store.activeRunForWorkspace(workspace.workspaceID)
        runs = await store.runsForWorkspace(workspace.workspaceID)
    }
}
