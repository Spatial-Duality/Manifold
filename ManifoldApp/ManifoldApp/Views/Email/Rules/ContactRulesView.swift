import SwiftUI
import ManifoldKit

/// Contact rules — override domain rules and shields for specific senders.
struct ContactRulesView: View {
    @Bindable var rulesModel: EmailRulesModel

    var body: some View {
        VStack(spacing: 0) {
            if rulesModel.contactRules.isEmpty {
                ContentUnavailableView {
                    Label("No Contact Rules", systemImage: "person")
                } description: {
                    Text("Contact rules override domain rules and shields for specific senders. Add one when you need an exception.")
                } actions: {
                    Button("Add Contact Rule") {}
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Table(rulesModel.contactRules) {
                    TableColumn("Name") { rule in
                        Text(rule.name)
                    }
                    .width(min: 100, ideal: 150)

                    TableColumn("Email") { rule in
                        Text(rule.email)
                            .font(Typ.mono)
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn("Rule") { rule in
                        StatusBadge(
                            text: rule.action.rawValue.capitalized,
                            color: rule.action == .allow ? .statusActive : .statusDanger
                        )
                    }
                    .width(70)

                    TableColumn("Overrides") { rule in
                        Text(rule.overridesDescription)
                            .font(Typ.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 100, ideal: 150)

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
        .navigationTitle("Contact Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Contact", systemImage: "plus") {}
                    .controlSize(.small)
            }
        }
    }
}
