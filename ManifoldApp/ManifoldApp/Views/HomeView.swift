import SwiftUI

struct HomeView: View {
    @Environment(ManifoldStore.self) var store
    @State private var isLoading = true

    private var activeSources: [SourceRecord] {
        store.sources.filter { $0.isAccessible && !$0.isRemoved }
    }

    var body: some View {
        Group {
            if isLoading && store.sources.isEmpty && store.activityEntries.isEmpty {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: Spacing.large) {
                        HomeSessionCard(activeSources: activeSources)
                        if let completed = store.lastCompletedSession {
                            SessionRecapCard(session: completed)
                        }
                        HomeStatsRow(activeSources: activeSources)
                        if !store.activityEntries.isEmpty {
                            RecentActivityCard()
                        }
                    }
                    .padding(Spacing.edge)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Home")
        .navigationSubtitle(statusSubtitle)
        .task {
            await store.loadSummary()
            isLoading = false
        }
    }

    private var statusSubtitle: String {
        if store.hasActiveSession { return "Session active" }
        let count = activeSources.count
        if count == 0 { return "No sources configured" }
        return "\(count) source\(count == 1 ? "" : "s") ready"
    }
}

// MARK: - Session Card (Router)

private struct HomeSessionCard: View {
    @Environment(ManifoldStore.self) var store
    let activeSources: [SourceRecord]

    var body: some View {
        VStack(spacing: Spacing.section) {
            if store.hasActiveSession, let grant = store.activeGrant {
                ActiveSessionCard(grant: grant)
            } else if activeSources.isEmpty {
                HomeEmptyStateCard()
            } else {
                ReadyToStartCard(activeSources: activeSources)
            }
        }
    }
}

// MARK: - Active Session

private struct ActiveSessionCard: View {
    @Environment(ManifoldStore.self) var store
    let grant: GrantRecord

    private static let isoFormatter = ISO8601DateFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            HStack {
                ColorIndicator(color: .green, size: 10)
                    .accessibilityLabel("Active session")
                Text("Session Active")
                    .font(.title3.weight(.medium))
                Spacer()
                if let started = Self.isoFormatter.date(from: grant.startedAt) {
                    Text(started, format: .relative(presentation: .named))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: Spacing.edge) {
                StatPill(label: "Sources", value: "\(store.activeGrantSources.count)", icon: "folder.fill")
                StatPill(label: "Emails", value: "\(store.selectedEmailIDsForNextSession.count)", icon: "envelope.fill")
            }

            HStack(spacing: Spacing.section) {
                Button("Review Changes") {
                    store.selectedSidebarItem = .history
                }
                .glassProminentButton()
                .controlSize(.regular)

                Button("End Session") {
                    Task { await store.endSession() }
                }
                .glassButton()
                .controlSize(.regular)
                .tint(.orange)
            }
        }
        .padding(Spacing.edge)
        .contentCard()
    }
}

// MARK: - Ready to Start

private struct ReadyToStartCard: View {
    @Environment(ManifoldStore.self) var store
    let activeSources: [SourceRecord]

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: Spacing.section) {
            Text("Ready to start")
                .font(.title3.weight(.medium))

            HStack(spacing: Spacing.edge) {
                StatPill(label: "Sources", value: "\(activeSources.count)", icon: "folder.fill")
                StatPill(label: "Emails", value: "\(store.selectedEmailIDsForNextSession.count)", icon: "envelope.fill")
            }

            PresetPickerView(selectedPreset: $store.selectedPreset)

            Button {
                Task { await store.startSession() }
            } label: {
                Label(
                    store.selectedPreset.map { "Start \($0.name)" } ?? "Start Session",
                    systemImage: "play.fill"
                )
            }
            .glassProminentButton()
            .controlSize(.large)
        }
        .padding(Spacing.edge)
        .contentCard()
    }
}

// MARK: - Empty State

private struct HomeEmptyStateCard: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: Spacing.section) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Add a folder to get started")
                .font(.headline)
            Text("Manifold versions and controls what AI agents can access.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Folder") {
                store.addSourceFromPicker()
            }
            .glassProminentButton()
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xlarge)
        .contentCard()
    }
}

// MARK: - Session Recap

private struct SessionRecapCard: View {
    @Environment(ManifoldStore.self) var store
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(nsColor: .systemGreen))
                Text("Session Complete")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Dismiss") {
                    store.lastCompletedSession = nil
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            HStack(spacing: Spacing.edge) {
                Label("\(session.readCount) reads", systemImage: "eye")
                Label("\(session.writeCount) writes", systemImage: "pencil")
                Label("\(session.searchCount) searches", systemImage: "magnifyingglass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("View in History") {
                store.lastCompletedSession = nil
                store.selectedSidebarItem = .history
            }
            .controlSize(.small)
        }
        .padding(Spacing.edge)
        .contentCard(tint: Color(nsColor: .systemGreen))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Stats Row

private struct HomeStatsRow: View {
    @Environment(ManifoldStore.self) var store
    let activeSources: [SourceRecord]

    var body: some View {
        HStack(spacing: Spacing.edge) {
            Button { store.selectedSidebarItem = .sources } label: {
                Label("\(activeSources.count) sources", systemImage: "folder.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text("·").foregroundStyle(.quaternary)

            Button { store.selectedSidebarItem = .history } label: {
                Label("\(store.allTrackedFiles.count) tracked files", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text("·").foregroundStyle(.quaternary)

            Button { store.selectedSidebarItem = .history } label: {
                Label("\(store.sessions.count) sessions", systemImage: "rectangle.stack")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, Spacing.tight)
    }
}

// MARK: - Recent Activity

private struct RecentActivityCard: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            HStack {
                Text("Recent Activity")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("See all") {
                    store.selectedSidebarItem = .history
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
            }

            ForEach(store.activityEntries.prefix(5)) { entry in
                HStack(spacing: Spacing.standard) {
                    Image(systemName: ActionFormatting.icon(for: entry.action))
                        .foregroundStyle(ActionFormatting.color(for: entry.action))
                        .imageScale(.small)
                        .frame(width: 16)
                    Text(ActionFormatting.description(for: entry))
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    TimeLabel(iso8601: entry.timestamp)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(Spacing.edge)
        .contentCard()
    }
}

// MARK: - Supporting Views

private struct StatPill: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: Spacing.tight) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .imageScale(.small)
            Text(value)
                .font(.callout.weight(.medium).monospacedDigit())
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
