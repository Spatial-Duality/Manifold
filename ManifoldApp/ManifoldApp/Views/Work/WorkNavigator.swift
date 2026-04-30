// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct WorkNavigator: View {
    @Environment(ManifoldStore.self) private var store
    @Bindable var work: WorkModel

    var body: some View {
        VStack(spacing: 0) {
            header
            List(selection: sessionSelection) {
                activeSection
                preparedSection
                recentSection
            }
            .listStyle(.sidebar)
        }
        .accessibilityIdentifier("work.sessions")
    }

    private var header: some View {
        HStack(spacing: Spacing.s2) {
            Text("Sessions")
                .font(ManifoldType.bodyMedium)
            Spacer()
            Menu {
                Button {
                    beginPreload(baseMode: .buildOnDefault)
                } label: {
                    Label("Build on Default", systemImage: "plus.rectangle.on.rectangle")
                }
                Button {
                    beginPreload(baseMode: .blank)
                } label: {
                    Label("Start Blank", systemImage: "plus.rectangle")
                }
            } label: {
                Label("New Session", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("New session")
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityIdentifier("work.sessions.new")
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
    }

    private var sessionSelection: Binding<WorkSessionSelection?> {
        Binding(
            get: { work.sessionSelection },
            set: { selection in
                guard let selection else { return }
                work.sessionSelection = selection
                work.inspectorSelection = .session(selection)
                if case .recent(let id) = selection,
                   let session = store.activity.sessions.first(where: { $0.id == id }) {
                    Task { await store.activity.selectSession(session) }
                }
            }
        )
    }

    @ViewBuilder
    private var activeSection: some View {
        Section("Active") {
            if let active = store.activeSession {
                WorkSessionListRow(
                    title: sessionDisplayName(active),
                    subtitle: activeSubtitle(active),
                    agent: active.agents.first ?? store.defaultSessionAgent,
                    status: "Active",
                    folderCount: store.session.activeGrantSources.count,
                    mailboxCount: activeMailboxCount(for: store),
                    pendingCount: store.pendingRequests.count
                )
                .tag(WorkSessionSelection.active)
                .accessibilityIdentifier("work.session.active")
            } else if store.sessionStartupMode == .defaultSession {
                WorkSessionListRow(
                    title: "Default session",
                    subtitle: "Starts when the runtime is connected",
                    agent: store.defaultSessionAgent,
                    status: "Standby",
                    folderCount: store.defaultSourceIDs(for: store.defaultSessionAgent).count,
                    mailboxCount: 0,
                    pendingCount: 0
                )
                .tag(WorkSessionSelection.defaultSession)
                .accessibilityIdentifier("work.session.default")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No session active")
                        .font(ManifoldType.captionMedium)
                    Text("Prepare a session to give an agent access.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("work.session.none")
            }
        }
    }

    @ViewBuilder
    private var preparedSection: some View {
        if let preload = store.sessionWorkbench.preload {
            Section("Prepared") {
                let defaultIDs = store.defaultSourceIDs(for: preload.agent)
                let effective = preload.effectiveSourceIDs(defaultSourceIDs: defaultIDs)
                WorkSessionListRow(
                    title: preload.name.isEmpty ? "New session" : preload.name,
                    subtitle: preload.baseMode.label,
                    agent: preload.agent,
                    status: "Prepared",
                    folderCount: effective.count,
                    mailboxCount: preload.selectedEmailIDs.count,
                    pendingCount: 0
                )
                .tag(WorkSessionSelection.prepared)
                .accessibilityIdentifier("work.session.prepared")
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !store.activity.sessions.isEmpty {
            Section("Recent") {
                ForEach(store.activity.sessions.prefix(20)) { session in
                    let agent = TargetApp(rawValue: session.agent) ?? .cowork
                    WorkSessionListRow(
                        title: "\(AgentMeta.label(agent)) session",
                        subtitle: relativeTime(session.endTime),
                        agent: agent,
                        status: "Ended",
                        folderCount: 0,
                        mailboxCount: 0,
                        pendingCount: 0
                    )
                    .tag(WorkSessionSelection.recent(sessionID: session.id))
                    .accessibilityIdentifier("work.session.recent.\(session.id)")
                }
            }
        }
    }

    private func beginPreload(baseMode: PreloadBaseMode) {
        store.beginSessionPreload(
            agent: store.defaultSessionAgent,
            baseMode: baseMode
        )
        work.sessionSelection = .prepared
        work.inspectorSelection = .session(.prepared)
    }

    private func sessionDisplayName(_ session: SessionRecord) -> String {
        if let name = store.session.activeGrant?.summaryFraming, !name.isEmpty {
            return name
        }
        return session.name
    }

    private func activeSubtitle(_ session: SessionRecord) -> String {
        let agent = session.agents.first.map { store.displayName(for: $0) } ?? "Agent"
        let folders = store.session.activeGrantSources.count
        return "\(agent) · \(folders) folder\(folders == 1 ? "" : "s")"
    }

    private func relativeTime(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.shared.date(from: iso) else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct WorkSessionListRow: View {
    let title: String
    let subtitle: String
    let agent: TargetApp
    let status: String
    let folderCount: Int
    let mailboxCount: Int
    let pendingCount: Int

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: AgentMeta.systemImage(agent))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s1) {
                    Text(title)
                        .lineLimit(1)
                    if pendingCount > 0 {
                        Text("\(pendingCount)")
                            .font(ManifoldType.tiny.weight(.semibold))
                            .foregroundStyle(ManifoldPalette.attention)
                    }
                }
                Text(detailLine)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.s1)

            Text(status)
                .font(ManifoldType.tiny.weight(.semibold))
                .foregroundStyle(status == "Active" ? ManifoldPalette.active : .secondary)
                .lineLimit(1)
        }
    }

    private var detailLine: String {
        var parts = [AgentMeta.label(agent), subtitle]
        if folderCount > 0 {
            parts.append("\(folderCount) folder\(folderCount == 1 ? "" : "s")")
        }
        if mailboxCount > 0 {
            parts.append("\(mailboxCount) mail")
        }
        return parts.joined(separator: " · ")
    }
}
