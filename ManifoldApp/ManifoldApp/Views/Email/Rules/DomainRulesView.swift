import SwiftUI
import ManifoldKit

/// Domain rules list — improved version of the old DomainsTableView.
struct DomainRulesView: View {
    @Bindable var rulesModel: EmailRulesModel
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 0) {
            if rulesModel.domainRules.isEmpty {
                ContentUnavailableView {
                    Label("No Domain Rules", systemImage: "globe")
                } description: {
                    Text("Domain rules control access by email sender domain. Add one to override shield defaults.")
                } actions: {
                    Button("Add Domain Rule") {}
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Table(rulesModel.domainRules) {
                    TableColumn("Domain") { rule in
                        HStack(spacing: 6) {
                            if rule.shieldOverlap != nil {
                                Image(systemName: "shield.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("@\(rule.domain)")
                                .font(domainFont(count: rule.emailCount))
                        }
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Category") { rule in
                        Text(rule.category)
                            .font(Typ.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(80)

                    TableColumn("Emails") { rule in
                        Text("\(rule.emailCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(60)

                    TableColumn("Rule") { rule in
                        StatusBadge(
                            text: rule.action.rawValue.capitalized,
                            color: rule.action == .allow ? .statusActive : .statusDanger
                        )
                    }
                    .width(70)

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
        .navigationTitle("Domain Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Domain", systemImage: "plus") {}
                    .controlSize(.small)
            }
        }
    }

    private func domainFont(count: Int) -> Font {
        if count >= 100 { return .callout.weight(.medium) }
        if count >= 10 { return .callout }
        return .caption
    }
}
