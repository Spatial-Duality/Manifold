import SwiftUI
import ManifoldKit

/// Keyword rules with inline creation form.
struct KeywordRulesView: View {
    @Bindable var rulesModel: EmailRulesModel
    let selectedAgent: TargetApp
    @State private var showAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            if showAddForm {
                AddKeywordRuleForm(isPresented: $showAddForm, rulesModel: rulesModel, selectedAgent: selectedAgent)
                Divider()
            }

            if rulesModel.keywordRules.isEmpty && !showAddForm {
                ContentUnavailableView {
                    Label("No Keyword Rules", systemImage: "magnifyingglass")
                } description: {
                    Text("Keyword rules catch emails containing specific text patterns, regardless of sender or domain.")
                } actions: {
                    Button("Add Pattern") {
                        withAnimation(Anim.structural) { showAddForm = true }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Table(rulesModel.keywordRules) {
                    TableColumn("Pattern") { rule in
                        HStack(spacing: 6) {
                            Text("\"\(rule.pattern)\"").font(Typ.mono)
                            if rule.isRegex {
                                Text("REGEX")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(.purple.opacity(Opacity.badgeFill), in: Capsule())
                                    .foregroundStyle(.purple)
                            }
                        }
                    }.width(min: 140, ideal: 200)

                    TableColumn("Match In") { rule in
                        Text(rule.matchLocation.rawValue).font(Typ.caption)
                    }.width(100)

                    TableColumn("Rule") { rule in
                        StatusBadge(text: rule.action.rawValue.capitalized,
                                    color: rule.action == .allow ? .statusActive : .statusDanger)
                    }.width(70)

                    TableColumn("Matched") { rule in
                        Text("\(rule.matchedCount)").monospacedDigit().foregroundStyle(.secondary)
                    }.width(60)

                }
                .tableStyle(.inset)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first {
                        Button("Delete Rule", role: .destructive) {
                            Task { await rulesModel.removeKeywordRule(id: id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Keyword Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Pattern", systemImage: "plus") {
                    withAnimation(Anim.structural) { showAddForm.toggle() }
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Add Keyword Rule Form

private struct AddKeywordRuleForm: View {
    @Binding var isPresented: Bool
    @Bindable var rulesModel: EmailRulesModel
    let selectedAgent: TargetApp

    @State private var pattern = ""
    @State private var matchIn: KeywordMatchLocation = .subjectAndBody
    @State private var action: RuleAction = .block
    @State private var isRegex = false
    @FocusState private var patternFieldFocused: Bool

    private var isValid: Bool { !pattern.trimmingCharacters(in: .whitespaces).isEmpty }

    private var previewText: String? {
        guard isValid else { return nil }
        let agentLabel = selectedAgent == .codex ? "Codex" : "Claude"
        let location = matchIn == .subject ? "in subject lines" :
            matchIn == .subjectAndBody ? "in subjects and bodies" : "anywhere"
        let regexNote = isRegex ? " (regex pattern)" : ""
        return "\(action == .block ? "Block" : "Allow") emails containing \"\(pattern)\" \(location) for \(agentLabel)\(regexNote)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("New Keyword Rule").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Close", systemImage: "xmark") { isPresented = false }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Pattern").font(.caption).fontWeight(.semibold)
                        Toggle(isOn: $isRegex) {
                            Text("REGEX")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.purple.opacity(isRegex ? Opacity.badgeFill : 0.04), in: Capsule())
                                .foregroundStyle(isRegex ? .purple : .secondary)
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                    }
                    TextField(
                        isRegex ? "SSN|social\\\\s+security" : "confidential",
                        text: $pattern
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(isRegex ? .system(.body, design: .monospaced) : .body)
                    .focused($patternFieldFocused)
                    .onSubmit { if isValid { addRule() } }
                    Text(isRegex ? "Use | for alternation, \\b for word boundaries" : "Case-insensitive text match")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Match In").font(.caption).fontWeight(.semibold)
                    Picker("Match In", selection: $matchIn) {
                        ForEach(KeywordMatchLocation.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(width: 140)

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
        .onAppear { patternFieldFocused = true }
    }

    private func addRule() {
        Task {
            await rulesModel.addKeywordRule(
                pattern: pattern.trimmingCharacters(in: .whitespaces),
                matchLocation: matchIn,
                action: action,
                isRegex: isRegex
            )
        }
        withAnimation(Anim.structural) { isPresented = false }
    }
}
