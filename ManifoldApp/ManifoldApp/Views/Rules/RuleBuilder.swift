// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RuleBuilder — scope-aware, sentence-style matcher composer.
//
// v1 intentionally edits a single matcher leaf (no combinators in the UI).
// This keeps the model predictable: one rule = one condition. Combinator
// editing (AND/OR/NOT) is a v2 Advanced mode.

import SwiftUI
import ManifoldKit

struct RuleBuilder: View {
    let scope: RuleScope
    @Binding var matcher: RuleMatcher
    let isEditable: Bool

    var body: some View {
        switch scope {
        case .file:  FileBuilder(matcher: $matcher, isEditable: isEditable)
        case .email: EmailBuilder(matcher: $matcher, isEditable: isEditable)
        case .agent: AgentBuilder(matcher: $matcher, isEditable: isEditable)
        }
    }
}

// MARK: - File scope

private struct FileBuilder: View {
    @Binding var matcher: RuleMatcher
    let isEditable: Bool

    enum Kind: String, CaseIterable, Identifiable {
        case pathGlob, pathRegex, fileExtension, fileSizeOver, fileAgeOlderThan, fileHidden, fileBinary, fileSecretDetected, gitignored
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pathGlob:           return "Path matches glob"
            case .pathRegex:          return "Path matches regex"
            case .fileExtension:      return "File extension is"
            case .fileSizeOver:       return "File size over"
            case .fileAgeOlderThan:   return "File older than"
            case .fileHidden:         return "File is hidden"
            case .fileBinary:         return "File is binary"
            case .fileSecretDetected: return "Contains a detected secret"
            case .gitignored:         return "Listed in .gitignore"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Picker("Condition", selection: Binding(
                get: { currentKind() },
                set: { newKind in
                    matcher = defaultMatcher(for: newKind)
                }
            )) {
                ForEach(Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .disabled(!isEditable)

            parameterEditor
        }
    }

