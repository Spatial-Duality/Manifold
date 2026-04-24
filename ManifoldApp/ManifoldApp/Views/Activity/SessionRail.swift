// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ActivitySessionRail — native-feeling session picker for the proof trail.
// Selection narrows the activity stream, while "All activity" returns to the
// user's full ledger.

import SwiftUI
import ManifoldKit

struct ActivitySessionRail: View {
    let sessions: [Session]
    @Binding var selection: Session?

    fileprivate static let iso = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
    fileprivate static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var grouped: [(date: String, sessions: [Session])] {
        let sortedSessions = sessions.sorted { left, right in
            (Self.iso.date(from: left.startTime) ?? .distantPast) >
            (Self.iso.date(from: right.startTime) ?? .distantPast)
        }
        var result: [(date: String, sessions: [Session])] = []
        for session in sortedSessions {
            let date = Self.iso.date(from: session.startTime).map(Self.dayFormatter.string(from:)) ?? "Unknown"
            if let lastIndex = result.indices.last, result[lastIndex].date == date {
                result[lastIndex].sessions.append(session)
            } else {
                result.append((date: date, sessions: [session]))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s1, pinnedViews: .sectionHeaders) {
                Button {
                    selection = nil
                } label: {
                    ActivityAllSessionsRow(
                        sessionCount: sessions.count,
                        isSelected: selection == nil
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.s1)
                .padding(.top, Spacing.s2)

                ForEach(grouped, id: \.date) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            Button {
                                selection = session
                            } label: {
                                ActivitySessionRow(
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
                            .background(.bar)
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

private struct ActivityAllSessionsRow: View {
    let sessionCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .fill(ManifoldPalette.selectionSoft)
                Image(systemName: "tray.full")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ManifoldPalette.selection)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("All activity")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(ManifoldPalette.text)
                Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(isSelected ? ManifoldPalette.selectionSoft.opacity(0.82) : Color.clear)
        )
        .accessibilityLabel("All activity")
    }
}

private struct ActivitySessionRow: View {
    let session: Session
    let isSelected: Bool

    private var timeText: String {
        guard let d = ActivitySessionRail.iso.date(from: session.startTime) else { return "" }
        return ActivitySessionRail.timeFormatter.string(from: d)
    }

    private var durationText: String {
        guard let start = ActivitySessionRail.iso.date(from: session.startTime),
              let end = ActivitySessionRail.iso.date(from: session.endTime) else {
            return "unknown duration"
        }
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private var agentColor: Color {
        if let agent = TargetApp(rawValue: session.agent) {
            return ManifoldPalette.agent(agent)
        }
        return ManifoldPalette.text3
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s2) {
            Circle()
                .fill(agentColor)
                .frame(width: 9, height: 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s1) {
                    Text(ActivityEventPresentation.agentLabel(session.agent))
                        .font(ManifoldType.captionMedium)
                        .foregroundStyle(ManifoldPalette.text)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.s1)
                    Text(timeText)
                        .font(ManifoldType.numericCaption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                Text("\(session.actionCount) recorded event\(session.actionCount == 1 ? "" : "s") · \(durationText)")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: Spacing.s1) {
                    ActivitySessionCount(label: "Read", value: session.readCount)
                    ActivitySessionCount(label: "Write", value: session.writeCount)
                    ActivitySessionCount(label: "Search", value: session.searchCount)
                }
            }
        }
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(isSelected ? ManifoldPalette.selectionSoft.opacity(0.82) : .clear)
        )
        .padding(.horizontal, Spacing.s1)
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.agent) session at \(timeText), \(session.readCount) reads, \(session.writeCount) writes")
    }
}

private struct ActivitySessionCount: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(ManifoldType.numericCaption.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(ManifoldType.tiny)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(ManifoldPalette.surface3.opacity(0.7))
        )
    }
}
