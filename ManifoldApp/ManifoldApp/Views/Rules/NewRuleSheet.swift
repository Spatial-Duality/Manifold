// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// NewRuleSheet — subject/verb/object grammar builder for adding a rule.
//
// No regex by default. The subject picker is scoped to concrete
// affordances (file type, path prefix, sender, label). Advanced toggle
// reveals pattern-editor.

import SwiftUI
import ManifoldKit

struct NewRuleSheet: View {
    @Environment(\.dismiss) private var dismiss

    let domain: Rule.Domain
    let onCommit: (Rule) -> Void

    @State private var verb: Rule.Verb = .deny
    @State private var subject: String = "files matching"
    @State private var subjectValue: String = "*.env"
    @State private var objectScope: String = "anywhere"
    @State private var advanced = false
    @State private var pattern: String = "**/*.env"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack {
                Text("New rule · \(domain.rawValue.capitalized)")
                    .font(ManifoldType.heading)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            // Verb picker
            HStack(spacing: Spacing.s2) {
                Text("Verb").font(ManifoldType.captionMedium).frame(width: 72, alignment: .leading)
                Picker("", selection: $verb) {
                    Text("Deny").tag(Rule.Verb.deny)
                    Text("Allow").tag(Rule.Verb.allow)
                    Text("Warn").tag(Rule.Verb.warn)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Subject
            HStack(spacing: Spacing.s2) {
                Text("Subject").font(ManifoldType.captionMedium).frame(width: 72, alignment: .leading)
                TextField("files matching", text: $subject)
                    .textFieldStyle(.roundedBorder)
                TextField("*.env", text: $subjectValue)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: subjectValue) { _, v in pattern = "**/\(v)" }
            }

            // Object
            HStack(spacing: Spacing.s2) {
                Text("Scope").font(ManifoldType.captionMedium).frame(width: 72, alignment: .leading)
                TextField("anywhere", text: $objectScope)
                    .textFieldStyle(.roundedBorder)
            }

            // Advanced
            Toggle("Advanced (raw pattern)", isOn: $advanced)
                .font(ManifoldType.captionMedium)
            if advanced {
                TextField("glob or predicate", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(ManifoldType.mono)
            }

            // Live match preview
            LiveMatchPreview(pattern: pattern)

            Divider()

            HStack {
                Spacer()
                Button("Add rule") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.s5)
        .frame(width: 520)
    }

    private func commit() {
        let rule = Rule(
            id: "user-\(UUID().uuidString.prefix(8))",
            domain: domain,
            verb: verb,
            subject: "\(subject) \(subjectValue)",
            object: objectScope,
            pattern: pattern,
            enabled: true,
            seeded: false,
            createdBy: .user,
            createdAt: Date()
        )
        onCommit(rule)
    }
}

struct LiveMatchPreview: View {
    let pattern: String

    // Placeholder: surface count updates once ManifoldCommands wires to
    // the real rule evaluator + source enumeration.
    private var sampleCount: Int {
        max(0, pattern.count % 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(ManifoldPalette.attention)
                Text("\(sampleCount) file\(sampleCount == 1 ? "" : "s") match right now")
                    .font(ManifoldType.bodyMedium)
            }
            Text("Live blast-radius preview becomes authoritative once the rule evaluator is wired to PolicyStore + source enumeration.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(ManifoldPalette.attentionSoft)
        )
    }
}
