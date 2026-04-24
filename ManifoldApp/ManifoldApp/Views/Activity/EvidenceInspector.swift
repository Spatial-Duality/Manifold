// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EvidenceInspector — right-pane detail for a selected event.
//
// Per design/html/activity.html: kicker + title + mono path + stats +
// DiffView + "Why allowed" card + file-activity sparkline + related-files
// list + Revert/Open actions. Denial rows get the orange "Claude tried
// to read…" variant.

import SwiftUI
import ManifoldKit
import ManifoldXPC

struct EvidenceInspector: View {
    let selection: AuditEntry.ID?
    let entries: [AuditEntry]
    let store: ManifoldStore

    private var entry: AuditEntry? {
        guard let selection else { return nil }
        return entries.first(where: { $0.id == selection })
    }

    var body: some View {
        ScrollView {
            if let entry {
                if isDenial(entry) {
                    DenialDetailCard(entry: entry)
                } else if isPrivacy(entry) {
                    PrivacyDetailCard(entry: entry)
                } else {
                    EventDetailCard(entry: entry, store: store)
                }
            } else {
                ContentUnavailableView(
                    "Choose an event",
                    systemImage: "rectangle.righthalf.inset.filled",
                    description: Text("Select any activity to see the file, agent, decision, and available recovery action.")
                )
                .frame(maxWidth: .infinity)
                .padding(Spacing.s8)
            }
        }
        .accessibilityIdentifier("activity.evidence.inspector")
    }

    private func isDenial(_ entry: AuditEntry) -> Bool {
        entry.action.contains("deny") || entry.action.contains("denied")
    }

    private func isPrivacy(_ entry: AuditEntry) -> Bool {
        entry.action == AuditAction.sensitivityWarning.rawValue
    }
}

private struct EventDetailCard: View {
    let entry: AuditEntry
    let store: ManifoldStore
    @State private var restoreResult: RestoreSnapshotResult?
    @State private var isRestoring = false