    @ViewBuilder
    private var parameterEditor: some View {
        switch matcher {
        case .pathGlob(let v):
            stringField("Glob pattern", placeholder: "**/*.env", value: v) { matcher = .pathGlob($0) }
        case .pathRegex(let v):
            stringField("Regex", placeholder: ".*\\.env$", value: v, mono: true) { matcher = .pathRegex($0) }
        case .fileExtension(let v):
            stringField("Extension", placeholder: "env", value: v) { matcher = .fileExtension($0) }
        case .fileSizeOver(let n):
            bytesField("Size threshold", value: n) { matcher = .fileSizeOver($0) }
        case .fileAgeOlderThan(let t):
            daysField("Days", value: t) { matcher = .fileAgeOlderThan($0) }
        case .fileHidden, .fileBinary, .fileSecretDetected, .gitignored:
            Text("This condition has no parameters.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        default:
            Text("Unsupported condition")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func currentKind() -> Kind {
        switch matcher {
        case .pathGlob:           return .pathGlob
        case .pathRegex:          return .pathRegex
        case .fileExtension:      return .fileExtension
        case .fileSizeOver:       return .fileSizeOver
        case .fileAgeOlderThan:   return .fileAgeOlderThan
        case .fileHidden:         return .fileHidden
        case .fileBinary:         return .fileBinary
        case .fileSecretDetected: return .fileSecretDetected
        case .gitignored:         return .gitignored
        default:                  return .pathGlob
        }
    }

    private func defaultMatcher(for kind: Kind) -> RuleMatcher {
        switch kind {
        case .pathGlob:           return .pathGlob("**/pattern")
        case .pathRegex:          return .pathRegex(".*pattern")
        case .fileExtension:      return .fileExtension("env")
        case .fileSizeOver:       return .fileSizeOver(50 * 1024 * 1024)
        case .fileAgeOlderThan:   return .fileAgeOlderThan(30 * 86_400)
        case .fileHidden:         return .fileHidden
        case .fileBinary:         return .fileBinary
        case .fileSecretDetected: return .fileSecretDetected
        case .gitignored:         return .gitignored
        }
    }

    @ViewBuilder
    private func stringField(_ label: String, placeholder: String, value: String, mono: Bool = false, onCommit: @escaping @Sendable (String) -> Void) -> some View {
        TextField(placeholder, text: Binding(get: { value }, set: onCommit))
            .font(mono ? ManifoldType.monoBody : ManifoldType.body)
            .textFieldStyle(.roundedBorder)
            .disabled(!isEditable)
    }

    @ViewBuilder
    private func bytesField(_ label: String, value: Int64, onCommit: @escaping (Int64) -> Void) -> some View {
        HStack {
            TextField("MB", value: Binding(
                get: { Int(value / 1_048_576) },
                set: { onCommit(Int64($0) * 1_048_576) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            .disabled(!isEditable)
            Text("MB")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func daysField(_ label: String, value: TimeInterval, onCommit: @escaping (TimeInterval) -> Void) -> some View {
        HStack {
            TextField("days", value: Binding(
                get: { Int(value / 86_400) },
                set: { onCommit(TimeInterval($0) * 86_400) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            .disabled(!isEditable)
            Text("days")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Email scope

private struct EmailBuilder: View {
    @Binding var matcher: RuleMatcher
    let isEditable: Bool

    enum Kind: String, CaseIterable, Identifiable {
        case emailSender, emailDomain, emailSubjectKeyword, emailBodyKeyword, emailHasAttachment, emailShield
        var id: String { rawValue }
        var title: String {
            switch self {
            case .emailSender:         return "From sender"
            case .emailDomain:         return "From domain"
            case .emailSubjectKeyword: return "Subject contains"
            case .emailBodyKeyword:    return "Body contains"
            case .emailHasAttachment:  return "Has attachment"
            case .emailShield:         return "Matches shield"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Picker("Condition", selection: Binding(
                get: { currentKind() },
                set: { newKind in matcher = defaultMatcher(for: newKind) }
            )) {
                ForEach(Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .disabled(!isEditable)

            parameterEditor
        }
    }

    @ViewBuilder
    private var parameterEditor: some View {
        switch matcher {
        case .emailSender(let v):
            stringField("sender@example.com", value: v) { matcher = .emailSender($0) }
        case .emailDomain(let v):
            stringField("*.bank.com", value: v) { matcher = .emailDomain($0) }
        case .emailSubjectKeyword(let s, let r):
            keywordField(value: s, isRegex: r) { matcher = .emailSubjectKeyword($0, regex: $1) }
        case .emailBodyKeyword(let s, let r):
            keywordField(value: s, isRegex: r) { matcher = .emailBodyKeyword($0, regex: $1) }
        case .emailHasAttachment:
            Text("Matches any message with at least one attachment.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        case .emailShield(let kind):
            Picker("Shield", selection: Binding(
                get: { kind },
                set: { matcher = .emailShield($0) }
            )) {
                ForEach(EmailShieldKind.allCases, id: \.self) { shield in
                    Text(shield.displayName).tag(shield)
                }
            }
            .disabled(!isEditable)
        default:
            Text("Unsupported condition")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func currentKind() -> Kind {
        switch matcher {
        case .emailSender:         return .emailSender
        case .emailDomain:         return .emailDomain
        case .emailSubjectKeyword: return .emailSubjectKeyword
        case .emailBodyKeyword:    return .emailBodyKeyword
        case .emailHasAttachment:  return .emailHasAttachment
        case .emailShield:         return .emailShield
        default:                   return .emailDomain
        }
    }

    private func defaultMatcher(for kind: Kind) -> RuleMatcher {
        switch kind {
        case .emailSender:         return .emailSender("user@example.com")
        case .emailDomain:         return .emailDomain("*.example.com")
        case .emailSubjectKeyword: return .emailSubjectKeyword("", regex: false)
        case .emailBodyKeyword:    return .emailBodyKeyword("", regex: false)
        case .emailHasAttachment:  return .emailHasAttachment
        case .emailShield:         return .emailShield(.financial)
        }
    }

    @ViewBuilder
    private func stringField(_ placeholder: String, value: String, onCommit: @escaping @Sendable (String) -> Void) -> some View {
        TextField(placeholder, text: Binding(get: { value }, set: onCommit))
            .textFieldStyle(.roundedBorder)
            .disabled(!isEditable)
    }

    @ViewBuilder
    private func keywordField(value: String, isRegex: Bool, onCommit: @escaping (String, Bool) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            TextField("keyword", text: Binding(get: { value }, set: { onCommit($0, isRegex) }))
                .font(isRegex ? ManifoldType.monoBody : ManifoldType.body)
                .textFieldStyle(.roundedBorder)
                .disabled(!isEditable)
            Toggle("Interpret as regex", isOn: Binding(
                get: { isRegex },
                set: { onCommit(value, $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!isEditable)
        }
    }
}

// MARK: - Agent scope

private struct AgentBuilder: View {
    @Binding var matcher: RuleMatcher
    let isEditable: Bool

    enum Kind: String, CaseIterable, Identifiable {
        case agentWrite, agentDelete, agentTool, agentSessionLongerThan, agentPayloadLargerThan
        var id: String { rawValue }
        var title: String {
            switch self {
            case .agentWrite:              return "Any write call"
            case .agentDelete:             return "Any delete call"
            case .agentTool:               return "Specific tool"
            case .agentSessionLongerThan:  return "Session longer than"
            case .agentPayloadLargerThan:  return "Payload larger than"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Picker("Condition", selection: Binding(
                get: { currentKind() },
                set: { newKind in matcher = defaultMatcher(for: newKind) }
            )) {
                ForEach(Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .disabled(!isEditable)

            parameterEditor
        }
    }

    @ViewBuilder
    private var parameterEditor: some View {
        switch matcher {
        case .agentWrite, .agentDelete:
            Text("Matches every request of this kind.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        case .agentTool(let t):
            Picker("Tool", selection: Binding(
                get: { t },
                set: { matcher = .agentTool($0) }
            )) {
                ForEach(AgentTool.allCases, id: \.self) { tool in
                    Text(tool.displayName).tag(tool)
                }
            }
            .disabled(!isEditable)
        case .agentSessionLongerThan(let t):
            minutesField(value: t) { matcher = .agentSessionLongerThan($0) }
        case .agentPayloadLargerThan(let n):
            bytesField(value: n) { matcher = .agentPayloadLargerThan($0) }
        default:
            Text("Unsupported condition")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func currentKind() -> Kind {
        switch matcher {
        case .agentWrite:              return .agentWrite
        case .agentDelete:             return .agentDelete
        case .agentTool:               return .agentTool
        case .agentSessionLongerThan:  return .agentSessionLongerThan
        case .agentPayloadLargerThan:  return .agentPayloadLargerThan
        default:                       return .agentWrite
        }
    }

    private func defaultMatcher(for kind: Kind) -> RuleMatcher {
        switch kind {
        case .agentWrite:              return .agentWrite
        case .agentDelete:             return .agentDelete
        case .agentTool:               return .agentTool(.write)
        case .agentSessionLongerThan:  return .agentSessionLongerThan(60 * 60)
        case .agentPayloadLargerThan:  return .agentPayloadLargerThan(1 * 1024 * 1024)
        }
    }

    @ViewBuilder
    private func minutesField(value: TimeInterval, onCommit: @escaping (TimeInterval) -> Void) -> some View {
        HStack {
            TextField("min", value: Binding(
                get: { Int(value / 60) },
                set: { onCommit(TimeInterval($0) * 60) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            .disabled(!isEditable)
            Text("minutes")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func bytesField(value: Int64, onCommit: @escaping (Int64) -> Void) -> some View {
        HStack {
            TextField("KB", value: Binding(
                get: { Int(value / 1024) },
                set: { onCommit(Int64($0) * 1024) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            .disabled(!isEditable)
            Text("KB")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        }
    }
}
