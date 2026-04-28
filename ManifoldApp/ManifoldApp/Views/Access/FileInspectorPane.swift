// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FileInspectorPane — inspector content for the Files tab.
//
// Renders an inline Quick Look preview, per-agent access chips that round-
// trip through the runtime, metadata, Open / Reveal buttons, and the
// existing tracked-versions timeline with Restore. When multiple files
// are selected, collapses to an aggregate summary.

import SwiftUI
import UniformTypeIdentifiers
import ManifoldKit

struct FileInspectorPane: View {
    @Environment(ManifoldStore.self) private var store
    let file: SourceFile?
    let selectionCount: Int
    let activity: [SnapshotRecord]
    let connectedAgents: [TargetApp]
    let visibleAgents: Set<TargetApp>
    let onToggleAgent: (TargetApp, Bool) -> Void
    let onSetAllAgents: (Bool) -> Void
    let onReset: () -> Void

    @State private var exposures: [ExposureRecord] = []
    @State private var exposuresFilePath: String?

    var body: some View {
        ScrollView {
            if selectionCount > 1 {
                multiSelectionSummary
                    .padding(Spacing.s4)
            } else if let file {
                singleFileContent(file)
                    .padding(Spacing.s4)
                    .task(id: file.path) { await loadExposures(for: file) }
            } else {
                empty
            }
        }
    }

    private func loadExposures(for file: SourceFile) async {
        guard exposuresFilePath != file.path else { return }
        exposuresFilePath = file.path
        do {
            exposures = try await store.runtime.fileExposures(resourcePath: file.path, limit: 200)
        } catch {
            exposures = []
        }
    }

    // MARK: - Single file

    @ViewBuilder
    private func singleFileContent(_ file: SourceFile) -> some View {
        let url = URL(fileURLWithPath: file.path)
        let visible = visibleAgents

        VStack(alignment: .leading, spacing: Spacing.s4) {
            QuickLookPreview(url: url)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .background(ManifoldPalette.surface3)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(alignment: .top, spacing: Spacing.s2) {
                FileTypeIcon(filename: file.name, size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(ManifoldType.heading)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Text(file.relativePath)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            accessSection(file: file, visible: visible)

            auditSection(file: file)

            HStack(spacing: Spacing.s2) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()

            metadata(file: file)

            Divider()

            versions(file: file)
        }
    }

    @ViewBuilder
    private func accessSection(file: SourceFile, visible: Set<TargetApp>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text("Sharing")
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)

            InspectorSharingSelector(
                connectedAgents: connectedAgents,
                visibleAgents: visible,
                onToggleAgent: { agent, wasVisible in
                    onToggleAgent(agent, wasVisible)
                },
                onSetAllAgents: onSetAllAgents
            )
            .accessibilityIdentifier(
                "access.inspector.file.\(file.sourceID.manifoldAccessIdentifierComponent).\(file.relativePath.manifoldAccessIdentifierComponent).selector"
            )

            Button("Reset to inherited", action: onReset)
                .buttonStyle(.borderless)
                .font(ManifoldType.caption)
        }
    }

    /// Per-agent exposure counts for the current file. Honest: when an
    /// agent has 0 reads we say "Codex 0×" rather than hiding the row,
    /// because absence-of-evidence is real audit information.
    @ViewBuilder
    private func auditSection(file: SourceFile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Audit")
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)

