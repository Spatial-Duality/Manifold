// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// NewRuleSheet — object-builder for adding a rule.
//
// The user picks a *kind* of subject from a short, concrete menu
// (Name ends with…, Path contains…, From sender…, Contains credit
// card numbers, …). The kind drives a second-level value field and
// maps to the underlying glob/predicate pattern — the pattern is
// never the first UI the user sees.
//
// Advanced disclosure reveals the raw pattern for power users who
// want to hand-edit. The live blast-radius preview is an honest
// placeholder until the rule evaluator is wired to `PolicyStore`
// and source enumeration (Principle 10 — no fake state).

import SwiftUI
import ManifoldKit

struct NewRuleSheet: View {
    @Environment(\.dismiss) private var dismiss

    let domain: Rule.Domain
    let onCommit: (Rule) -> Void

    @State private var verb: Rule.Verb = .deny
    @State private var subjectKind: SubjectKind
    @State private var subjectValue: String = ""
    @State private var objectScope: String = ""
    @State private var advanced = false
    @State private var patternOverride: String = ""

    init(domain: Rule.Domain, onCommit: @escaping (Rule) -> Void) {
        self.domain = domain
        self.onCommit = onCommit
        _subjectKind = State(initialValue: SubjectKind.defaults(for: domain).first ?? .nameEndsWith)
        _objectScope = State(initialValue: SubjectKind.defaultScope(for: domain))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            header

            Divider()

            // Verb
            FormRow(label: "Verb") {
                Picker("", selection: $verb) {
                    Text("Deny").tag(Rule.Verb.deny)
                    Text("Allow").tag(Rule.Verb.allow)
                    Text("Warn").tag(Rule.Verb.warn)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            // Subject kind
            FormRow(label: "Subject") {
                Picker("", selection: $subjectKind) {
                    ForEach(SubjectKind.defaults(for: domain), id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                .fixedSize()

                if subjectKind.takesValue {
                    TextField(subjectKind.placeholder, text: $subjectValue)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Object scope
            FormRow(label: "Scope") {
                TextField(SubjectKind.defaultScope(for: domain), text: $objectScope)
                    .textFieldStyle(.roundedBorder)
            }

            // Advanced
            Toggle("Advanced (raw pattern)", isOn: $advanced)
                .font(ManifoldType.captionMedium)
                .toggleStyle(.switch)
                .controlSize(.small)

            if advanced {
                FormRow(label: "Pattern") {
                    TextField(derivedPattern, text: $patternOverride)
                        .textFieldStyle(.roundedBorder)
                        .font(ManifoldType.mono)
                        .autocorrectionDisabled()
                }
            }

            // Honest placeholder preview
            LiveMatchPreview()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add rule") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(Spacing.s5)
        .frame(width: 540)
    }

    private var header: some View {
        HStack {
            Text("New rule · \(domain.rawValue.capitalized)")
                .font(ManifoldType.heading)
            Spacer()
        }
    }

    /// Pattern derived from the subject kind + value, unless the user
    /// has opened Advanced and typed a raw override.
    private var derivedPattern: String {
        subjectKind.pattern(for: subjectValue)
    }

    private var effectivePattern: String {
        if advanced, !patternOverride.isEmpty { return patternOverride }
        return derivedPattern
    }

    /// Human-readable subject sentence that reads as the rule card will.
    private var derivedSubject: String {
        subjectKind.sentence(for: subjectValue)
    }

    private var isValid: Bool {
        if advanced, !patternOverride.isEmpty { return true }
        if subjectKind.takesValue { return !subjectValue.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private func commit() {
        let rule = Rule(
            id: "user-\(UUID().uuidString.prefix(8))",
            domain: domain,
            verb: verb,
            subject: derivedSubject,
            object: objectScope.isEmpty ? SubjectKind.defaultScope(for: domain) : objectScope,
            pattern: effectivePattern,
            enabled: true,
            seeded: false,
            createdBy: .user,
            createdAt: Date()
        )
        onCommit(rule)
    }
}

// MARK: - Form row primitive

private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Text(label)
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content()
        }
    }
}

// MARK: - Subject kinds (object builder)

/// A concrete kind of subject the rule applies to. Each kind hides a
/// specific pattern shape so the user never has to write regex unless
/// they explicitly open Advanced.
enum SubjectKind: Hashable {
    // Files
    case nameEndsWith         // *.env
    case pathContains         // secrets/
    case fileGlob             // **/*.secret

    // Email
    case fromSender           // newsletters@*
    case subjectContains      // "invoice"
    case containsCreditCard
    case containsSSN
    case containsAPIKey

    // Agents
    case anyAgent

    var label: String {
        switch self {
        case .nameEndsWith:       return "Name ends with"
        case .pathContains:       return "Path contains"
        case .fileGlob:           return "File glob"
        case .fromSender:         return "From sender"
        case .subjectContains:    return "Subject contains"
        case .containsCreditCard: return "Contains credit card numbers"
        case .containsSSN:        return "Contains Social Security numbers"
        case .containsAPIKey:     return "Contains an API key"
        case .anyAgent:           return "Any agent"
        }
    }

    var placeholder: String {
        switch self {
        case .nameEndsWith:    return ".env"
        case .pathContains:    return "secrets/"
        case .fileGlob:        return "**/*.secret"
        case .fromSender:      return "newsletters@*"
        case .subjectContains: return "invoice"
        default:               return ""
        }
    }

    /// Whether this kind needs a secondary value field.
    var takesValue: Bool {
        switch self {
        case .containsCreditCard, .containsSSN, .containsAPIKey, .anyAgent:
            return false
        default:
            return true
        }
    }

    /// Translate kind + user value into the underlying pattern.
    func pattern(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        switch self {
        case .nameEndsWith:
            // "*.env" or just "env" → **/*.<rest>
            let tail = trimmed.hasPrefix("*") ? trimmed : (trimmed.hasPrefix(".") ? "*\(trimmed)" : "*.\(trimmed)")
            return "**/\(tail)"
        case .pathContains:
            return "**/\(trimmed)/**"
        case .fileGlob:
            return trimmed
        case .fromSender:
            return "from:\(trimmed)"
        case .subjectContains:
            return "subject:\(trimmed)"
        case .containsCreditCard:
            return "body:/\\b\\d{13,19}\\b/"
        case .containsSSN:
            return "body:/\\b\\d{3}-\\d{2}-\\d{4}\\b/"
        case .containsAPIKey:
            return "body:/(?i)(sk_|api[_-]?key|bearer)\\s*[:=]\\s*[A-Za-z0-9_\\-]{16,}/"
        case .anyAgent:
            return "agent:*"
        }
    }

    /// Readable subject sentence for use in `Rule.subject`.
    func sentence(for value: String) -> String {
        let v = value.trimmingCharacters(in: .whitespaces)
        switch self {
        case .nameEndsWith:
            return "files whose name ends with \(v.isEmpty ? "…" : v)"
        case .pathContains:
            return "files whose path contains \(v.isEmpty ? "…" : v)"
        case .fileGlob:
            return "files matching \(v.isEmpty ? "…" : v)"
        case .fromSender:
            return "messages from \(v.isEmpty ? "…" : v)"
        case .subjectContains:
            return "messages whose subject contains \(v.isEmpty ? "…" : v)"
        case .containsCreditCard:
            return "messages containing credit card numbers"
        case .containsSSN:
            return "messages containing Social Security numbers"
        case .containsAPIKey:
            return "messages containing an API key"
        case .anyAgent:
            return "any agent"
        }
    }

    static func defaults(for domain: Rule.Domain) -> [SubjectKind] {
        switch domain {
        case .files:
            return [.nameEndsWith, .pathContains, .fileGlob]
        case .email:
            return [.fromSender, .subjectContains, .containsCreditCard, .containsSSN, .containsAPIKey]
        case .agents:
            return [.anyAgent]
        }
    }

    static func defaultScope(for domain: Rule.Domain) -> String {
        switch domain {
        case .files:  return "anywhere"
        case .email:  return "any mailbox"
        case .agents: return "always"
        }
    }
}

// MARK: - Honest live preview placeholder

struct LiveMatchPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "bolt.slash")
                    .foregroundStyle(.tertiary)
                Text("Live preview not available")
                    .font(ManifoldType.bodyMedium)
                    .foregroundStyle(.secondary)
            }
            Text("A blast-radius preview will appear here once the rule evaluator is wired to PolicyStore and source enumeration.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(ManifoldPalette.surface3.opacity(0.5))
        )
    }
}
