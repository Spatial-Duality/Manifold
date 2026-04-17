// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RulesView — top-level unified Rules surface.
//
// Three-pane layout: sidebar (filters) → rule list table → inspector.
// All rules live in a single `RuleStore` on the runtime; this view
// reads/writes through `RulesModel` via `AppRuntimeClient`.
//
// Per design principle 10: this replaces the Phase 11 preview surface.
// Edits here affect real enforcement (file-read gate in ManifoldBridge,
// email engine, agent tool gates).

import SwiftUI
import ManifoldKit

struct RulesView: View {
    @Environment(ManifoldStore.self) private var store
    @AppStorage("rules.inspectorVisible") private var inspectorVisible = true

    var body: some View {
        HStack(spacing: 0) {
            RulesSidebar(model: store.rules)
                .frame(width: 200)
                .background(ManifoldPalette.surface2)

            Divider()

            VStack(spacing: 0) {
                RulesToolbar(model: store.rules, inspectorVisible: $inspectorVisible)
                Divider()
                RuleListTable(model: store.rules)
            }

            if inspectorVisible {
                Divider()
                RuleInspector(model: store.rules)
                    .frame(width: 360)
                    .background(ManifoldPalette.surface2)
            }
        }
        .task {
            if store.rules.rules.isEmpty {
                await store.rules.load()
            }
        }
        .onChange(of: store.rules.selectedRuleID) { _, _ in
            store.rules.refreshPreview(for: store.rules.selectedRule, agent: store.rules.previewAgent)
        }
        .accessibilityIdentifier("ledger.surface.rules")
    }
}

// MARK: - Sidebar

private struct RulesSidebar: View {
    @Bindable var model: RulesModel

    var body: some View {
        List(selection: Binding(
            get: { model.filter },
            set: { model.filter = $0 ?? .all }
        )) {
            Section("Scope") {
                ForEach(RulesModel.Filter.allCases) { filter in
                    if case .scope = filter {
                        sidebarRow(for: filter)
                    } else if filter == .all {
                        sidebarRow(for: filter)
                    }
                }
            }

            Section("Source") {
                ForEach(RulesModel.Filter.allCases) { filter in
                    switch filter {
                    case .seeded, .userAuthored, .suggested:
                        sidebarRow(for: filter)
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(for filter: RulesModel.Filter) -> some View {
        Label(filter.title, systemImage: filter.symbol)
            .tag(filter)
            .badge(count(for: filter))
    }

    private func count(for filter: RulesModel.Filter) -> Int {
        switch filter {
        case .all: return model.rules.count
        case .scope(let s): return model.rules.filter { $0.scope == s }.count
        case .seeded: return model.rules.filter { $0.source == .seeded }.count
        case .userAuthored: return model.rules.filter { [.user, .userOverride, .imported].contains($0.source) }.count
        case .suggested: return model.rules.filter { $0.source == .suggested }.count
        }
    }
}

// MARK: - Toolbar

private struct RulesToolbar: View {
    @Bindable var model: RulesModel
    @Binding var inspectorVisible: Bool

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Menu {
                Button("New File Rule") {
                    Task { await model.addRule(RuleRecord.newUserFileRule()) }
                }
                Button("New Email Rule") {
                    Task { await model.addRule(RuleRecord.newUserEmailRule()) }
                }
                Button("New Agent Rule") {
                    Task { await model.addRule(RuleRecord.newUserAgentRule()) }
                }
            } label: {
                Label("New Rule", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 16)

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.attention)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            TextField("Search rules", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            Button {
                withAnimation(ManifoldMotion.micro) { inspectorVisible.toggle() }
            } label: {
                Image(systemName: inspectorVisible ? "sidebar.right" : "sidebar.right")
                    .foregroundStyle(inspectorVisible ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(inspectorVisible ? "Hide inspector" : "Show inspector")
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial)
    }
}
