// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ActivityView — the user's readable proof trail.
//
// The page keeps the native three-pane ledger shape:
//   [ Sessions | Activity stream | Evidence ]
// but the center pane leads with "what happened to my data" instead of
// exposing a raw implementation table.

import SwiftUI
import ManifoldKit

struct ActivityView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var selectedEvent: AuditEntry.ID? = nil
    @State private var selectedFilter: EventTable.Filter = .all
    @State private var filterText = ""
    @State private var displayedEntries: [AuditEntry] = []
    @FocusState private var isSearchFocused: Bool

    private var filteredEntries: [AuditEntry] {
        displayedEntries.filter { selectedFilter.matches($0) }
    }

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
                ActivitySummaryStrip(
                    entries: filteredEntries,
                    selectedSession: selectedSession,
                    searchText: filterText,
                    filter: selectedFilter
                )
                Divider()
                ActivityFilterBar(filter: $selectedFilter, searchText: $filterText, isSearchFocused: $isSearchFocused)
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
            recomputeVisibleEntries()
        }
        .onChange(of: selectedFilter) {
            repairSelection()
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
        .accessibilityElement(children: .contain)
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
            repairSelection()
            return
        }
        displayedEntries = scopedEntries.filter { entry in
            [entry.action, entry.agent ?? "", entry.filePath ?? "", entry.metadata ?? ""]
                .joined(separator: "\n")
                .localizedCaseInsensitiveContains(trimmedQuery)
        }
        repairSelection()
    }

    private func repairSelection() {
        let rows = filteredEntries
        if let selectedEvent, rows.contains(where: { $0.id == selectedEvent }) {
            return
        }
        selectedEvent = rows.first?.id
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
                Button {
                    filter = option
                } label: {
                    Label(option.label, systemImage: option.systemImage)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
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
                .accessibilityIdentifier("activity.filter.\(option.label.lowercased().replacingOccurrences(of: " ", with: "-"))")
            }
            Spacer()
            HStack(spacing: Spacing.s1) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search activity", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .accessibilityIdentifier("activity.search")
            }
            .padding(.horizontal, Spacing.s2)
            .padding(.vertical, 6)
            .frame(width: 220)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .fill(ManifoldPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
            )
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.filters")
    }
}

private struct ActivitySummaryStrip: View {
    let entries: [AuditEntry]
    let selectedSession: Session?
    let searchText: String
    let filter: EventTable.Filter

    private var attentionCount: Int {
        entries.filter { entry in
            entry.action.contains("deny") ||
            entry.action.contains("denied") ||
            entry.action == AuditAction.sensitivityWarning.rawValue ||
            entry.action == AuditAction.coverageWarning.rawValue
        }.count
    }

    private var readCount: Int {
        entries.filter { $0.action.contains("read") }.count
    }

    private var writeCount: Int {
        entries.filter {
            $0.action.contains("write") ||
            $0.action == AuditAction.fileModified.rawValue ||
            $0.action == AuditAction.fileCreated.rawValue ||
            $0.action == AuditAction.fileDeleted.rawValue
        }.count
    }

    private var lastEventDescription: String {
        guard let entry = entries.first else { return "No matching events" }
        return ActivityEventPresentation(entry).title
    }

    private var title: String {
        if let selectedSession {
            return "\(ActivityEventPresentation.agentLabel(selectedSession.agent)) session"
        }
        return "Activity"
    }

    private var subtitle: String {
        var parts: [String] = []
        if filter != .all {
            parts.append(filter.label)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            parts.append("matching \"\(query)\"")
        }
        parts.append("\(entries.count) event\(entries.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(ManifoldPalette.selectionSoft)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ManifoldPalette.selection)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ManifoldType.heading)
                    .foregroundStyle(ManifoldPalette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 220, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: Spacing.s2)

            ActivitySummaryMetric(label: "Review", value: "\(attentionCount)", systemImage: "shield.lefthalf.filled", tint: attentionCount > 0 ? ManifoldPalette.attention : ManifoldPalette.active)
            ActivitySummaryMetric(label: "Reads", value: "\(readCount)", systemImage: "eye", tint: ManifoldPalette.text2)
            ActivitySummaryMetric(label: "Writes", value: "\(writeCount)", systemImage: "pencil", tint: ManifoldPalette.selection)
            ActivitySummaryMetric(label: "Latest", value: lastEventDescription, systemImage: "clock", tint: ManifoldPalette.text3, wide: true)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .frame(height: 96)
        .background(.bar)
        .accessibilityIdentifier("activity.summary")
    }
}

private struct ActivitySummaryMetric: View {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color
    var wide = false

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.tertiary)
                    .tracking(0.4)
                    .lineLimit(1)
                Text(value)
                    .font(wide ? ManifoldType.captionMedium : ManifoldType.numericCaption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .monospacedDigit()
            }
        }
        .frame(width: wide ? 160 : 88, alignment: .leading)
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(ManifoldPalette.surface.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}
