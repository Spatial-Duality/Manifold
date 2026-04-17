// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ActivityView — the 3-pane evidence ledger.
//
// Per design/html/activity.html:
//   [ SessionRail | EventTable | EvidenceInspector ]
//
// The rail lists sessions with per-session sparklines and sticky day
// headers; the table is the dense 7-column event list with denial rows
// getting an orange leading edge; the inspector shows the evidence for
// whichever event is selected.

import SwiftUI
import ManifoldKit

struct ActivityView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var selectedEvent: AuditEntry.ID? = nil
    @State private var selectedFilter: EventTable.Filter = .all
    @State private var filterText = ""
    @State private var displayedEntries: [AuditEntry] = []
    @FocusState private var isSearchFocused: Bool

    private var selectedSession: Session? {
        store.selectedSession
    }

    private var selectedSessionBinding: Binding<Session?> {
        Binding(
            get: { store.selectedSession },
            set: { newValue in
                store.selectedSession = newValue
                Task {
                    await store.activity.selectSession(newValue)
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            ActivitySessionRail(
                sessions: store.activity.sessions,
                selection: selectedSessionBinding
            )
            .frame(width: 240)
            .background(ManifoldPalette.surface2)

            Divider()

            VStack(spacing: 0) {
                ActivityFilterBar(filter: $selectedFilter, searchText: $filterText, isSearchFocused: $isSearchFocused)
                if let selectedSession {
                    Divider()
                    SessionSummaryHeader(session: selectedSession, entries: displayedEntries)
                }
                Divider()
                EventTable(
                    entries: displayedEntries,
                    filter: selectedFilter,
                    selection: $selectedEvent,
                    onFilterToAgent: { agent in
                        filterText = agent
                        selectedFilter = .all
                    },
                    onFocusSession: { sessionID in
                        guard let sessionID,
                              let session = store.activity.sessions.first(where: { $0.id == sessionID }) else { return }
                        selectedSessionBinding.wrappedValue = session
                    }
                )
            }
            .frame(maxWidth: .infinity)
            .background(ManifoldPalette.surface)

            Divider()

            EvidenceInspector(
                selection: selectedEvent,
                entries: displayedEntries,
                store: store
            )
            .frame(width: 340)
            .background(ManifoldPalette.surface2)
        }
        .task {
            await store.activity.loadActivity()
            await store.activity.loadSessions()
            recomputeVisibleEntries()
        }
        .onChange(of: selectedSession?.id) {
            selectedEvent = nil
            recomputeVisibleEntries()
        }
        .onChange(of: filterText) {
            recomputeVisibleEntries()
        }
        .onChange(of: store.activity.activityRevision) {
            recomputeVisibleEntries()
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldFocusCurrentSearch)) { _ in
            isSearchFocused = true
        }
        .accessibilityIdentifier("ledger.surface.activity")
    }

    private func recomputeVisibleEntries() {
        let scopedEntries = if let selectedSession {
            store.activityEntries.filter { $0.sessionID == selectedSession.id || $0.grantID == selectedSession.id }
        } else {
            store.activityEntries
        }
        let trimmedQuery = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            displayedEntries = scopedEntries
            return
        }
        displayedEntries = scopedEntries.filter { entry in
            [entry.action, entry.agent ?? "", entry.filePath ?? "", entry.metadata ?? ""]
                .joined(separator: "\n")
                .localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}

/// Filter chips above the event table.
private struct ActivityFilterBar: View {
    @Binding var filter: EventTable.Filter
    @Binding var searchText: String
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ForEach(EventTable.Filter.allCases, id: \.self) { option in
                Button(option.label) {
                    filter = option
                }
                .buttonStyle(.plain)
                .font(ManifoldType.captionMedium)
                .padding(.horizontal, Spacing.s2)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(option == filter ? ManifoldPalette.selectionSoft : Color.clear)
                )
                .foregroundStyle(option == filter ? ManifoldPalette.selection : ManifoldPalette.text2)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            option == filter ? ManifoldPalette.selection.opacity(0.35) : ManifoldPalette.border,
                            lineWidth: 0.5
                        )
                )
            }
            Spacer()
            TextField("Filter activity", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .focused($isSearchFocused)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
    }
}

private struct SessionSummaryHeader: View {
    let session: Session
    let entries: [AuditEntry]

    private var deniedCount: Int {
        entries.filter { $0.action.contains("deny") || $0.action.contains("denied") }.count
    }

    private var restoredCount: Int {
        entries.filter { $0.action == "restore" || $0.action.contains("manifold-restore") }.count
    }

    var body: some View {
        HStack(spacing: Spacing.s4) {
            SessionSummaryMetric(label: "Reads", value: "\(session.readCount)")
            SessionSummaryMetric(label: "Writes", value: "\(session.writeCount)")
            SessionSummaryMetric(label: "Searches", value: "\(session.searchCount)")
            SessionSummaryMetric(label: "Denied", value: "\(deniedCount)")
            SessionSummaryMetric(label: "Restored", value: "\(restoredCount)")
            Spacer()
            Text(session.agent.capitalized)
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(ManifoldPalette.surface3.opacity(0.75))
    }
}

private struct SessionSummaryMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(ManifoldType.tiny)
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            Text(value)
                .font(ManifoldType.numericCaption.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}
