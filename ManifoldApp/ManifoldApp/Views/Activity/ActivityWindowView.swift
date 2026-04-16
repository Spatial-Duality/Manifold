// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ActivityWindowView — the 3-pane evidence ledger.
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

struct ActivityWindowView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var selectedSession: Session? = nil
    @State private var selectedEvent: AuditEntry.ID? = nil
    @State private var filter: EventTable.Filter = .all
    @State private var showNewRuleSheet = false

    var body: some View {
        HStack(spacing: 0) {
            SessionRail(
                sessions: store.history.sessions,
                selection: $selectedSession
            )
            .frame(width: 240)
            .background(ManifoldPalette.surface2)

            Divider()

            VStack(spacing: 0) {
                EventTableToolbar(filter: $filter)
                Divider()
                EventTable(
                    entries: store.activityEntries,
                    filter: filter,
                    selection: $selectedEvent,
                    onRevokeSource: { entry in
                        Task { await revokeSource(for: entry) }
                    },
                    onAddDenyRule: { _ in
                        showNewRuleSheet = true
                    }
                )
            }
            .frame(maxWidth: .infinity)
            .background(ManifoldPalette.surface)

            Divider()

            EvidenceInspector(
                selection: selectedEvent,
                entries: store.activityEntries,
                store: store
            )
            .frame(width: 340)
            .background(ManifoldPalette.surface2)
        }
        .task {
            await store.history.loadActivity()
            await store.history.loadSessions()
        }
        .sheet(isPresented: $showNewRuleSheet) {
            NewRuleSheet(domain: .files) { rule in
                store.rules.add(rule)
                showNewRuleSheet = false
            }
        }
    }

    /// Find the source that contains `entry.filePath` (by root-path prefix)
    /// and revoke it from whichever agent(s) currently see it. Honest
    /// no-op when no match — the menu item only appears when the entry
    /// carries a path, but the source may have been removed since.
    private func revokeSource(for entry: AuditEntry) async {
        guard let path = entry.filePath, !path.isEmpty else { return }
        let expanded = (path as NSString).expandingTildeInPath
        guard let source = store.sources.first(where: { src in
            let root = (src.originalRootPath as NSString).expandingTildeInPath
            return expanded.hasPrefix(root)
        }) else { return }

        let claudeHas = store.policy.claudePolicy?.allowedSourceIDs.contains(source.sourceID) == true
        let codexHas = store.policy.codexPolicy?.allowedSourceIDs.contains(source.sourceID) == true

        if claudeHas {
            await store.policy.removeSource(source.sourceID, from: .cowork)
        }
        if codexHas {
            await store.policy.removeSource(source.sourceID, from: .codex)
        }
    }
}

/// Native segmented filter above the event table. Replaces the previous
/// custom capsule pills per APPLE-DESIGN-EXCELLENCE-GUIDE §3.
private struct EventTableToolbar: View {
    @Binding var filter: EventTable.Filter

    var body: some View {
        HStack {
            Picker("Filter", selection: $filter) {
                ForEach(EventTable.Filter.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial)
    }
}
