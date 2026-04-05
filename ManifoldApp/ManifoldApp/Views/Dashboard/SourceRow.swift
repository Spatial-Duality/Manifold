import SwiftUI
import AppKit
import ManifoldKit

struct SourceRow: View {
    @Environment(ManifoldStore.self) var store
    let workspace: WorkspaceRecord

    @State private var isExpanded = false
    @State private var activeRun: RunRecord?
    @State private var runs: [RunRecord] = []
    @State private var fileCount: Int = 0
    @State private var confirmRemove = false

    private var folderName: String { URL(fileURLWithPath: workspace.rootPath).lastPathComponent }
    private var shortenedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return workspace.rootPath.hasPrefix(home) ? "~" + workspace.rootPath.dropFirst(home.count) : workspace.rootPath
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Metadata
            LabeledContent("Path") {
                Text(shortenedPath).font(.caption.monospaced()).textSelection(.enabled)
            }
            LabeledContent("Added") { TimeLabel(iso8601: workspace.createdAt) }
            LabeledContent("Files") { Text("\(fileCount)").monospacedDigit() }

            // Access controls
            if let run = activeRun {
                HStack {
                    AgentBadge(agent: run.agent)
                    Spacer()
                    TimeLabel(iso8601: run.startedAt)
                    Button("End Access", role: .destructive) {
                        Task { await store.endRun(runID: run.runID); await loadData() }
                    }.controlSize(.small)
                }
            }

            // File tree
            Section("Contents") {
                FileTreeView(rootPath: workspace.rootPath)
            }

            // Run history
            if !runs.isEmpty {
                Section("Run History") {
                    ForEach(runs.prefix(5), id: \.runID) { run in
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
        } label: {
            HStack(spacing: 8) {
                Image(systemName: workspace.status == "active" ? "folder.fill" : "folder")
                    .foregroundStyle(workspace.status == "active" ? .blue : .secondary)
                Text(folderName).font(.body.weight(.medium))
                Spacer()
                if workspace.status == "active" {
                    StatusBadge(text: "Active", color: .green)
                }
                Text("\(fileCount) files")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(workspace.rootPath, inFileViewerRootedAtPath: "")
            }
            Divider()
            if workspace.status == "archived" {
                Button("Resume Access") {
                    Task { await store.resumeSource(workspaceID: workspace.workspaceID) }
                }
            } else {
                Button("Pause Access") {
                    Task { await store.pauseSource(workspaceID: workspace.workspaceID) }
                }
            }
            Divider()
            Button("Remove Source...", role: .destructive) { confirmRemove = true }
        }
        .alert("Remove Source?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { store.removeSource(path: workspace.rootPath) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("File history for \"\(folderName)\" will remain. You can re-add this folder later.")
        }
        .task { await loadData() }
    }

    private func loadData() async {
        activeRun = await store.activeRunForWorkspace(workspace.workspaceID)
        runs = await store.runsForWorkspace(workspace.workspaceID)
        // Count files
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: URL(fileURLWithPath: workspace.rootPath),
                                           includingPropertiesForKeys: [.isRegularFileKey],
                                           options: [.skipsHiddenFiles]) {
            var count = 0
            while enumerator.nextObject() != nil { count += 1 }
            fileCount = count
        }
    }
}
