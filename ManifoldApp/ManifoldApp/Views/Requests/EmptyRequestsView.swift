// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EmptyRequestsView — the happy path.
//
// Empty should still be useful: it states the current trust posture, shows
// how future prompts will be answered, and points at the ledger evidence
// Manifold keeps for handoff between Claude and Codex.

import SwiftUI
import ManifoldKit

struct EmptyRequestsView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                RequestClearStateCard(
                    runtimeConnected: store.isRuntimeConnected,
                    pendingCount: store.pendingRequests.count,
                    lastExposure: store.dataControlSummary?.lastExposure
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: Spacing.s3)],
                    alignment: .leading,
                    spacing: Spacing.s3
                ) {
                    RequestPrincipleCard(
                        symbol: "hand.raised",
                        title: "Block",
                        value: "Not this time",
                        detail: "Unclear requests and unsafe originals can be denied without changing policy.",
                        tint: ManifoldPalette.attention
                    )
                    RequestPrincipleCard(
                        symbol: "text.badge.checkmark",
                        title: "Filter",
                        value: "Share redacted",
                        detail: "Sensitive spans are removed before the agent receives the content.",
                        tint: ManifoldPalette.selection
                    )
                    RequestPrincipleCard(
                        symbol: "text.badge.plus",
                        title: "Remember",
                        value: "Save as rule",
                        detail: "A one-off privacy decision can become a durable block, redact, warn, or allow rule.",
                        tint: ManifoldPalette.active
                    )
                }

                if !store.recentSessionEntries.isEmpty {
                    RecentSessionHandoffStrip(entries: Array(store.recentSessionEntries.prefix(3)))
                }
            }
            .padding(Spacing.s6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("requests.empty")
    }
}

private struct RequestClearStateCard: View {
    let runtimeConnected: Bool
    let pendingCount: Int
    let lastExposure: DataControlSummary.Exposure?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s4) {
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(runtimeConnected ? ManifoldPalette.activeSoft : ManifoldPalette.pausedSoft)
                Image(systemName: runtimeConnected ? "checkmark.seal.fill" : "wifi.slash")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(runtimeConnected ? ManifoldPalette.active : ManifoldPalette.paused)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(runtimeConnected ? "Nothing is waiting on you" : "Runtime is offline")
                    .font(ManifoldType.heading)
                Text(subtitle)
                    .font(ManifoldType.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastExposure {
                    Label(lastExposureLine(lastExposure), systemImage: "clock")
                        .font(ManifoldType.caption)
                        .foregroundStyle(ManifoldPalette.text2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s5)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }

    private var subtitle: String {
        if !runtimeConnected {
            return "Reconnect Manifold before approving new access. Existing rules and ledger history remain visible."
        }
        if pendingCount > 0 {
            return "\(pendingCount) request\(pendingCount == 1 ? "" : "s") need a decision."
        }
        return "Claude and Codex can continue only through the file, mail, privacy, and agent rules you have already set."
    }

    private func lastExposureLine(_ exposure: DataControlSummary.Exposure) -> String {
        let agent = exposure.agent.map(AgentMeta.label) ?? "Agent"
        return "Last exposure: \(agent) \(exposure.action) \(relativeTime(exposure.timestamp))"
    }
}

private struct RequestPrincipleCard: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(title)
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text(value)
                .font(ManifoldType.bodyMedium)
            Text(detail)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}

private struct RecentSessionHandoffStrip: View {
    let entries: [SessionHistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Label("Handoff context", systemImage: "arrow.left.arrow.right")
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            ForEach(entries) { entry in
                HStack(spacing: Spacing.s2) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(ManifoldPalette.active)
                    Text(entry.name)
                        .font(ManifoldType.captionMedium)
                        .lineLimit(1)
                    Spacer()
                    Text(entry.endedAt.formatted(.relative(presentation: .named)))
                        .font(ManifoldType.numericCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}

/// Keyboard-shortcut reference for the commit ladder. Kept as a secondary
/// affordance so the empty state doubles as a quick lookup.
struct ShortcutsCard: View {
    private struct Row: Identifiable {
        let id = UUID()
        let key: String
        let label: String
    }

    private let rows: [Row] = [
        .init(key: "↩",   label: "Not this time (focused default)"),
        .init(key: "⇧↩",  label: "Allow one reversible write"),
        .init(key: "⌘↩",  label: "Allow reversible writes in default scope"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Commit ladder")
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            ForEach(rows) { row in
                LabeledContent {
                    Text(row.label)
                        .font(ManifoldType.caption)
                        .foregroundStyle(ManifoldPalette.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    KbdLabel(row.key)
                        .frame(width: 36, alignment: .leading)
                }
            }
        }
        .padding(Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }
}

private func relativeTime(_ isoString: String) -> String {
    guard let date = ISO8601DateFormatter.shared.date(from: isoString) else { return "" }
    return date.formatted(.relative(presentation: .named))
}

#Preview("Empty Requests") {
    EmptyRequestsView()
        .frame(width: 720, height: 520)
}
