// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// SessionRail — vertical session list with per-session sparklines and
// sticky date headers. Selection drives the EventTable's session filter.

import SwiftUI
import ManifoldKit

struct SessionRail: View {
    let sessions: [Session]
    @Binding var selection: Session?

    private static let iso = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var grouped: [(date: String, sessions: [Session])] {
        let dict = Dictionary(grouping: sessions) { session -> String in
            guard let d = Self.iso.date(from: session.startTime) else { return "Unknown" }
            return Self.dayFormatter.string(from: d)
        }
        return dict.sorted { $0.key > $1.key }
            .map { (date: $0.key, sessions: $0.value) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(grouped, id: \.date) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            Button {
                                selection = session
                            } label: {
                                SessionRailRow(
                                    session: session,
                                    isSelected: selection?.id == session.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(group.date)
                            .font(ManifoldType.tiny.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                            .padding(.horizontal, Spacing.s3)
                            .padding(.vertical, Spacing.s1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ManifoldPalette.surface2)
                    }
                }

                if sessions.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("No sessions yet")
                            .font(ManifoldType.bodyMedium)
                        Text("Start a session in the toolbar to populate this rail with a ledger of who accessed what and when.")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Spacing.s3)
                }
            }
        }
    }
}

private struct SessionRailRow: View {
    let session: Session
    let isSelected: Bool

    // Build a stable pseudo-sparkline from the session's counts so the
    // rail has visual signal even before runtime exposes per-interval
    // event density.
    private var samples: [SparklineBar.Sample] {
        let total = max(1, session.actionCount)
        let reads = Double(session.readCount) / Double(total)
        let writes = Double(session.writeCount) / Double(total)
        let searches = Double(session.searchCount) / Double(total)
        return [
            .init(value: reads, emphasis: .base),
            .init(value: writes, emphasis: writes > 0 ? .active : .muted),
            .init(value: searches, emphasis: .base),
            .init(value: 0.2 + reads * 0.6, emphasis: .base),
            .init(value: 0.15 + writes * 0.7, emphasis: writes > 0 ? .active : .muted),
            .init(value: 0.12 + searches * 0.5, emphasis: .base),
            .init(value: 0.30, emphasis: .base),
        ]
    }

    private var timeText: String {
        let iso = ISO8601DateFormatter()
        guard let d = iso.date(from: session.startTime) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(spacing: Spacing.s2) {
                Circle()
                    .fill(session.agent == "codex" ? ManifoldPalette.codex : ManifoldPalette.claude)
                    .frame(width: 7, height: 7)
                Text(session.agent.capitalized)
                    .font(ManifoldType.captionMedium)
                Spacer(minLength: Spacing.s1)
                Text(timeText)
                    .font(ManifoldType.numericCaption)
                    .foregroundStyle(.tertiary)
            }
            SparklineBar(
                samples: samples,
                height: 14,
                tint: session.agent == "codex" ? ManifoldPalette.codex : ManifoldPalette.claude
            )
            HStack(spacing: Spacing.s2) {
                Text("\(session.readCount) read\(session.readCount == 1 ? "" : "s")")
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(session.writeCount) write\(session.writeCount == 1 ? "" : "s")")
            }
            .font(ManifoldType.tiny)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(isSelected ? ManifoldPalette.claudeSoft : .clear)
        )
        .padding(.horizontal, Spacing.s1)
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.agent) session at \(timeText), \(session.readCount) reads, \(session.writeCount) writes")
    }
}
