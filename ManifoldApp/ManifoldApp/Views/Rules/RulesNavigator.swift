// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct RulesNavigator: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        List(selection: filterSelection) {
            Section("Scope") {
                rulesRow(.all)
                ForEach(RulesModel.Filter.allCases.filter { filter in
                    if case .scope = filter { return true }
                    return false
                }) { filter in
                    rulesRow(filter)
                }
            }

            Section("Model") {
                rulesRow(.privacy)
            }

            Section("Source") {
                rulesRow(.seeded)
                rulesRow(.userAuthored)
                rulesRow(.suggested)
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("rules.sidebar")
    }

    private var filterSelection: Binding<RulesModel.Filter?> {
        Binding(
            get: { store.rules.filter },
            set: { filter in
                guard let filter else { return }
                store.rules.selectFilter(filter)
            }
        )
    }

    private func rulesRow(_ filter: RulesModel.Filter) -> some View {
        Label(filter.title, systemImage: filter.symbol)
            .badge(count(for: filter))
        .tag(filter)
        .accessibilityLabel("\(filter.title), \(count(for: filter)) rules")
        .accessibilityIdentifier("rules.sidebar.\(filter.id)")
    }

    private func count(for filter: RulesModel.Filter) -> Int {
        switch filter {
        case .all:
            return store.rules.rules.count
        case .privacy:
            return store.rules.rules.filter(\.isPrivacyFilterBacked).count
        case .scope(let scope):
            return store.rules.rules.filter { $0.scope == scope }.count
        case .seeded:
            return store.rules.rules.filter { $0.source == .seeded }.count
        case .userAuthored:
            return store.rules.rules.filter { [.user, .userOverride, .imported].contains($0.source) }.count
        case .suggested:
            return store.rules.rules.filter { $0.source == .suggested }.count
        }
    }
}
