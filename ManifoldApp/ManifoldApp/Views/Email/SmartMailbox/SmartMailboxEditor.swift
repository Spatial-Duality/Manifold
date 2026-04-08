import SwiftUI
import ManifoldKit

/// Editor for creating/editing smart mailbox rules.
struct SmartMailboxEditor: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String = ""
    @State private var iconName: String = "tray"
    @State private var matchType: SmartMailboxRules.MatchType = .all
    @State private var conditions: [EditableCondition] = []

    /// If set, editing an existing smart mailbox.
    var existingMailbox: SmartMailboxRecord?

    var body: some View {
        VStack(spacing: Spacing.large) {
            Text(existingMailbox != nil ? "Edit Smart Mailbox" : "New Smart Mailbox")
                .font(.title3.weight(.semibold))

            Form {
                TextField("Name", text: $displayName)

                Picker("Match", selection: $matchType) {
                    Text("All conditions").tag(SmartMailboxRules.MatchType.all)
                    Text("Any condition").tag(SmartMailboxRules.MatchType.any)
                }

                Section("Conditions") {
                    ForEach($conditions) { $condition in
                        ConditionRow(condition: $condition, onRemove: {
                            conditions.removeAll { $0.id == condition.id }
                        })
                    }

                    Button {
                        conditions.append(EditableCondition())
                    } label: {
                        Label("Add Condition", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .glassButton()
                    .keyboardShortcut(.cancelAction)
                Button(existingMailbox != nil ? "Save" : "Create") {
                    save()
                }
                .glassProminentButton()
                .disabled(displayName.isEmpty || conditions.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.large)
        .frame(width: 400)
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let mb = existingMailbox else { return }
        displayName = mb.displayName
        iconName = mb.iconName
        if let rules = mb.rules {
            matchType = rules.match
            conditions = rules.conditions.map { EditableCondition(field: $0.field, op: $0.op, value: $0.value) }
        }
    }

    private func save() {
        let ruleConditions = conditions.compactMap { c -> RuleCondition? in
            guard !c.field.isEmpty, !c.value.isEmpty else { return nil }
            return RuleCondition(field: c.field, op: c.op, value: c.value)
        }
        guard !ruleConditions.isEmpty else { return }
        let rules = SmartMailboxRules(match: matchType, conditions: ruleConditions)
        guard let json = rules.toJSON() else { return }

        Task {
            if let existing = existingMailbox {
                try? await store.emailAccounts.updateSmartMailbox(
                    mailboxID: existing.mailboxID,
                    displayName: displayName,
                    iconName: iconName,
                    rulesJSON: json
                )
            } else {
                try? await store.emailAccounts.createSmartMailbox(
                    displayName: displayName,
                    iconName: iconName,
                    rulesJSON: json
                )
            }
            dismiss()
        }
    }
}

// MARK: - Editable Condition

struct EditableCondition: Identifiable {
    let id = UUID()
    var field: String = "sender"
    var op: RuleCondition.RuleOperator = .contains
    var value: String = ""
}

// MARK: - Condition Row

private struct ConditionRow: View {
    @Binding var condition: EditableCondition
    let onRemove: () -> Void

    private static let fieldOptions: [(label: String, value: String)] = [
        ("From", "sender_email"),
        ("Subject", "subject"),
        ("Body", "body_text"),
        ("To", "recipients"),
        ("CC", "cc"),
        ("Domain", "sender_domain"),
        ("Mailbox", "mailbox"),
        ("Date", "received_at"),
        ("Is Read", "is_read"),
        ("Is Flagged", "is_flagged"),
        ("Is Junk", "is_junk"),
        ("Attachments", "attachment_count"),
        ("Size", "size_bytes"),
    ]

    var body: some View {
        HStack(spacing: Spacing.standard) {
            // Field picker
            Picker("Field", selection: $condition.field) {
                ForEach(Self.fieldOptions, id: \.value) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .labelsHidden()
            .frame(width: 100)

            // Operator picker (context-dependent)
            Picker("Operator", selection: $condition.op) {
                ForEach(operatorsForField, id: \.self) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .labelsHidden()
            .frame(width: 100)

            // Value input (field-dependent)
            valueInput
                .frame(maxWidth: .infinity)

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .onChange(of: condition.field) { _, _ in
            // Reset operator when field changes
            let valid = operatorsForField
            if !valid.contains(condition.op), let first = valid.first {
                condition.op = first
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rule: \(condition.field) \(condition.op.displayName) \(condition.value)")
    }

    private var fieldType: RuleCondition.FieldType {
        RuleCondition.fieldType(for: condition.field)
    }

    private var operatorsForField: [RuleCondition.RuleOperator] {
        RuleCondition.operators(for: condition.field)
    }

    @ViewBuilder
    private var valueInput: some View {
        switch fieldType {
        case .boolean:
            Picker("Value", selection: $condition.value) {
                Text("Yes").tag("1")
                Text("No").tag("0")
            }
            .labelsHidden()
        case .date:
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
        case .numeric:
            TextField("Value", text: $condition.value)
                .textFieldStyle(.roundedBorder)
        case .string, .enumeration:
            TextField("Value", text: $condition.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]
                return iso.date(from: condition.value) ?? Date()
            },
            set: { newDate in
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]
                condition.value = iso.string(from: newDate)
            }
        )
    }
}

// MARK: - Operator Display Name

extension RuleCondition.RuleOperator {
    var displayName: String {
        switch self {
        case .contains: "contains"
        case .notContains: "doesn't contain"
        case .equals: "is"
        case .notEquals: "is not"
        case .greaterThan: "greater than"
        case .lessThan: "less than"
        case .after: "after"
        case .before: "before"
        case .between: "between"
        }
    }
}
