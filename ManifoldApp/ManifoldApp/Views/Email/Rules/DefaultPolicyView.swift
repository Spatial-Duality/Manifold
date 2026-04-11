import SwiftUI
import ManifoldKit

/// Default policy — per-agent allow/block default when no rule matches.
struct DefaultPolicyView: View {
    @Bindable var rulesModel: EmailRulesModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Default Policy")
                        .font(Typ.sectionTitle)
                    Text("When an email doesn't match any contact rule, keyword rule, domain rule, or shield, this default applies.")
                        .font(Typ.body)
                        .foregroundStyle(.secondary)
                }

                // Claude policy
                policyCard(
                    agentName: "Claude",
                    color: .claudeBlue,
                    policy: $rulesModel.claudeDefaultPolicy
                )

                // Codex policy
                policyCard(
                    agentName: "Codex",
                    color: .codexPurple,
                    policy: $rulesModel.codexDefaultPolicy
                )

                // Warning
                if rulesModel.claudeDefaultPolicy == .blockUnlessAllowed || rulesModel.codexDefaultPolicy == .blockUnlessAllowed {
                    let agents = [
                        rulesModel.claudeDefaultPolicy == .blockUnlessAllowed ? "Claude" : nil,
                        rulesModel.codexDefaultPolicy == .blockUnlessAllowed ? "Codex" : nil,
                    ].compactMap { $0 }

                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.statusWarning)
                        Text("\(agents.joined(separator: " and ")) won't see any emails unless you add allow rules above. This is high-security mode.")
                            .font(Typ.body)
                    }
                    .padding(12)
                    .background(Color.statusWarning.opacity(Opacity.badgeFill), in: RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                // Evaluation order explanation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Evaluation Order")
                        .font(Typ.heading)
                    Text("When an email arrives, Manifold checks Contact rules first (most specific), then Keywords, then Domains, then Shields. If none match, this default applies.")
                        .font(Typ.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .navigationTitle("Default Policy")
    }

    private func policyCard(agentName: String, color: Color, policy: Binding<AgentDefaultPolicy>) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)

            VStack(alignment: .leading, spacing: 10) {
                Text(agentName)
                    .font(Typ.heading)

                Picker(selection: policy) {
                    Text("Allow unless blocked").tag(AgentDefaultPolicy.allowUnlessBlocked)
                    Text("Block unless allowed").tag(AgentDefaultPolicy.blockUnlessAllowed)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)

                Text(policy.wrappedValue == .allowUnlessBlocked
                     ? "Agent sees all emails except those caught by shields and rules."
                     : "Agent sees nothing unless a rule explicitly allows it.")
                    .font(Typ.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}
