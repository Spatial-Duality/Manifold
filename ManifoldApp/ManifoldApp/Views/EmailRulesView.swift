import SwiftUI
import ManifoldKit

struct EmailRulesView: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var showAddRule = false
    @State private var newRuleType: RuleType = .domain
    @State private var newRulePattern = ""
    @State private var newRuleCategory = ""

    private var groupedRules: [(String, [EmailRule])] {
        let grouped = Dictionary(grouping: store.emailRules) { $0.category ?? "Other" }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.emailRules.isEmpty {
                ContentUnavailableView(
                    "No Custom Rules",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Default rules for banking, 2FA, and healthcare are built in. Add custom rules below.")
                )
            } else {
                List {
                    ForEach(groupedRules, id: \.0) { category, rules in
                        Section(category) {
                            ForEach(rules, id: \.id) { rule in
                                HStack(spacing: 8) {
                                    Image(systemName: ruleIcon(rule.ruleType))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    Text(rule.pattern)
                                        .font(.callout.monospaced())
                                    Spacer()
                                    Text(rule.ruleType.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await store.removeEmailRule(id: rule.id) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Add rule form
            VStack(spacing: 8) {
                HStack {
                    Picker("Type", selection: $newRuleType) {
                        Text("Domain").tag(RuleType.domain)
                        Text("Sender").tag(RuleType.sender)
                        Text("Keyword").tag(RuleType.keyword)
                    }
                    .frame(width: 150)

                    TextField("Pattern (e.g. example.com)", text: $newRulePattern)
                        .textFieldStyle(.roundedBorder)

                    TextField("Category", text: $newRuleCategory)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)

                    Button("Add") {
                        guard !newRulePattern.isEmpty else { return }
                        Task {
                            await store.addEmailRule(
                                type: newRuleType,
                                pattern: newRulePattern,
                                category: newRuleCategory.isEmpty ? "Custom" : newRuleCategory
                            )
                            newRulePattern = ""
                            newRuleCategory = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newRulePattern.isEmpty)
                }
            }
            .padding()
        }
    }

    private func ruleIcon(_ type: RuleType) -> String {
        switch type {
        case .domain: return "globe"
        case .sender: return "person"
        case .keyword: return "textformat"
        }
    }
}
