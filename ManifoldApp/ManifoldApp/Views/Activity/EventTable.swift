// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EventTable — readable activity stream for audit events.
//
// This intentionally avoids a raw database-table presentation. The activity
// page is the user's proof trail, so rows read as "what happened" with the
// relevant agent, target, and outcome visible without decoding columns.

import SwiftUI
import ManifoldKit

struct EventTable: View {
    enum Filter: Hashable, CaseIterable {
        case all, reads, writes, denials, searches, trackedEdits, privacy

        var label: String {
            switch self {
            case .all:           return "All"
            case .reads:         return "Reads"
            case .writes:        return "Writes"
            case .denials:       return "Denials"
            case .searches:      return "Searches"
            case .trackedEdits:  return "Tracked edits"
            case .privacy:       return "Privacy"
            }
        }
    }

    let entries: [AuditEntry]
    let filter: Filter
    @Binding var selection: AuditEntry.ID?
    var onFilterToAgent: (String) -> Void = { _ in }
    var onFocusSession: (String?) -> Void = { _ in }

    private var rows: [AuditEntry] {
        entries.filter { filter.matches($0) }
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No matching activity",
                    systemImage: filter.systemImage,
                    description: Text("Change the filter or search text to see more of the ledger.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { entry in
                            ActivityEventRow(
                                entry: entry,
                                isSelected: selection == entry.id
                            ) {
                                selection = entry.id
                            }
                            .contextMenu {
                                contextMenu(for: entry)
                            }
                            .accessibilityIdentifier("activity.event.\(entry.id)")

                            Divider()
                                .padding(.leading, 66)
                        }
                    }
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s2)
                }
            }
        }
        .background(ManifoldPalette.surface)
        .accessibilityIdentifier("activity.events.table")
    }

    @ViewBuilder
    private func contextMenu(for entry: AuditEntry) -> some View {
        Button("View Evidence") {
            selection = entry.id
        }
        if let path = entry.filePath {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        if let agent = entry.agent {
            Button("Filter to \(ActivityEventPresentation.agentLabel(agent))") {
                onFilterToAgent(agent)
            }
        }
        if entry.sessionID != nil || entry.grantID != nil {
            Button("Focus This Session") {
                onFocusSession(entry.sessionID ?? entry.grantID)
            }
        }
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let hmsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func displayTime(_ iso: String) -> String {
        guard let d = isoFormatter.date(from: iso) else { return "" }
        return hmsFormatter.string(from: d)
    }
}

private struct ActivityEventRow: View {
    let entry: AuditEntry
    let isSelected: Bool
    let onSelect: () -> Void

    private var presentation: ActivityEventPresentation {
        ActivityEventPresentation(entry)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                ZStack {
                    Circle()
                        .fill(presentation.color.opacity(0.15))
                    Image(systemName: presentation.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(presentation.color)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                        Text(presentation.title)
                            .font(ManifoldType.bodyMedium)
                            .foregroundStyle(ManifoldPalette.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: Spacing.s2)

                        Text(EventTable.displayTime(entry.timestamp))
                            .font(ManifoldType.numericCaption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Text(presentation.detail)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Spacing.s1) {
                        AgentPill(rawAgent: entry.agent)

                        if let target = presentation.target {
                            Pill(text: target, variant: .scope, systemImage: "doc.text")
                                .lineLimit(1)
                        }

                        Pill(text: presentation.outcomeLabel, variant: presentation.outcomeVariant, systemImage: presentation.outcomeSymbol)

                        if entry.beforeHash != nil || entry.afterHash != nil {
                            Pill(text: "Changed", variant: .defaultScope, systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(isSelected ? ManifoldPalette.selectionSoft.opacity(0.82) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if presentation.needsAttention {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(presentation.color)
                        .frame(width: 3)
                        .padding(.vertical, Spacing.s2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(presentation.title). \(presentation.detail)")
    }
}

private struct AgentPill: View {
    let rawAgent: String?

    var body: some View {
        if let rawAgent, let agent = TargetApp(rawValue: rawAgent) {
            Pill(
                text: AgentMeta.label(agent),
                variant: .agent(agent),
                systemImage: AgentMeta.systemImage(agent)
            )
        } else if let rawAgent, !rawAgent.isEmpty {
            Pill(text: rawAgent.capitalized, variant: .neutral, systemImage: "sparkles")
        } else {
            Pill(text: "System", variant: .neutral, systemImage: "gearshape")
        }
    }
}

extension EventTable.Filter {
    func matches(_ entry: AuditEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .reads:
            return entry.action.contains("read")
        case .writes:
            return entry.action.contains("write") ||
                   entry.action == AuditAction.fileModified.rawValue ||
                   entry.action == AuditAction.fileCreated.rawValue ||
                   entry.action == AuditAction.fileDeleted.rawValue
        case .denials:
            return entry.action.contains("deny") || entry.action.contains("denied")
        case .searches:
            return entry.action.contains("search")
        case .trackedEdits:
            return entry.action.contains("snapshot") ||
                   entry.action.contains("promote") ||
                   entry.action.contains("revert") ||
                   entry.action == AuditAction.restore.rawValue
        case .privacy:
            return entry.action == AuditAction.sensitivityWarning.rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .reads: return "eye"
        case .writes: return "pencil"
        case .denials: return "hand.raised"
        case .searches: return "magnifyingglass"
        case .trackedEdits: return "arrow.triangle.2.circlepath"
        case .privacy: return "shield.lefthalf.filled"
        }
    }
}

struct ActivityEventPresentation {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let outcomeLabel: String
    let outcomeSymbol: String
    let outcomeVariant: Pill.Variant
    let target: String?
    let needsAttention: Bool

    init(_ entry: AuditEntry) {
        let action = entry.action
        let targetName = entry.filePath.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        let targetPath = entry.filePath?.shortenedPath
        let agent = entry.agent.map(Self.agentLabel) ?? "Manifold"
        let metadata = Self.metadataValues(for: entry)
        let privacyOutcome = metadata["privacy_outcome"].flatMap(PrivacyOutcome.init(rawValue:))

        target = targetName

        if action.contains("deny") || action.contains("denied") {
            title = "\(agent) was blocked"
            detail = targetPath.map { "Manifold kept \($0) out of scope." } ?? "Manifold blocked an out-of-scope request."
            symbol = "hand.raised.fill"
            color = ManifoldPalette.attention
            outcomeLabel = "Blocked"
            outcomeSymbol = "lock.fill"
            outcomeVariant = .attention
            needsAttention = true
        } else if action == AuditAction.sensitivityWarning.rawValue {
            title = privacyOutcome?.displayName ?? "Privacy decision"
            detail = metadata["privacy_summary"] ?? targetPath.map { "Privacy filter reviewed \($0) before sharing." } ?? "Privacy filter reviewed content before sharing."
            symbol = "shield.lefthalf.filled"
            switch privacyOutcome {
            case .blocked:
                color = ManifoldPalette.danger
                outcomeLabel = "Secret blocked"
                outcomeVariant = .attention
                needsAttention = true
            case .filtered:
                color = ManifoldPalette.preview
                outcomeLabel = "Filtered"
                outcomeVariant = .preview
                needsAttention = false
            default:
                color = ManifoldPalette.attention
                outcomeLabel = "Needs review"
                outcomeVariant = .attention
                needsAttention = true
            }
            outcomeSymbol = "shield"
        } else if action == AuditAction.coverageWarning.rawValue {
            title = "Coverage warning"
            detail = targetPath.map { "\(agent) touched \($0) near the protected boundary." } ?? "\(agent) produced a coverage warning."
            symbol = "exclamationmark.triangle.fill"
            color = ManifoldPalette.attention
            outcomeLabel = "Review"
            outcomeSymbol = "exclamationmark.triangle"
            outcomeVariant = .attention
            needsAttention = true
        } else if action == AuditAction.mcpConnection.rawValue {
            title = "\(agent) connected"
            detail = "The agent route connected through Manifold."
            symbol = "point.3.connected.trianglepath.dotted"
            color = ManifoldPalette.text3
            outcomeLabel = "Connected"
            outcomeSymbol = "checkmark.circle"
            outcomeVariant = .neutral
            needsAttention = false
        } else if action.contains("write") || action == AuditAction.fileModified.rawValue || action == AuditAction.fileCreated.rawValue || action == AuditAction.fileDeleted.rawValue {
            title = Self.writeTitle(action: action, targetName: targetName)
            detail = targetPath.map { "\(agent) changed \($0)." } ?? "\(agent) wrote to a protected workspace."
            symbol = "pencil"
            color = ManifoldPalette.claude
            outcomeLabel = "Written"
            outcomeSymbol = "pencil"
            outcomeVariant = .defaultScope
            needsAttention = false
        } else if action.contains("read") {
            title = targetName.map { "Read \($0)" } ?? "File read"
            detail = targetPath.map { "\(agent) read \($0)." } ?? "\(agent) read shared content."
            symbol = "eye"
            color = ManifoldPalette.text2
            outcomeLabel = "Read"
            outcomeSymbol = "eye"
            outcomeVariant = .neutral
            needsAttention = false
        } else if action.contains("search") {
            title = "Search"
            detail = targetPath.map { "\(agent) searched near \($0)." } ?? "\(agent) searched shared context."
            symbol = "magnifyingglass"
            color = ManifoldPalette.codex
            outcomeLabel = "Search"
            outcomeSymbol = "magnifyingglass"
            outcomeVariant = .neutral
            needsAttention = false
        } else if action.contains("snapshot") || action.contains("promote") || action.contains("revert") || action == AuditAction.restore.rawValue {
            title = action.replacingOccurrences(of: "_", with: " ").capitalized
            detail = targetPath.map { "Manifold recorded a recoverable version for \($0)." } ?? "Manifold recorded a recoverable version."
            symbol = "arrow.triangle.2.circlepath"
            color = ManifoldPalette.active
            outcomeLabel = "Tracked"
            outcomeSymbol = "clock.arrow.circlepath"
            outcomeVariant = .defaultScope
            needsAttention = false
        } else {
            title = action.replacingOccurrences(of: "_", with: " ").capitalized
            detail = targetPath.map { "\(agent) activity on \($0)." } ?? "Manifold recorded this activity."
            symbol = "circle.fill"
            color = ManifoldPalette.text3
            outcomeLabel = entry.grantID != nil || entry.sessionID != nil ? "Session" : "Logged"
            outcomeSymbol = entry.grantID != nil || entry.sessionID != nil ? "play.fill" : "list.bullet"
            outcomeVariant = entry.grantID != nil || entry.sessionID != nil ? .session : .neutral
            needsAttention = false
        }
    }

    static func agentLabel(_ rawAgent: String) -> String {
        guard let agent = TargetApp(rawValue: rawAgent) else {
            if rawAgent == "Unknown Agent" { return "Unknown agent" }
            return rawAgent.capitalized
        }
        return AgentMeta.label(agent)
    }

    private static func metadataValues(for entry: AuditEntry) -> [String: String] {
        guard let metadata = entry.metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return json
    }

    private static func writeTitle(action: String, targetName: String?) -> String {
        switch action {
        case AuditAction.fileCreated.rawValue:
            return targetName.map { "Created \($0)" } ?? "File created"
        case AuditAction.fileDeleted.rawValue:
            return targetName.map { "Deleted \($0)" } ?? "File deleted"
        default:
            return targetName.map { "Changed \($0)" } ?? "File changed"
        }
    }
}
