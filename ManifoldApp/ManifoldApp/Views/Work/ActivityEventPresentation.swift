// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct ActivityEventPresentation {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let outcomeLabel: String
    let outcomeSymbol: String
    let outcomeVariant: Pill.Variant
    let target: String?
    let needsAttention: Bool

    init(_ entry: AuditEntry) {
        let action = entry.action
        let targetName = entry.filePath
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 }
        let targetPath = entry.filePath?.shortenedPath
        let agent = entry.agent.map(Self.agentLabel) ?? "Manifold"
        let metadata = Self.metadataValues(for: entry)
        let privacyOutcome = metadata["privacy_outcome"].flatMap(PrivacyOutcome.init(rawValue:))

        target = targetName

        if action.contains("deny") || action.contains("denied") {
            title = "\(agent) was blocked"
            detail = targetPath.map { "Manifold kept \($0) out of scope." } ?? "Manifold blocked an out-of-scope request."
            symbol = "hand.raised.fill"
            color = ManifoldPalette.attention
            outcomeLabel = "Blocked"
            outcomeSymbol = "lock.fill"
            outcomeVariant = .attention
            needsAttention = true
        } else if action == AuditAction.sensitivityWarning.rawValue {
            title = privacyOutcome?.displayName ?? "Privacy decision"
            detail = metadata["privacy_summary"]
                ?? targetPath.map { "Privacy filter reviewed \($0) before sharing." }
                ?? "Privacy filter reviewed content before sharing."
            symbol = "shield.lefthalf.filled"
            outcomeSymbol = "shield"

            switch privacyOutcome {
            case .blocked:
                color = ManifoldPalette.danger
                outcomeLabel = "Secret blocked"
                outcomeVariant = .attention
                needsAttention = true
            case .filtered:
                color = ManifoldPalette.preview
                outcomeLabel = "Filtered"
                outcomeVariant = .preview
                needsAttention = false
            default:
                color = ManifoldPalette.attention
                outcomeLabel = "Needs review"
                outcomeVariant = .attention
                needsAttention = true
            }
        } else if action == AuditAction.coverageWarning.rawValue {
            title = "Coverage warning"
            detail = targetPath.map { "\(agent) touched \($0) near the Manifold boundary." } ?? "\(agent) produced a coverage warning."
            symbol = "exclamationmark.triangle.fill"
            color = ManifoldPalette.attention
            outcomeLabel = "Review"
            outcomeSymbol = "exclamationmark.triangle"
            outcomeVariant = .attention
            needsAttention = true
        } else if action == AuditAction.mcpConnection.rawValue {
            title = "\(agent) connected"
            detail = "The agent route connected through Manifold."
            symbol = "point.3.connected.trianglepath.dotted"
            color = ManifoldPalette.text3
            outcomeLabel = "Connected"
            outcomeSymbol = "checkmark.circle"
            outcomeVariant = .neutral
            needsAttention = false
        } else if action.contains("write")
                    || action == AuditAction.fileModified.rawValue
                    || action == AuditAction.fileCreated.rawValue
                    || action == AuditAction.fileDeleted.rawValue {
            title = Self.writeTitle(action: action, targetName: targetName)
            detail = targetPath.map { "\(agent) changed \($0)." } ?? "\(agent) wrote through Manifold."
            symbol = "pencil"
            color = ManifoldPalette.claude
            outcomeLabel = "Written"
            outcomeSymbol = "pencil"
            outcomeVariant = .defaultScope
            needsAttention = false
        } else if action.contains("read") {
            title = targetName.map { "Read \($0)" } ?? "File read"
            detail = targetPath.map { "\(agent) read \($0)." } ?? "\(agent) read shared content."
            symbol = "eye"
            color = ManifoldPalette.text2
            outcomeLabel = "Read"
            outcomeSymbol = "eye"
            outcomeVariant = .neutral
            needsAttention = false
        } else if action.contains("search") {
            title = "Search"
            detail = targetPath.map { "\(agent) searched near \($0)." } ?? "\(agent) searched shared context."
            symbol = "magnifyingglass"
            color = ManifoldPalette.codex
            outcomeLabel = "Search"
            outcomeSymbol = "magnifyingglass"
            outcomeVariant = .neutral
            needsAttention = false
        } else if action.contains("snapshot")
                    || action.contains("promote")
                    || action.contains("revert")
                    || action == AuditAction.restore.rawValue {
            title = action.replacingOccurrences(of: "_", with: " ").capitalized
            detail = targetPath.map { "Manifold recorded a recoverable version for \($0)." } ?? "Manifold recorded a recoverable version."
            symbol = "arrow.triangle.2.circlepath"
            color = ManifoldPalette.active
            outcomeLabel = "Versioned"
            outcomeSymbol = "clock.arrow.circlepath"
            outcomeVariant = .defaultScope
            needsAttention = false
        } else {
            title = action.replacingOccurrences(of: "_", with: " ").capitalized
            detail = targetPath.map { "\(agent) activity on \($0)." } ?? "Manifold recorded this activity."
            symbol = "circle.fill"
            color = ManifoldPalette.text3
            outcomeLabel = entry.grantID != nil || entry.sessionID != nil ? "Session" : "Logged"
            outcomeSymbol = entry.grantID != nil || entry.sessionID != nil ? "play.fill" : "list.bullet"
            outcomeVariant = entry.grantID != nil || entry.sessionID != nil ? .session : .neutral
            needsAttention = false
        }
    }

    static func agentLabel(_ rawAgent: String) -> String {
        guard let agent = TargetApp(rawValue: rawAgent) else {
            if rawAgent == "Unknown Agent" {
                return "Unknown agent"
            }
            return rawAgent.capitalized
        }
        return AgentMeta.label(agent)
    }

    private static func metadataValues(for entry: AuditEntry) -> [String: String] {
        guard let metadata = entry.metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return json
    }

    private static func writeTitle(action: String, targetName: String?) -> String {
        switch action {
        case AuditAction.fileCreated.rawValue:
            return targetName.map { "Created \($0)" } ?? "File created"
        case AuditAction.fileDeleted.rawValue:
            return targetName.map { "Deleted \($0)" } ?? "File deleted"
        default:
            return targetName.map { "Changed \($0)" } ?? "File changed"
        }
    }
}
