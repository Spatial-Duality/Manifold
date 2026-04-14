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
                    selection: $selectedEvent
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
    }
}

/// Filter chips above the event table.
private struct EventTableToolbar: View {
    @Binding var filter: EventTable.Filter

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
                        .fill(option == filter ? ManifoldPalette.claudeSoft : Color.clear)
                )
                .foregroundStyle(option == filter ? ManifoldPalette.claude : ManifoldPalette.text2)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            option == filter ? ManifoldPalette.claude.opacity(0.35) : ManifoldPalette.border,
                            lineWidth: 0.5
                        )
                )
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
    }
}
