// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EventTable — dense 7-column ledger of audit events.
//
// Columns: leading-edge, time, agent, operation, target, size-delta, meta.
// Denial rows carry an orange leading edge and are not dimmed — denials
// are successes (Principle 1).

import SwiftUI
import ManifoldKit

struct EventTable: View {
    enum Filter: Hashable, CaseIterable {
        case all, reads, writes, denials, searches, trackedEdits

        var label: String {
            switch self {
            case .all:           return "All"
            case .reads:         return "Reads"
            case .writes:        return "Writes"
            case .denials:       return "Denials"
            case .searches:      return "Searches"
            case .trackedEdits:  return "Tracked edits"
            }
        }
    }

    let entries: [AuditEntry]
    let filter: Filter
    @Binding var selection: AuditEntry.ID?

    private var rows: [AuditEntry] {
        entries.filter { entry in
            switch filter {
            case .all:          return true
            case .reads:        return entry.action.contains("read")
            case .writes:       return entry.action.contains("write")
            case .denials:      return entry.action.contains("deny") || entry.action.contains("denied")
            case .searches:     return entry.action.contains("search")
            case .trackedEdits: return entry.action.contains("snapshot") || entry.action.contains("promote") || entry.action.contains("revert")
            }
        }
    }

    var body: some View {
        Table(of: AuditEntry.self, selection: $selection) {
            TableColumn("") { entry in
                Rectangle()
                    .fill(leadingEdgeColor(for: entry))
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }
            .width(6)

            TableColumn("Time") { entry in
                Text(Self.displayTime(entry.timestamp))
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 64, ideal: 72, max: 96)

            TableColumn("Agent") { entry in
                HStack(spacing: Spacing.s1) {
                    if let agent = entry.agent {
                        Circle()
                            .fill(agent == "codex" ? ManifoldPalette.codex : ManifoldPalette.claude)
                            .frame(width: 6, height: 6)
                        Text(agent.capitalized)
                            .font(ManifoldType.caption)
                    } else {
                        Text("—").foregroundStyle(Color.secondary)
                    }
                }
            }
            .width(min: 72, ideal: 80)

            TableColumn("Operation") { entry in
                HStack(spacing: Spacing.s1) {
                    Image(systemName: operationSymbol(for: entry))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(operationColor(for: entry))
                    Text(entry.action.replacingOccurrences(of: "_", with: " "))
                        .font(ManifoldType.caption)
                }
            }
            .width(min: 120, ideal: 160)

            TableColumn("Target") { entry in
                Text(entry.filePath?.shortenedPath ?? "—")
                    .font(ManifoldType.mono)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(entry.filePath == nil ? Color.secondary : ManifoldPalette.text)
            }

            TableColumn("Δ") { entry in
                if entry.beforeHash != nil || entry.afterHash != nil {
                    HStack(spacing: 2) {
                        SparklineBar(
                            samples: [
                                .init(value: entry.beforeHash != nil ? 0.6 : 0.0, emphasis: .muted),
                                .init(value: entry.afterHash != nil ? 0.8 : 0.0, emphasis: .active),
                            ],
                            height: 12,
                            tint: ManifoldPalette.claude,
                            spacing: 1
                        )
                        .frame(width: 14)
                    }
                } else {
                    Text("").accessibilityHidden(true)
                }
            }
            .width(24)

            TableColumn("") { entry in
                if entry.grantID != nil {
                    Pill(text: "session", variant: .session)
                } else if entry.sessionID != nil {
                    Pill(text: "session", variant: .session)
                } else {
                    Text("").accessibilityHidden(true)
                }
            }
            .width(80)
        } rows: {
            ForEach(rows) { entry in
                TableRow(entry)
            }
        }
        .tableStyle(.inset)
    }

    private func leadingEdgeColor(for entry: AuditEntry) -> Color {
        if entry.action.contains("deny") || entry.action.contains("denied") {
            return ManifoldPalette.attention
        }
        if entry.action.contains("write") {
            return ManifoldPalette.claude
        }
        return .clear
    }

    private func operationSymbol(for entry: AuditEntry) -> String {
        if entry.action.contains("deny")   { return "hand.raised" }
        if entry.action.contains("write")  { return "pencil" }
        if entry.action.contains("read")   { return "eye" }
        if entry.action.contains("search") { return "magnifyingglass" }
        return "circle.fill"
    }

    private func operationColor(for entry: AuditEntry) -> Color {
        if entry.action.contains("deny")   { return ManifoldPalette.attention }
        if entry.action.contains("write")  { return ManifoldPalette.claude }
        if entry.action.contains("read")   { return ManifoldPalette.text2 }
        if entry.action.contains("search") { return ManifoldPalette.codex }
        return ManifoldPalette.text3
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
