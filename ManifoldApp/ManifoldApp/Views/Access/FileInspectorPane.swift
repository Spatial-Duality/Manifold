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
    /// Agents whose state for this file is an explicit override (not just
    /// inherited from the source default). Used by the selector to render
    /// the tinted underline beneath an override row.
    var explicitAgents: Set<TargetApp> = []
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
                    .task(id: file.canonicalPath) { await loadExposures(for: file) }
            } else {
                empty
            }
        }
        .accessibilityIdentifier("access.inspector")
    }

    private func loadExposures(for file: SourceFile) async {
        guard exposuresFilePath != file.canonicalPath else { return }
        exposuresFilePath = file.canonicalPath
        do {
            exposures = try await store.runtime.fileExposures(resourcePath: file.canonicalPath, limit: 200)
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
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        NSWorkspace.shared.open(url)
                    }
                )
                .help("Double-click to open in default app")
                .accessibilityHint("Double-tap to open in default app")

            HStack(alignment: .top, spacing: Spacing.s2) {
                FileTypeIcon(filename: file.name, size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.s1) {
                        Text(file.name)
                            .font(ManifoldType.heading)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        if let touched = aiTouchedSummary {
                            sparkleBadge(touched)
                        }
                        if file.isDraftWorkspace {
                            Text("DRAFT")
                                .font(ManifoldType.captionMedium)
                                .foregroundStyle(ManifoldPalette.paused)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(ManifoldPalette.pausedSoft, in: Capsule())
                        }
                    }
                    Text(file.relativePath)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            accessSection(file: file, visible: visible)

            if file.isDraftWorkspace {
                draftWorkspaceNotice
            }

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

            AccessCheckboxStrip(
                agents: connectedAgents,
                visibleAgents: visible,
                explicitOverrideAgents: explicitAgents,
                accessibilityIDPrefix: "access.inspector.file.\(file.sourceID.manifoldAccessIdentifierComponent).\(file.relativePath.manifoldAccessIdentifierComponent)",
                onToggleAgent: onToggleAgent,
                onSetAll: onSetAllAgents
            )

            Button("Reset to inherited", action: onReset)
                .buttonStyle(.borderless)
                .font(ManifoldType.caption)
        }
    }

    // MARK: - AI-touched indicator (Goal 6 from the redesign brief)

    /// Summary of AI authorship for the current file. Computed from the
    /// existing snapshot timeline — non-baseline, non-restore snapshots
    /// from MCP/agent write paths mean an AI wrote bytes. Returns nil when no
    /// AI authorship is present (so the badge stays out of the way).
    private var aiTouchedSummary: AITouchSummary? {
        let agentSnapshots = activity.filter { snap in
            guard !snap.isBaseline, !snap.isDelete else { return false }
            let source = snap.source.lowercased()
            return source.contains("agent")
                || source.contains("mcp")
                || source.hasPrefix("standing_write_")
        }
        guard let mostRecent = agentSnapshots.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }
        return AITouchSummary(
            count: agentSnapshots.count,
            mostRecentTimestamp: mostRecent.timestamp
        )
    }

    private struct AITouchSummary {
        let count: Int
        let mostRecentTimestamp: String
    }

    /// Manifold mark inline next to the filename. The mark *is* the
    /// tracked-edit symbol — its presence says "Manifold saw this write."
    /// Saffron tint so it reads as app identity, not generic AI sparkle.
    /// Tooltip names the count + relative recency of the latest AI write.
    @ViewBuilder
    private func sparkleBadge(_ summary: AITouchSummary) -> some View {
        ManifoldMark(placement: .inline, color: ManifoldPalette.accent)
            .frame(width: 11, height: 11)
            .help(sparkleHelpText(summary))
            .accessibilityLabel(sparkleHelpText(summary))
    }

    private func sparkleHelpText(_ summary: AITouchSummary) -> String {
        let plural = summary.count == 1 ? "" : "s"
        let date = ISO8601DateFormatter().date(from: summary.mostRecentTimestamp)
            ?? Date(timeIntervalSinceReferenceDate: 0)
        let relative = Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
        return "AI-touched · \(summary.count) write\(plural), most recent \(relative)"
    }

    @ViewBuilder
    private var draftWorkspaceNotice: some View {
        HStack(alignment: .top, spacing: Spacing.s2) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ManifoldPalette.paused)
            Text("Draft workspace copy. The original folder is unchanged until this work is applied.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.s2)
        .background(ManifoldPalette.pausedSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    auditTrailFooter
                }
            }
        }
    }

    /// One-line trust footer beneath the per-agent rows: total audit
    /// entries the runtime has recorded for this file, and the date of
    /// the most recent one. The runtime is content-addressed and
    /// hash-chained — when this row says "23 audit entries since Mar 12"
    /// it means 23 cryptographically chained ledger records exist for
    /// reads of this exact file.
    @ViewBuilder
    private var auditTrailFooter: some View {
        let entryCount = exposures.count
        if entryCount > 0 {
            let earliest = exposures.last?.timestamp
            let dateText: String? = earliest.map { ts in
                Self.relativeFormatter.localizedString(
                    for: Date(timeIntervalSince1970: ts), relativeTo: .now
                )
            }
            HStack(spacing: Spacing.s1) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(ManifoldPalette.active)
                    .font(.system(size: 10))
                    .accessibilityHidden(true)
                Text(footerText(entryCount: entryCount, dateText: dateText))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 2)
            .padding(.leading, 14)
            .accessibilityLabel(
                "\(entryCount) audit \(entryCount == 1 ? "entry" : "entries") logged for this file"
            )
        }
    }

    private func footerText(entryCount: Int, dateText: String?) -> String {
        let entries = "\(entryCount) audit \(entryCount == 1 ? "entry" : "entries")"
        if let dateText {
            return "\(entries) · earliest \(dateText)"
        }
        return entries
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
        Text("Version history")
            .font(ManifoldType.captionMedium)

        if activity.isEmpty {
            Text("No versions yet.")
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
                                _ = await store.restoreFile(snapshotID: snapshot.id, filePath: file.canonicalPath)
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