    private var presentation: ActivityEventPresentation {
        ActivityEventPresentation(entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                        .fill(presentation.color.opacity(0.14))
                    Image(systemName: presentation.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(presentation.color)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(ManifoldType.heading)
                        .foregroundStyle(ManifoldPalette.text)
                    Text(presentation.detail)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let path = entry.filePath {
                Text((path as NSString).lastPathComponent)
                    .font(ManifoldType.bodyMedium)
                Text(path.shortenedPath)
                    .font(ManifoldType.mono)
                    .foregroundStyle(ManifoldPalette.text2)
                    .textSelection(.enabled)
            }

            // Stats strip
            HStack(spacing: Spacing.s4) {
                if let agent = entry.agent {
                    LabeledMeta(label: "Agent", value: agent.capitalized)
                }
                LabeledMeta(label: "Time", value: EventTable.displayTime(entry.timestamp))
                if let grantID = entry.grantID {
                    LabeledMeta(label: "Grant", value: String(grantID.prefix(8)))
                }
            }
            .font(ManifoldType.caption)

            if entry.beforeHash != nil || entry.afterHash != nil {
                HStack(spacing: Spacing.s2) {
                    Pill(text: "Tracked", variant: .defaultScope, systemImage: "clock.arrow.circlepath")
                    Text("A recoverable before/after record exists.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: Spacing.s2) {
                if let path = entry.filePath {
                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                }
                if let snapshotID = entrySnapshotID, let filePath = entry.filePath {
                    Button(isRestoring ? "Restoring…" : "Restore this version") {
                        isRestoring = true
                        Task {
                            let result = await store.restoreFile(snapshotID: snapshotID, filePath: filePath)
                            await MainActor.run {
                                restoreResult = result
                                isRestoring = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isRestoring)
                }
            }
            .padding(.top, Spacing.s2)

            if let restoreResult {
                RestoreStatusCard(result: restoreResult)
            }
        }
        .padding(Spacing.s4)
        .accessibilityIdentifier("activity.evidence.event")
    }

    private var entrySnapshotID: Int? {
        if let metadataID = metadataValue(for: "snapshot_id").flatMap(Int.init) {
            return metadataID
        }
        return nil
    }

    private func metadataValue(for key: String) -> String? {
        guard let metadata = entry.metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return json[key]
    }
}

private struct DenialDetailCard: View {
    let entry: AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(ManifoldPalette.attention)
                Text("DENIAL")
                    .font(ManifoldType.tiny.weight(.semibold))
                    .foregroundStyle(ManifoldPalette.attention)
                    .tracking(0.5)
            }

            Text((entry.agent?.capitalized ?? "Agent") + " tried to read")
                .font(ManifoldType.heading)
            Text(entry.filePath?.shortenedPath ?? "unknown target")
                .font(ManifoldType.monoBody)
                .foregroundStyle(ManifoldPalette.text2)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text("Why this was blocked")
                    .font(ManifoldType.bodyMedium)
                Text("Not in the agent's scope for this session. Denials are successes — this is Manifold working. Grant the path to allow it, or add a rule.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.s3)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4)
                    .fill(ManifoldPalette.attentionSoft)
            )
        }
        .padding(Spacing.s4)
        .accessibilityIdentifier("activity.evidence.denial")
    }
}

private struct PrivacyDetailCard: View {
    let entry: AuditEntry

    var body: some View {
        let metadata = metadataValues
        let categories = Self.parseCategories(metadata["privacy_categories"])
        let severity = Self.inferredSeverity(for: categories)
        let outcomeRaw = metadata["privacy_outcome"]
        let outcome = outcomeRaw.flatMap(PrivacyOutcome.init(rawValue:))
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(outcomeColor(outcome))
                Text("PRIVACY DECISION")
                    .font(ManifoldType.tiny.weight(.semibold))
                    .foregroundStyle(outcomeColor(outcome))
                    .tracking(0.5)
                Spacer()
                PrivacySeverityBar(severity: severity)
            }

            Text(outcome?.displayName ?? "Sensitive content detected")
                .font(ManifoldType.heading)

            if let path = entry.filePath {
                Text(path.shortenedPath)
                    .font(ManifoldType.monoBody)
                    .foregroundStyle(ManifoldPalette.text2)
                    .textSelection(.enabled)
            }

            if !categories.isEmpty {
                HStack(spacing: Spacing.s1) {
                    ForEach(categories, id: \.self) { category in
                        CategoryChip(category: category)
                    }
                }
                .accessibilityIdentifier("activity.evidence.privacy.categories")
            }

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text("What Manifold found")
                    .font(ManifoldType.bodyMedium)
                Text(metadata["privacy_summary"] ?? "Detected sensitive spans before sharing.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.s3)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4)
                    .fill(outcomeSoftBackground(outcome))
            )
            .accessibilityIdentifier("activity.evidence.privacy.summary")

            HStack(spacing: Spacing.s4) {
                if let backend = metadata["privacy_backend"] {
                    LabeledMeta(label: "Backend", value: backend)
                }
                if let modelVersion = metadata["privacy_model_version"] {
                    LabeledMeta(label: "Model", value: modelVersion)
                }
                if let contentKind = metadata["privacy_content_kind"] {
                    LabeledMeta(label: "Content", value: contentKind.replacingOccurrences(of: "_", with: " "))
                }
                if let agent = entry.agent {
                    LabeledMeta(label: "Agent", value: agent.capitalized)
                }
            }
            .font(ManifoldType.caption)
        }
        .padding(Spacing.s4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.evidence.privacy")
    }

    private var metadataValues: [String: String] {
        guard let metadata = entry.metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return json
    }

    private static func parseCategories(_ raw: String?) -> [PrivacyCategory] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw
            .split(separator: ",")
            .map(String.init)
            .compactMap(PrivacyCategory.init(rawValue:))
    }

    private static func inferredSeverity(for categories: [PrivacyCategory]) -> PrivacySeverity {
        if categories.contains(.secret) { return .critical }
        if categories.contains(.accountNumber) { return .high }
        if categories.contains(where: { [.privatePerson, .email, .phone, .address].contains($0) }) {
            return .medium
        }
        if categories.isEmpty { return .none }
        return .low
    }

    private func outcomeColor(_ outcome: PrivacyOutcome?) -> Color {
        switch outcome {
        case .blocked:           return ManifoldPalette.danger
        case .filtered:          return ManifoldPalette.preview
        case .warning, .approvalRequired, .clean, nil:
            return ManifoldPalette.attention
        }
    }

    private func outcomeSoftBackground(_ outcome: PrivacyOutcome?) -> Color {
        switch outcome {
        case .filtered:
            return ManifoldPalette.preview.opacity(0.16)
        default:
            return ManifoldPalette.attentionSoft
        }
    }
}

private struct LabeledMeta: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(ManifoldType.tiny)
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            Text(value)
                .foregroundStyle(ManifoldPalette.text)
        }
    }
}

private struct RestoreStatusCard: View {
    let result: RestoreSnapshotResult

    private var tone: Color {
        switch result.status {
        case "success":
            return ManifoldPalette.active
        case "conflict":
            return ManifoldPalette.attention
        default:
            return ManifoldPalette.text2
        }
    }

    private var background: Color {
        switch result.status {
        case "success":
            return ManifoldPalette.activeSoft
        case "conflict":
            return ManifoldPalette.attentionSoft
        default:
            return ManifoldPalette.surface3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(result.status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(ManifoldType.captionMedium)
                .foregroundStyle(tone)
            Text(result.message ?? "Manifold returned a restore update.")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                .fill(background)
        )
    }
}
