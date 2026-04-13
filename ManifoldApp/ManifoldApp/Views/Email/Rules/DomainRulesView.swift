import SwiftUI
import ManifoldKit

/// Domain rules list with inline creation form.
struct DomainRulesView: View {
    @Bindable var rulesModel: EmailRulesModel
    let selectedAgent: TargetApp
    @State private var showAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            // Inline creation form (expands above table)
            if showAddForm {
                AddDomainRuleForm(isPresented: $showAddForm, rulesModel: rulesModel, selectedAgent: selectedAgent)
                Divider()
            }

            if rulesModel.domainRules.isEmpty && !showAddForm {
                ContentUnavailableView {
                    Label("No Domain Rules", systemImage: "globe")
                } description: {
                    Text("Domain rules control access by email sender domain. Add one to override shield defaults.")
                } actions: {
                    Button("Add Domain Rule") {
                        withAnimation(Anim.structural) { showAddForm = true }
                    }
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
                        Text(rule.category).font(Typ.caption).foregroundStyle(.secondary)
                    }
                    .width(80)

                    TableColumn("Emails") { rule in
                        Text("\(rule.emailCount)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(60)

                    TableColumn("Hits") { rule in
                        Text("\(rule.matchedCount)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(60)

                    TableColumn("Rule") { rule in
                        StatusBadge(text: rule.action.rawValue.capitalized,
                                    color: rule.action == .allow ? .statusActive : .statusDanger)
                    }
                    .width(70)

                }
                .tableStyle(.inset)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first {
                        Button("Delete Rule", role: .destructive) {
                            Task { await rulesModel.removeDomainRule(id: id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Domain Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Domain", systemImage: "plus") {
                    withAnimation(Anim.structural) { showAddForm.toggle() }
                }
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

// MARK: - Add Domain Rule Form

private struct AddDomainRuleForm: View {
    @Binding var isPresented: Bool
    @Bindable var rulesModel: EmailRulesModel
    let selectedAgent: TargetApp

    @State private var domain = ""
    @State private var action: RuleAction = .block
    @State private var category = "Work"
    @FocusState private var domainFieldFocused: Bool

    private var cleanDomain: String {
        domain.replacing("@", with: "").trimmingCharacters(in: .whitespaces)
    }
    private var isValid: Bool { cleanDomain.contains(".") && cleanDomain.count > 2 }

    private var previewText: String? {
        guard isValid else { return nil }
        let agentLabel = selectedAgent == .codex ? "Codex" : "Claude"
        return action == .block
            ? "Block \(agentLabel) from seeing emails from @\(cleanDomain)"
            : "Allow \(agentLabel) to see emails from @\(cleanDomain)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("New Domain Rule").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Close", systemImage: "xmark") { isPresented = false }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Domain").font(.caption).fontWeight(.semibold)
                    HStack(spacing: 4) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("example.com", text: $domain)
                            .textFieldStyle(.plain)
                            .focused($domainFieldFocused)
                            .onSubmit { if isValid { addRule() } }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                        isValid ? Color.statusActive.opacity(0.4) :
                        domain.isEmpty ? Color.secondary.opacity(0.2) :
                        Color.statusDanger.opacity(0.3), lineWidth: 1
                    ))
                    Text("Use *.domain.com for subdomains")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Category").font(.caption).fontWeight(.semibold)
                    Picker("Category", selection: $category) {
                        ForEach(["Work", "Financial", "Automated", "Personal"], id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                }
                .frame(width: 120)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Action").font(.caption).fontWeight(.semibold)
                    ActionSegmented(action: $action)
                }
            }

            RulePreviewStrip(text: previewText)
                .animation(Anim.entrance, value: previewText != nil)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add Rule") { addRule() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.02))
        .onAppear { domainFieldFocused = true }
    }

    private func addRule() {
        Task {
            await rulesModel.addDomainRule(
                domain: cleanDomain,
                action: action,
                category: category
            )
        }
        withAnimation(Anim.structural) { isPresented = false }
    }
}
