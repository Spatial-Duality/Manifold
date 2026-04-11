import SwiftUI
import ManifoldKit

/// Email Rules container — NavigationSplitView with rules sidebar + detail.
/// Replaces the flat Domains tab with a layered rules engine.
struct EmailRulesView: View {
    @Environment(ManifoldStore.self) var store
    @State private var rulesModel = EmailRulesModel()
    @State private var selectedItem: RulesSidebarItem? = .dashboard

    enum RulesSidebarItem: Hashable {
        case dashboard
        case shield(String)
        case domains
        case contacts
        case keywords
        case defaults
    }

    var body: some View {
        NavigationSplitView {
            rulesSidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            switch selectedItem {
            case .dashboard, .none:
                RulesDashboardView(rulesModel: rulesModel)
            case .shield(let shieldID):
                if let idx = rulesModel.shields.firstIndex(where: { $0.id == shieldID }) {
                    ShieldDetailView(shield: $rulesModel.shields[idx])
                }
            case .domains:
                DomainRulesView(rulesModel: rulesModel)
            case .contacts:
                ContactRulesView(rulesModel: rulesModel)
            case .keywords:
                KeywordRulesView(rulesModel: rulesModel)
            case .defaults:
                DefaultPolicyView(rulesModel: rulesModel)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Rules Sidebar

    private var rulesSidebar: some View {
        List(selection: $selectedItem) {
            Section {
                Label("Dashboard", systemImage: "chart.bar")
                    .tag(RulesSidebarItem.dashboard)
            } header: {
                Text("Overview")
            }
            .headerProminence(.increased)

            Section {
                ForEach(rulesModel.shields) { shield in
                    HStack {
                        Label(shield.name, systemImage: shield.isEnabled ? "shield.fill" : "shield")
                            .foregroundStyle(shield.isEnabled ? .primary : .secondary)
                        Spacer()
                        Text(shield.isEnabled ? "\(shield.blockedCount)" : "off")
                            .font(Typ.numericCaption)
                            .foregroundStyle(.tertiary)
                    }
                    .tag(RulesSidebarItem.shield(shield.id))
                }
            } header: {
                let activeCount = rulesModel.shields.filter(\.isEnabled).count
                Text("Shields (\(activeCount) active)")
            }
            .headerProminence(.increased)

            Section {
                Label {
                    HStack {
                        Text("Domains")
                        Spacer()
                        Text("\(rulesModel.domainRules.count)")
                            .font(Typ.numericCaption)
                            .foregroundStyle(.tertiary)
                    }
                } icon: {
                    Image(systemName: "globe")
                }
                .tag(RulesSidebarItem.domains)

                Label {
                    HStack {
                        Text("Contacts")
                        Spacer()
                        Text("\(rulesModel.contactRules.count)")
                            .font(Typ.numericCaption)
                            .foregroundStyle(.tertiary)
                    }
                } icon: {
                    Image(systemName: "person")
                }
                .tag(RulesSidebarItem.contacts)

                Label {
                    HStack {
                        Text("Keywords")
                        Spacer()
                        Text("\(rulesModel.keywordRules.count)")
                            .font(Typ.numericCaption)
                            .foregroundStyle(.tertiary)
                    }
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
                .tag(RulesSidebarItem.keywords)
            } header: {
                Text("Rules")
            }
            .headerProminence(.increased)

            Section {
                Label("Defaults", systemImage: "gearshape")
                    .tag(RulesSidebarItem.defaults)
            } header: {
                Text("Policy")
            }
            .headerProminence(.increased)

            // Priority footer
            Section {
                Text("Priority: Contact \u{2192} Keyword \u{2192} Domain \u{2192} Shield \u{2192} Default")
                    .font(Typ.caption)
                    .foregroundStyle(.quaternary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Email Rules")
    }
}
