// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

// MARK: - Agent Checkbox Selector

/// Colored checkbox row for selecting which agents a rule applies to.
struct AgentCheckboxSelector: View {
    @Binding var selectedAgents: Set<TargetApp>

    var body: some View {
        HStack(spacing: 10) {
            agentCheckbox(.cowork, "Claude", Color.claudeBlue)
            agentCheckbox(.codex, "Codex", Color.codexPurple)

            Button("Both") {
                selectedAgents = [.cowork, .codex]
            }
            .font(.caption)
            .foregroundStyle(selectedAgents.count == 2 ? .primary : .tertiary)
            .buttonStyle(.plain)
        }
    }

    private func agentCheckbox(_ agent: TargetApp, _ label: String, _ color: Color) -> some View {
        let isOn = selectedAgents.contains(agent)
        return Button {
            if isOn && selectedAgents.count > 1 {
                selectedAgents.remove(agent)
            } else if !isOn {
                selectedAgents.insert(agent)
            }
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? color : Color.clear)
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 16, height: 16)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Segmented

/// Allow / Block segmented picker for rule actions.
struct ActionSegmented: View {
    @Binding var action: RuleAction

    var body: some View {
        Picker(selection: $action) {
            Text("Allow")
                .foregroundStyle(action == .allow ? Color.statusActive : .primary)
                .tag(RuleAction.allow)
            Text("Block")
                .foregroundStyle(action == .block ? Color.statusDanger : .primary)
                .tag(RuleAction.block)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .frame(width: 140)
    }
}

// MARK: - Rule Preview Strip

/// Green-tinted preview strip showing the plain-English effect of a rule.
struct RulePreviewStrip: View {
    let text: String?

    var body: some View {
        if let text {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.statusActive)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.24))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.statusActive.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.statusActive.opacity(0.2), lineWidth: 1))
        }
    }
}

// MARK: - Share Popover

/// Unified sharing popover for files, folders, and emails.
/// Shows both agent toggles, summary, and change preview.
struct SharePopover: View {
    let itemType: String
    let itemLabel: String
    let initialClaude: Bool
    let initialCodex: Bool
    let onApply: (Bool, Bool) -> Void

    @State private var isPresented = false
    @State private var claude: Bool
    @State private var codex: Bool

    init(itemType: String, itemLabel: String, claude: Bool, codex: Bool, onApply: @escaping (Bool, Bool) -> Void) {
        self.itemType = itemType
        self.itemLabel = itemLabel
        self.initialClaude = claude
        self.initialCodex = codex
        self.onApply = onApply
        _claude = State(initialValue: claude)
        _codex = State(initialValue: codex)
    }

    private var hasChanges: Bool {
        claude != initialClaude || codex != initialCodex
    }

    private var summary: String {
        if !claude && !codex { return "Not visible to any agent" }
        let names = [claude ? "Claude" : nil, codex ? "Codex" : nil].compactMap { $0 }
        return "Visible to \(names.joined(separator: " and "))"
    }

    private var changeDescription: String? {
        guard hasChanges else { return nil }
        var parts: [String] = []
        if claude != initialClaude {
            parts.append(claude ? "share with Claude" : "unshare from Claude")
        }
        if codex != initialCodex {
            parts.append(codex ? "share with Codex" : "unshare from Codex")
        }
        return "Will " + parts.joined(separator: " and ")
    }

    var body: some View {
        Button("Share\u{2026}", systemImage: "shield") {
            isPresented = true
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                HStack {
                    Text("Share \(itemLabel)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Close", systemImage: "xmark") { isPresented = false }
                        .labelStyle(.iconOnly)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)

                Divider()

                VStack(spacing: 0) {
                    agentRow("Claude", Color.claudeBlue, $claude)
                    agentRow("Codex", Color.codexPurple, $codex)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.04))

                if let change = changeDescription {
                    Text(change)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.18, green: 0.43, blue: 0.24))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.statusActive.opacity(0.06))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                    Button("Apply") {
                        onApply(claude, codex)
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .frame(width: 280)
            .animation(Anim.entrance, value: changeDescription)
        }
    }

    private func agentRow(_ name: String, _ color: Color, _ isOn: Binding<Bool>) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.callout).fontWeight(.medium)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(color)
                .labelsHidden()
        }
        .padding(.vertical, 6)
    }
}
