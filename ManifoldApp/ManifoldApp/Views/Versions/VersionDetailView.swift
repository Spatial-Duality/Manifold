import SwiftUI

struct VersionDetailView: View {
    @Environment(ManifoldStore.self) var store
    let filePath: String

    @State private var snapshots: [SnapshotRecord] = []
    @State private var selectedSnapshot: SnapshotRecord?
    @State private var diffLines: [DiffLine] = []
    @State private var loadingDiff = false
    @State private var restoredSnapshotID: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90").foregroundStyle(.secondary)
                Text(filePath).font(.headline.monospaced()).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(snapshots.count) versions").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.edge).padding(.vertical, Spacing.section)
            Divider()

            if snapshots.isEmpty {
                ContentUnavailableView("No Versions", systemImage: "clock",
                    description: Text("No snapshots recorded for this file."))
            } else {
                HSplitView {
                    snapshotList.frame(minWidth: 200)
                    diffPanel.frame(minWidth: 250)
                }
            }
        }
        .task { await loadHistory() }
    }

    private var snapshotList: some View {
        List(snapshots, id: \.id, selection: $selectedSnapshot) { snapshot in
            SnapshotRow(snapshot: snapshot, isRestored: restoredSnapshotID == snapshot.id)
                .tag(snapshot)
        }
        .listStyle(.inset)
        .onChange(of: selectedSnapshot) { _, newValue in
            if let snap = newValue { Task { await loadDiff(for: snap) } }
        }
    }

    private var diffPanel: some View {
        VStack(spacing: 0) {
            if let snap = selectedSnapshot {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        TimeLabel(iso8601: snap.timestamp)
                        Text(snap.source == "agent" ? "Changed by AI agent" : "Source: \(snap.source)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if snap.afterHash != nil && !snap.isDelete {
                        Button("Restore") {
                            Task {
                                restoredSnapshotID = snap.id
                                _ = await store.restoreFile(snapshotID: snap.id, filePath: filePath)
                                try? await Task.sleep(for: .seconds(3))
                                restoredSnapshotID = nil
                            }
                        }
                        .controlSize(.small)
                        .disabled(!store.hasActiveSession)
                    }
                }
                .padding(.horizontal, Spacing.edge).padding(.vertical, Spacing.standard)
                Divider()

                if loadingDiff {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if snap.isDelete {
                    ContentUnavailableView("File Deleted", systemImage: "trash",
                        description: Text("This version marks the file as deleted."))
                } else if diffLines.isEmpty {
                    ContentUnavailableView("No Changes", systemImage: "checkmark.circle",
                        description: Text("Identical to previous version, or first version."))
                } else {
                    DiffView(lines: diffLines)
                }
            } else {
                ContentUnavailableView("Select a Version", systemImage: "arrow.left",
                    description: Text("Click a version to see the diff."))
            }
        }
    }

    private func loadHistory() async {
        snapshots = await store.fileHistory(filePath: filePath)
        if let first = snapshots.first {
            selectedSnapshot = first
            await loadDiff(for: first)
        }
    }

    private func loadDiff(for snapshot: SnapshotRecord) async {
        loadingDiff = true
        defer { loadingDiff = false }
        let engine = DiffEngine()
        let afterData: Data? = if let hash = snapshot.afterHash { await store.snapshotData(hash: hash) } else { nil }
        let beforeData: Data? = if let hash = snapshot.beforeHash, !hash.isEmpty { await store.snapshotData(hash: hash) } else { nil }

        if let after = afterData, let before = beforeData {
            diffLines = engine.diff(beforeData: before, afterData: after) ?? [
                DiffLine(type: .context, text: "(Binary file, diff not available)")
            ]
        } else if let after = afterData {
            if let text = String(data: after, encoding: .utf8) {
                let lines = text.components(separatedBy: "\n")
                diffLines = lines.prefix(50).map { DiffLine(type: .addition, text: $0) }
                if lines.count > 50 { diffLines.append(DiffLine(type: .context, text: "... (\(lines.count - 50) more lines)")) }
            } else {
                diffLines = [DiffLine(type: .context, text: "(Binary file, \(after.count) bytes)")]
            }
        } else { diffLines = [] }
    }
}
