import SwiftUI
import ManifoldKit

/// Email Rules container — NavigationSplitView with rules sidebar + detail.
/// Replaces the flat Domains tab with a layered rules engine.
struct EmailRulesView: View {
    @Environment(ManifoldStore.self) var store
    @State private var rulesModel = EmailRulesModel()
    @State private var selectedItem: RulesSidebarItem? = .dashboard
    @State private var selectedAgent: TargetApp = .cowork

    enum RulesSidebarItem: Hashable {
        case dashboard
        case shield(String)
        case domains
        case contacts
        case keywords
        case policy
    }

    var body: some View {
        NavigationSplitView {
            rulesSidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                rulesHeader
                Divider()
                Group {
                    switch selectedItem {
                    case .dashboard, .none:
                        RulesDashboardView(rulesModel: rulesModel, selectedAgent: selectedAgent)
                    case .shield(let shieldID):
                        if let shield = rulesModel.shields.first(where: { $0.id == shieldID }) {
                            ShieldDetailView(shield: shield) { enabled in
                                Task { await rulesModel.toggleShield(shieldID: shieldID, isEnabled: enabled) }
                            }
                        }
                    case .domains:
                        DomainRulesView(rulesModel: rulesModel, selectedAgent: selectedAgent)
                    case .contacts:
                        ContactRulesView(rulesModel: rulesModel, selectedAgent: selectedAgent)
                    case .keywords:
                        KeywordRulesView(rulesModel: rulesModel, selectedAgent: selectedAgent)
                    case .policy:
                        EmailPolicyView(rulesModel: rulesModel, selectedAgent: selectedAgent)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            selectedAgent = store.agentFocus.targetApp
            rulesModel.configure(client: store.runtime)
            await rulesModel.load(agent: selectedAgent)
        }
        .task(id: selectedAgent) {
            await rulesModel.load(agent: selectedAgent)
        }
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
                Label("Policy", systemImage: "gearshape")
                    .tag(RulesSidebarItem.policy)
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

    @ViewBuilder
    private var rulesHeader: some View {
        HStack(spacing: Spacing.standard) {
            Picker("Agent", selection: $selectedAgent) {
                Text("Claude").tag(TargetApp.cowork)
                Text("Codex").tag(TargetApp.codex)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            if let coverage = store.policy.coverage(for: selectedAgent) {
                StatusBadge(
                    text: coverage.coverageState.displayName,
                    color: coverage.coverageState == .trackedWorkspace ? .statusActive :
                        coverage.coverageState == .manifoldRouted ? .blue : .orange
                )
                StatusBadge(
                    text: coverage.verificationStatus.displayName,
                    color: coverage.verificationStatus == .verified ? .statusActive : .orange
                )
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.section)
        .padding(.vertical, 10)

        if let errorMessage = rulesModel.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.statusWarning)
                Text(errorMessage)
                    .font(Typ.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.section)
            .padding(.bottom, 10)
        }
    }
}
