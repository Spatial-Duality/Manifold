import SwiftUI
import ManifoldKit

/// Contact rules with inline creation form.
struct ContactRulesView: View {
    @Bindable var rulesModel: EmailRulesModel
    let selectedAgent: TargetApp
    @State private var showAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            if showAddForm {
                AddContactRuleForm(isPresented: $showAddForm, rulesModel: rulesModel, selectedAgent: selectedAgent)
                Divider()
            }

            if rulesModel.contactRules.isEmpty && !showAddForm {
                ContentUnavailableView {
                    Label("No Contact Rules", systemImage: "person")
                } description: {
                    Text("Contact rules override domain rules and shields for specific senders. Add one when you need an exception.")
                } actions: {
                    Button("Add Contact Rule") {
                        withAnimation(Anim.structural) { showAddForm = true }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Table(rulesModel.contactRules) {
                    TableColumn("Name") { rule in Text(rule.name) }.width(min: 100, ideal: 150)
                    TableColumn("Email") { rule in Text(rule.email).font(Typ.mono) }.width(min: 120, ideal: 200)
                    TableColumn("Rule") { rule in
                        StatusBadge(text: rule.action.rawValue.capitalized,
                                    color: rule.action == .allow ? .statusActive : .statusDanger)
                    }.width(70)
                    TableColumn("Hits") { rule in
                        Text("\(rule.matchedCount)").monospacedDigit().foregroundStyle(.secondary)
                    }.width(60)
                    TableColumn("Overrides") { rule in
                        Text(rule.overridesDescription).font(Typ.caption).foregroundStyle(.secondary)
                    }.width(min: 100, ideal: 150)
                }
                .tableStyle(.inset)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first {
                        Button("Delete Rule", role: .destructive) {
                            Task { await rulesModel.removeContactRule(id: id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Contact Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Contact", systemImage: "plus") {
                    withAnimation(Anim.structural) { showAddForm.toggle() }
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Add Contact Rule Form

private struct AddContactRuleForm: View {
    @Binding var isPresented: Bool
    @Bindable var rulesModel: EmailRulesModel
    let selectedAgent: TargetApp

    @State private var name = ""
    @State private var email = ""
    @State private var action: RuleAction = .allow
    @FocusState private var nameFieldFocused: Bool

    private var isValid: Bool { email.contains("@") && email.contains(".") }
    private var emailDomain: String { email.split(separator: "@").last.map(String.init) ?? "" }

    private var previewText: String? {
        guard isValid else { return nil }
        let agentLabel = selectedAgent == .codex ? "Codex" : "Claude"
        let who = name.isEmpty ? email : name
        let domainNote = emailDomain.isEmpty ? "" : " \u{2014} overrides any @\(emailDomain) domain rule or shield"
        return action == .allow
            ? "Allow \(agentLabel) to see emails from \(who)\(domainNote)"
            : "Block \(agentLabel) from seeing emails from \(who)\(domainNote)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("New Contact Rule").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Close", systemImage: "xmark") { isPresented = false }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.tertiary)
            }

            Text("Contact rules are the most specific \u{2014} they override domain rules and shields for this sender.")
                .font(Typ.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Name (optional)").font(.caption).fontWeight(.semibold)
                    TextField("Sarah Jones", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                }
                .frame(minWidth: 140)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Email").font(.caption).fontWeight(.semibold)
                    TextField("sarah@bank.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { if isValid { addRule() } }
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Action").font(.caption).fontWeight(.semibold)
                    ActionSegmented(action: $action)
                }
            }

            RulePreviewStrip(text: previewText)
                .animation(Anim.entrance, value: previewText != nil)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button("Add Rule") { addRule() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.02))
        .onAppear { nameFieldFocused = true }
    }

    private func addRule() {
        Task {
            await rulesModel.addContactRule(
                name: name,
                email: email,
                action: action
            )
        }
        withAnimation(Anim.structural) { isPresented = false }
    }
}
