// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EvidenceInspector — right-pane detail for a selected event.
//
// Per design/html/activity.html: kicker + title + mono path + stats +
// DiffView + "Why allowed" card + file-history sparkline + related-files
// list + Revert/Open actions. Denial rows get the orange "Claude tried
// to read…" variant.

import SwiftUI
import ManifoldKit

struct EvidenceInspector: View {
    let selection: AuditEntry.ID?
    let entries: [AuditEntry]
    let store: ManifoldStore

    private var entry: AuditEntry? {
        guard let selection else { return nil }
        return entries.first(where: { $0.id == selection })
    }

    var body: some View {
        ScrollView {
            if let entry {
                if isDenial(entry) {
                    DenialDetailCard(entry: entry)
                } else {
                    EventDetailCard(entry: entry, store: store)
                }
            } else {
                VStack(spacing: Spacing.s2) {
                    Image(systemName: "rectangle.righthalf.inset.filled")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select an event to see its evidence.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.s8)
            }
        }
    }

    private func isDenial(_ entry: AuditEntry) -> Bool {
        entry.action.contains("deny") || entry.action.contains("denied")
    }
}

private struct EventDetailCard: View {
    let entry: AuditEntry
    let store: ManifoldStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(entry.action.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            if let path = entry.filePath {
                Text((path as NSString).lastPathComponent)
                    .font(ManifoldType.heading)
                Text(path.shortenedPath)
                    .font(ManifoldType.mono)
                    .foregroundStyle(ManifoldPalette.text2)
                    .textSelection(.enabled)
            }

            // Stats strip
            HStack(spacing: Spacing.s4) {
                if let agent = entry.agent {
                    LabeledMeta(label: "Agent", value: agent.capitalized)
                }
                LabeledMeta(label: "Time", value: EventTable.displayTime(entry.timestamp))
                if let grantID = entry.grantID {
                    LabeledMeta(label: "Grant", value: String(grantID.prefix(8)))
                }
            }
            .font(ManifoldType.caption)

            if entry.beforeHash != nil || entry.afterHash != nil {
                HStack(spacing: Spacing.s2) {
                    Pill(text: "changed", variant: .defaultScope)
                    Text("before → after")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: Spacing.s2) {
                if let path = entry.filePath {
                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                }
            }
            .padding(.top, Spacing.s2)
        }
        .padding(Spacing.s4)
    }
}

private struct DenialDetailCard: View {
    let entry: AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(ManifoldPalette.attention)
                Text("DENIAL")
                    .font(ManifoldType.tiny.weight(.semibold))
                    .foregroundStyle(ManifoldPalette.attention)
                    .tracking(0.5)
            }

            Text((entry.agent?.capitalized ?? "Agent") + " tried to read")
                .font(ManifoldType.heading)
            Text(entry.filePath?.shortenedPath ?? "unknown target")
                .font(ManifoldType.monoBody)
                .foregroundStyle(ManifoldPalette.text2)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text("Why this was blocked")
                    .font(ManifoldType.bodyMedium)
                Text("Not in the agent's scope for this session. Denials are successes — this is Manifold working. Grant the path to allow it, or add a rule.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.s3)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4)
                    .fill(ManifoldPalette.attentionSoft)
            )
        }
        .padding(Spacing.s4)
    }
}

private struct LabeledMeta: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(ManifoldType.tiny)
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            Text(value)
                .foregroundStyle(ManifoldPalette.text)
        }
    }
}
