// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Email policy — per-agent defaults and coarse sensitivity preset.
struct EmailPolicyView: View {
    @Bindable var rulesModel: EmailRulesModel
    let selectedAgent: TargetApp

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Email Policy")
                        .font(Typ.sectionTitle)
                        .accessibilityIdentifier("emailRules.policy.title")
                    Text("Set the coarse sensitivity preset and what happens when no specific email rule matches.")
                        .font(Typ.body)
                        .foregroundStyle(.secondary)
                }

                sensitivityCard(
                    agentName: selectedAgent == .codex ? "Codex" : "Claude",
                    color: selectedAgent == .codex ? .codexPurple : .claudeBlue,
                    sensitivity: Binding(
                        get: { rulesModel.emailSensitivity },
                        set: { newValue in
                            Task { await rulesModel.updateSensitivity(newValue) }
                        }
                    )
                )

                policyCard(
                    agentName: selectedAgent == .codex ? "Codex" : "Claude",
                    color: selectedAgent == .codex ? .codexPurple : .claudeBlue,
                    policy: Binding(
                        get: { rulesModel.defaultPolicy },
                        set: { newValue in
                            Task { await rulesModel.updateDefaultPolicy(newValue) }
                        }
                    )
                )

                // Warning
                if rulesModel.defaultPolicy == .blockUnlessAllowed {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.statusWarning)
                        Text("\(selectedAgent == .codex ? "Codex" : "Claude") won't see any emails unless you add allow rules above. This is high-security mode.")
                            .font(Typ.body)
                    }
                    .padding(12)
                    .background(Color.statusWarning.opacity(Opacity.badgeFill), in: RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                // Evaluation order explanation
                VStack(alignment: .leading, spacing: 8) {
                    Text("How Evaluation Works")
                        .font(Typ.heading)
                    Text("Manifold checks contact rules first, then keywords, then domains, then shields, then sensitivity. If none match, the default policy applies.")
                        .font(Typ.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .navigationTitle("Email Policy")
        .accessibilityIdentifier("emailRules.policy.screen")
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
                .accessibilityIdentifier("emailRules.policy.defaultPolicyPicker")

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

    private func sensitivityCard(
        agentName: String,
        color: Color,
        sensitivity: Binding<EmailSensitivityLevel>
    ) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)

            VStack(alignment: .leading, spacing: 10) {
                Text("\(agentName) Sensitivity")
                    .font(Typ.heading)

                Picker(selection: sensitivity) {
                    ForEach(EmailSensitivityLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("emailRules.policy.sensitivityPicker")

                Text(sensitivityDescription(for: sensitivity.wrappedValue))
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

    private func sensitivityDescription(for level: EmailSensitivityLevel) -> String {
        switch level {
        case .strict:
            return "Hide more potentially sensitive mail before the default policy is considered."
        case .moderate:
            return "Balance everyday access with protection for common sensitive categories."
        case .open:
            return "Rely mostly on shields and explicit rules; sensitivity blocks the least."
        }
    }
}