            if connectedAgents.isEmpty {
                Text("Connect an AI to start recording exposures.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            } else {
                let summaries = exposureSummaries(for: file)
                if exposuresFilePath == nil {
                    HStack(spacing: Spacing.s1) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text("Loading exposure history…")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(summaries, id: \.agent) { summary in
                        exposureRow(summary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func exposureRow(_ summary: AgentExposureSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.s2) {
                Circle()
                    .fill(agentColor(summary.agent))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(displayName(for: summary.agent))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.primary)
                Spacer()
                if summary.totalCount == 0 {
                    Text("never")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(summary.summaryText)
                        .font(ManifoldType.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !summary.toolBreakdown.isEmpty {
                Text(summary.toolBreakdown)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 14)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private struct AgentExposureSummary {
        let agent: TargetApp
        let readCount: Int
        let writeCount: Int
        let totalBytes: Int
        let lastTimestamp: Double?
        let topTools: [(name: String, count: Int)]
        var totalCount: Int { readCount + writeCount }
        var summaryText: String {
            var parts: [String] = []
            if readCount > 0 {
                parts.append("read \(readCount)×")
            }
            if writeCount > 0 {
                parts.append("wrote \(writeCount)×")
            }
            let joined = parts.joined(separator: ", ")
            if totalBytes > 0 {
                let bytes = ByteCountFormatter.string(
                    fromByteCount: Int64(totalBytes), countStyle: .memory
                )
                return "\(joined) (\(bytes))"
            }
            return joined
        }
        /// "via read_file (3), grep (2)" — caption line beneath the count
        /// row that tells the user which tools the agent used. Empty when
        /// the agent has no exposures.
        var toolBreakdown: String {
            guard !topTools.isEmpty else { return "" }
            let formatted = topTools.prefix(3).map { entry in
                entry.count > 1 ? "\(entry.name) (\(entry.count))" : entry.name
            }
            return "via " + formatted.joined(separator: ", ")
        }
    }

    /// Aggregates the in-memory exposure timeline by agent. Filtering on
    /// connected agents only — disconnected agents have no audit row.
    private func exposureSummaries(for file: SourceFile) -> [AgentExposureSummary] {
        let connectedRaw = Set(connectedAgents.map(\.rawValue))
        struct Bucket {
            var read = 0
            var write = 0
            var bytes = 0
            var latest: Double?
            var toolCounts: [String: Int] = [:]
        }
        var counts: [TargetApp: Bucket] = [:]
        for record in exposures {
            guard connectedRaw.contains(record.agent),
                  let agent = TargetApp(rawValue: record.agent) else { continue }
            var entry = counts[agent] ?? Bucket()
            entry.bytes += record.byteCount
            if record.exposureType.contains("write") {
                entry.write += 1
            } else {
                entry.read += 1
            }
            if let current = entry.latest {
                entry.latest = max(current, record.timestamp)
            } else {
                entry.latest = record.timestamp
            }
            if !record.toolName.isEmpty {
                entry.toolCounts[record.toolName, default: 0] += 1
            }
            counts[agent] = entry
        }
        return connectedAgents.map { agent in
            let entry = counts[agent] ?? Bucket()
            let topTools = entry.toolCounts
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return lhs.key < rhs.key
                }
                .map { (name: $0.key, count: $0.value) }
            return AgentExposureSummary(
                agent: agent,
                readCount: entry.read,
                writeCount: entry.write,
                totalBytes: entry.bytes,
                lastTimestamp: entry.latest,
                topTools: topTools
            )
        }
    }

    private func displayName(for agent: TargetApp) -> String {
        switch agent {
        case .cowork: return "Claude"
        case .codex:  return "Codex"
        }
    }

    private func agentColor(_ agent: TargetApp) -> Color {
        switch agent {
        case .cowork: return .blue
        case .codex:  return .purple
        }
    }

    @ViewBuilder
    private func metadata(file: SourceFile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            row("Source", file.sourceName)
            row("Kind", kindLabel(for: file))
            row("Size", ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
            row("Modified", Self.relativeFormatter.localizedString(for: file.modifiedDate, relativeTo: .now))
        }
    }

    @ViewBuilder
    private func versions(file: SourceFile) -> some View {
        Text("Tracked versions")
            .font(ManifoldType.captionMedium)

        if activity.isEmpty {
            Text("No tracked versions yet.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                ForEach(activity.prefix(8), id: \.id) { snapshot in
                    HStack(spacing: Spacing.s2) {
                        Circle()
                            .fill(snapshot.isBaseline ? ManifoldPalette.selection : ManifoldPalette.active)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.source.capitalized)
                                .font(ManifoldType.captionMedium)
                            Text(MailDisplayFormatter.relativeTimestamp(snapshot.timestamp))
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            Task {
                                _ = await store.restoreFile(snapshotID: snapshot.id, filePath: file.path)
                            }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Multi selection

    private var multiSelectionSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text("\(selectionCount) files selected")
                .font(ManifoldType.heading)
            Text("Use the bulk bar at the bottom of the list to share, unshare, or reset overrides for the selection.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Empty

    private var empty: some View {
        ContentUnavailableView(
            "No file selected",
            systemImage: "sidebar.right",
            description: Text("Pick a file to inspect visibility, overrides, and tracked versions.")
        )
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Text(title)
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(ManifoldType.caption)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func kindLabel(for file: SourceFile) -> String {
        let ext = file.fileExtension.isEmpty
            ? (file.path as NSString).pathExtension
            : file.fileExtension
        if ext.isEmpty { return "File" }
        if let type = UTType(filenameExtension: ext), let desc = type.localizedDescription {
            return desc
        }
        return ext.uppercased()
    }

    static let relativeFormatter = RelativeDateTimeFormatter()
}
