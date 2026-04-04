import SwiftUI
import ManifoldKit

struct EmailRulesView: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var newRuleType: RuleType = .domain
    @State private var newRulePattern = ""
    @State private var newRuleCategory = ""
    @State private var groupedRules: [(String, [EmailRule])] = []

    private func regroupRules() {
        groupedRules = Dictionary(grouping: store.emailRules) { $0.category ?? "Other" }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            if store.emailRules.isEmpty {
                Section {
                    Text("Default rules for banking, 2FA, and healthcare are built in. Add custom rules below.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groupedRules, id: \.0) { category, rules in
                    Section(category) {
                        ForEach(rules, id: \.id) { rule in
                            HStack(spacing: 8) {
                                Image(systemName: ruleIcon(rule.ruleType))
                                    .foregroundStyle(.secondary).frame(width: 16)
                                Text(rule.pattern).font(.callout.monospaced())
                                Spacer()
                                Text(rule.ruleType.rawValue).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await store.removeEmailRule(id: rule.id) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }

            // Add rule
            Section("Add Rule") {
                Picker("Type", selection: $newRuleType) {
                    Text("Domain").tag(RuleType.domain)
                    Text("Sender").tag(RuleType.sender)
                    Text("Keyword").tag(RuleType.keyword)
                }
                TextField("Pattern (e.g. example.com)", text: $newRulePattern)
                    .textFieldStyle(.roundedBorder)
                TextField("Category", text: $newRuleCategory)
                    .textFieldStyle(.roundedBorder)
                Button("Add Rule") {
                    guard !newRulePattern.isEmpty else { return }
                    Task {
                        await store.addEmailRule(
                            type: newRuleType,
                            pattern: newRulePattern,
                            category: newRuleCategory.isEmpty ? "Custom" : newRuleCategory
                        )
                        newRulePattern = ""; newRuleCategory = ""
                    }
                }
                .disabled(newRulePattern.isEmpty)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("Email Rules")
        .task { await store.loadEmailRules(); regroupRules() }
        .onChange(of: store.emailRules.count) { _, _ in regroupRules() }
    }

    private func ruleIcon(_ type: RuleType) -> String {
        switch type {
        case .domain: return "globe"
        case .sender: return "person"
        case .keyword: return "textformat"
        }
    }
}
