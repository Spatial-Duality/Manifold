// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AccessView — the "who can see what" surface.
//
// Per design/html/access.html: 4-tab router — Folders / Files / Session
// / History — plus an empty state when no sources exist. Each sub-view
// is a dense matrix or list with its own inspector on the right.

import SwiftUI
import ManifoldKit

struct AccessView: View {
    @Environment(ManifoldStore.self) private var store

    enum AccessSection: String, Hashable, CaseIterable {
        case folders
        case files
        case session
        case memory
        case history

        var label: String {
            switch self {
            case .folders: return "Folders"
            case .files:   return "Files"
            case .session: return "Session"
            case .memory:  return "Memory"
            case .history: return "History"
            }
        }

        var systemImage: String {
            switch self {
            case .folders: return "folder.fill"
            case .files:   return "doc.on.doc"
            case .session: return "play.fill"
            case .memory:  return "brain"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    @State private var selectedSection: AccessSection = .folders
    @AppStorage("access.inspector.visible") private var isInspectorVisible = true

    var body: some View {
        VStack(spacing: 0) {
            SegmentedTabBar(
                selection: $selectedSection,
                items: AccessSection.allCases.map { item in
                    SegmentedTabItem(
                        value: item,
                        title: item.label,
                        systemImage: item.systemImage,
                        isEnabled: item != .session || store.activeSession != nil,
                        accessibilityIdentifier: "access.tab.\(item.rawValue)"
                    )
                }
            ) {
                AccessAddControls(
                    onAddFolder: {
                        if store.addSourceFromPicker() {
                            selectedSection = .folders
                        }
                    },
                    onAddFiles: {
                        if store.addFilesFromPicker() {
                            selectedSection = .files
                        }
                    }
                )
            }
            Divider()

            if store.sources.isEmpty {
                EmptyFoldersView()
            } else {
                switch selectedSection {
                case .folders: FoldersMatrixView()
                case .files:   FilesFlatView()
                case .session: SessionDiffView()
                case .memory:  AccessMemoryView()
                case .history: AccessHistoryView()
                }
            }
        }
        .background {
            Button("Toggle Inspector") { isInspectorVisible.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .opacity(0)
                .accessibilityHidden(true)
        }
        .task { await store.refreshAll(force: false) }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldFocusCurrentSearch)) { _ in
            guard selectedSection != .files else { return }
            selectedSection = .files
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .manifoldFocusCurrentSearch, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .manifoldCycleCurrentSubtab)) { notification in
            guard let delta = notification.object as? Int else { return }
            cycleTab(by: delta)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.surface.access")
    }

    private func cycleTab(by delta: Int) {
        let enabledSections = AccessSection.allCases.filter { $0 != .session || store.activeSession != nil }
        guard let currentIndex = enabledSections.firstIndex(of: selectedSection), !enabledSections.isEmpty else { return }
        let nextIndex = (currentIndex + delta + enabledSections.count) % enabledSections.count
        withAnimation(ManifoldMotion.micro) {
            selectedSection = enabledSections[nextIndex]
        }
    }
}

private struct AccessAddControls: View {
    let onAddFolder: () -> Void
    let onAddFiles: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Button(action: onAddFolder) {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .help("Add folders Manifold can protect and share per agent")
            .accessibilityIdentifier("access.addFolder")

            Button(action: onAddFiles) {
                Label("Add Files", systemImage: "doc.badge.plus")
            }
            .help("Pick files to bring their containing folders into Access")
            .accessibilityIdentifier("access.addFiles")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
    }
}

private struct AccessMemoryView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                header
                memoryControls
                memorySummary
                sourceSummary
                memoryList
            }
            .padding(Spacing.s5)
        }
        .task { await store.personalDataOS.loadMemory() }
        .accessibilityIdentifier("access.memory")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            Label("Memory You Own", systemImage: "brain")
                .font(ManifoldType.title)
            Spacer()
            Button {
                Task { await store.personalDataOS.loadMemory() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("access.memory.refresh")
        }
    }

    private var memoryControls: some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.s5, verticalSpacing: Spacing.s3) {
            GridRow {
                settingLabel("Session default")
                Toggle("Amnesiac sessions", isOn: amnesiacMode)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("access.memory.amnesiac")
            }
            GridRow {
                settingLabel("Retention")
                Stepper("\(store.personalDataOS.memorySettings.derivedRetentionDays) days", value: derivedRetentionDays, in: 1...365)
                    .frame(width: 180, alignment: .leading)
                    .accessibilityIdentifier("access.memory.retention")
            }
        }
        .padding(Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }

    private var amnesiacMode: Binding<Bool> {
        Binding(
            get: { store.personalDataOS.memorySettings.amnesiacMode },
            set: { value in
                Task { await store.personalDataOS.updateMemorySettings(amnesiacMode: value) }
            }
        )
    }

    private var derivedRetentionDays: Binding<Int> {
        Binding(
            get: { store.personalDataOS.memorySettings.derivedRetentionDays },
            set: { value in
                Task { await store.personalDataOS.updateMemorySettings(derivedRetentionDays: value) }
            }
        )
    }

    private var memorySummary: some View {
        HStack(spacing: Spacing.s3) {
            MemoryStatTile(
                title: "Active",
                value: "\(store.personalDataOS.activeMemoryCount)",
                systemImage: "checkmark.circle",
                variant: .defaultScope
            )
            MemoryStatTile(
                title: "Hidden",
                value: "\(store.personalDataOS.hiddenMemoryCount)",
                systemImage: "eye.slash",
                variant: .neutral
            )
            MemoryStatTile(
                title: "Sources",
                value: "\(store.personalDataOS.memorySources.count)",
                systemImage: "folder",
                variant: .scope
            )
        }
        .accessibilityIdentifier("access.memory.summary")
    }

    @ViewBuilder
    private var sourceSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label("Lineage", systemImage: "point.3.connected.trianglepath.dotted")
                .font(ManifoldType.bodyMedium)

            if store.personalDataOS.memorySources.isEmpty {
                Text("No memory has source lineage yet.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("access.memory.sources.empty")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.s3)],
                    alignment: .leading,
                    spacing: Spacing.s3
                ) {
                    ForEach(store.personalDataOS.memorySources) { summary in
                        MemorySourceCard(summary: summary, sourceName: sourceName(summary.sourceID))
                            .accessibilityIdentifier("access.memory.source.\(summary.sourceID)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var memoryList: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label("Items", systemImage: "tray.full")
                .font(ManifoldType.bodyMedium)

            if store.personalDataOS.isLoadingMemory {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if store.personalDataOS.memoryItems.isEmpty {
                EmptyStateIllustration(
                    systemImage: "brain",
                    title: "No owned memory yet",
                    subtitle: "Session notes and derived summaries appear here after an agent saves memory through Manifold."
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s6)
                .accessibilityIdentifier("access.memory.empty")
            } else {
                LazyVStack(alignment: .leading, spacing: Spacing.s2) {
                    ForEach(store.personalDataOS.memoryItems) { item in
                        MemoryItemRow(
                            item: item,
                            sourceNames: item.contributingSourceIDs.map(sourceName),
                            onForget: {
                                Task { await store.personalDataOS.forgetMemory(item) }
                            }
                        )
                        .accessibilityIdentifier("access.memory.item.\(item.memoryID)")
                    }
                }
            }
        }
    }

    private func sourceName(_ sourceID: String) -> String {
        store.sources.first { $0.sourceID == sourceID }?.displayName ?? sourceID
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(ManifoldType.body.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

private struct MemoryStatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let variant: Pill.Variant

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .foregroundStyle(variant.color)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                        .fill(variant.color.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(ManifoldType.title)
                    .monospacedDigit()
                Text(title)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}

private struct MemorySourceCard: View {
    let summary: MemorySourceSummary
    let sourceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(sourceName)
                .font(ManifoldType.bodyMedium)
                .lineLimit(1)
            HStack(spacing: Spacing.s2) {
                Pill(text: "\(summary.activeCount) active", variant: .defaultScope)
                if summary.tombstonedCount > 0 {
                    Pill(text: "\(summary.tombstonedCount) hidden", variant: .neutral)
                }
                if summary.deletedCount > 0 {
                    Pill(text: "\(summary.deletedCount) forgotten", variant: .attention)
                }
            }
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }
}

private struct MemoryItemRow: View {
    let item: MemoryItem
    let sourceNames: [String]
    let onForget: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: iconName)
                .frame(width: 28, height: 28)
                .foregroundStyle(statusVariant.color)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                        .fill(statusVariant.color.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(spacing: Spacing.s2) {
                    Text(item.title)
                        .font(ManifoldType.bodyMedium)
                        .lineLimit(1)
                    Pill(text: kindLabel, variant: .scope)
                    Pill(text: statusLabel, variant: statusVariant)
                    Spacer(minLength: 0)
                }

                Text(item.body)
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.text2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.s2) {
                    ForEach(sourceNames.prefix(3), id: \.self) { sourceName in
                        Pill(text: sourceName, variant: .neutral, systemImage: "folder")
                    }
                    if item.contributingSourceIDs.count > 3 {
                        Pill(text: "+\(item.contributingSourceIDs.count - 3)", variant: .neutral)
                    }
                    Text(relativeDate)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive, action: onForget) {
                Label("Forget", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(item.status == MemoryStatus.deletedByUser.rawValue)
            .accessibilityIdentifier("access.memory.forget.\(item.memoryID)")
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
        )
    }

    private var iconName: String {
        switch MemoryKind(rawValue: item.kind) {
        case .summary: return "text.alignleft"
        case .decision: return "checkmark.seal"
        case .evidence: return "quote.bubble"
        case .staleRisk: return "exclamationmark.triangle"
        case .routine: return "repeat"
        case .sourceSchema: return "tablecells"
        case .note, .none: return "note.text"
        }
    }

    private var kindLabel: String {
        item.kind.replacingOccurrences(of: "_", with: " ")
    }

    private var statusLabel: String {
        item.status.replacingOccurrences(of: "_", with: " ")
    }

    private var statusVariant: Pill.Variant {
        switch MemoryStatus(rawValue: item.status) {
        case .active: return .defaultScope
        case .hiddenByScope, .tombstonedByRevocation, .expiredByRetention: return .neutral
        case .deletedByUser: return .attention
        case nil: return .neutral
        }
    }

    private var relativeDate: String {
        let date = Date(timeIntervalSince1970: item.updatedAt)
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
