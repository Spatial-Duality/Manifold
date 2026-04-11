import SwiftUI
import ManifoldKit

/// Keyword rules — content-based pattern matching regardless of sender or domain.
struct KeywordRulesView: View {
    @Bindable var rulesModel: EmailRulesModel

    var body: some View {
        VStack(spacing: 0) {
            if rulesModel.keywordRules.isEmpty {
                ContentUnavailableView {
                    Label("No Keyword Rules", systemImage: "magnifyingglass")
                } description: {
                    Text("Keyword rules catch emails containing specific text patterns, regardless of sender or domain.")
                } actions: {
                    Button("Add Pattern") {}
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Table(rulesModel.keywordRules) {
                    TableColumn("Pattern") { rule in
                        HStack(spacing: 6) {
                            Text("\"\(rule.pattern)\"")
                                .font(Typ.mono)
                            if rule.isRegex {
                                Text("REGEX")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.purple.opacity(Opacity.badgeFill), in: Capsule())
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                    .width(min: 140, ideal: 200)

                    TableColumn("Match In") { rule in
                        Text(rule.matchLocation.rawValue)
                            .font(Typ.caption)
                    }
                    .width(100)

                    TableColumn("Rule") { rule in
                        StatusBadge(
                            text: rule.action.rawValue.capitalized,
                            color: rule.action == .allow ? .statusActive : .statusDanger
                        )
                    }
                    .width(70)

                    TableColumn("Matched") { rule in
                        Text("\(rule.matchedCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(60)

                    TableColumn("Agents") { rule in
                        HStack(spacing: 4) {
                            ForEach(rule.agents, id: \.self) { agent in
                                Circle()
                                    .fill(Color.agent(agent))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                    .width(60)
                }
                .tableStyle(.inset)
            }
        }
        .navigationTitle("Keyword Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Pattern", systemImage: "plus") {}
                    .controlSize(.small)
            }
        }
    }
}
