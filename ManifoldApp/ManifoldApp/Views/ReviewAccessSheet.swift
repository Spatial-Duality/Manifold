// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// What triggered the Review sheet to open.
struct ReviewAccessChange: Identifiable {
    let id = UUID()
    let description: String
    let kind: Kind

    enum Kind {
        case addSource(sourceID: String, sourceName: String)
        case bulkSources(sourceIDs: [String])
        case explicit // User clicked "Review & Update Access"
        case startWorkBlock

        var isExplicit: Bool {
            if case .explicit = self { return true }
            return false
        }
    }
}

/// Full-height attached sheet for ALL broadening access changes.
/// This is the product's commitment surface — every grant is deliberate.
struct ReviewAccessSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss

    /// The specific change that triggered this sheet.
    let pendingChange: ReviewAccessChange?

    /// Which agent is being configured.
    @State private var selectedAgent: TargetApp = .cowork
    @State private var hasInitializedAgent = false

    /// Draft policy — editable copy for the explicit review path
    @State private var draftAllowedSources: Set<String> = []
    @State private var draftInitialized = false

    /// Internal tab: Files or Emails
    @State private var selectedTab: ReviewTab = .files

    enum ReviewTab: Hashable {
        case files
        case emails
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sheetHeader

            Divider()

            // What's changing (green tinted section)
            if let change = pendingChange, !change.kind.isExplicit {
                whatsChangingSection(change)
            }

            // Files | Emails tab bar
            Group {
                Picker("Review", selection: $selectedTab) {
                    Text("Files")
                        .tag(ReviewTab.files)
                        .accessibilityIdentifier("reviewAccess.tab.files")
                    Text("Emails")
                        .tag(ReviewTab.emails)
                        .accessibilityIdentifier("reviewAccess.tab.emails")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(Spacing.section)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reviewAccess.tabPicker")

            // Content
            ScrollView {
                switch selectedTab {
                case .files:
                    filesContent
                case .emails:
                    emailsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()

            // Footer with counts + CTAs
            sheetFooter
        }
        .frame(minWidth: 520, minHeight: 500)
        .accessibilityIdentifier("reviewAccess.sheet")
        .task {
            guard !hasInitializedAgent else { return }
            selectedAgent = store.agentFocus.targetApp
            hasInitializedAgent = true
            // Initialize draft from current policy for explicit reviews
            if !draftInitialized {
                draftAllowedSources = store.policy.policy(for: selectedAgent)?.allowedSourceIDs ?? []
                draftInitialized = true
            }
        }
        .onChange(of: selectedAgent) { _, newAgent in
            if isExplicitReview {
                draftAllowedSources = store.policy.policy(for: newAgent)?.allowedSourceIDs ?? []
            }
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review & Update Access")
                    .font(Typ.sectionTitle)
                Text("Review what \(selectedAgent == .codex ? "Codex" : "Claude") can access")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Agent switcher
            Picker("Agent", selection: $selectedAgent) {
                HStack(spacing: 4) {
                    Circle().fill(.blue).frame(width: 8, height: 8)
                    Text("Claude")
                }.tag(TargetApp.cowork)
                HStack(spacing: 4) {
                    Circle().fill(.purple).frame(width: 8, height: 8)
                    Text("Codex")
                }.tag(TargetApp.codex)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding(Spacing.edge)
    }

    // MARK: - What's Changing

    private func whatsChangingSection(_ change: ReviewAccessChange) -> some View {
        HStack(spacing: Spacing.standard) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
            Text(change.description)
                .font(Typ.body.weight(.medium))
            Spacer()
        }
        .padding(Spacing.section)
        .background(Color.green.opacity(0.08))
    }

    // MARK: - Files Content

    private var isExplicitReview: Bool {
        pendingChange?.kind.isExplicit == true
    }

    private var filesContent: some View {
        let allowedIDs = isExplicitReview ? draftAllowedSources : (store.policy.policy(for: selectedAgent)?.allowedSourceIDs ?? [])

        return VStack(alignment: .leading, spacing: Spacing.standard) {
            ForEach(store.sources.filter { !$0.isRemoved }) { source in
                let isInPolicy = allowedIDs.contains(source.sourceID)

                HStack(spacing: Spacing.standard) {
                    if isExplicitReview {
                        // Editable toggles for explicit review
                        Toggle(isOn: Binding(
                            get: { draftAllowedSources.contains(source.sourceID) },
                            set: { enabled in
                                if enabled {
                                    draftAllowedSources.insert(source.sourceID)
                                } else {
                                    draftAllowedSources.remove(source.sourceID)
                                }
                            }
                        )) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    } else {
                        // Read-only for specific-change triggers
                        Toggle(isOn: .constant(isInPolicy || isNewAddition(source))) { EmptyView() }
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .disabled(true)
                    }

                    Image(systemName: "folder.fill")
                        .foregroundStyle(isInPolicy ? .blue : .secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.displayName)
                            .font(Typ.body)
                        Text(source.originalRootPath.shortenedPath)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if isNewAddition(source) {
                        Text("new \u{2726}")
                            .font(Typ.caption.weight(.medium))
                            .foregroundStyle(.green)
                    } else if isInPolicy {
                        Text("current")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(Spacing.edge)
    }

    // MARK: - Emails Content

    private var emailsContent: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            let policy = store.policy.policy(for: selectedAgent)
            let governance = store.policy.emailGovernance(for: selectedAgent)

            Text("Email access is managed in Email Rules.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                if let governance {
                    Text("\(selectedAgent == .codex ? "Codex" : "Claude") currently has \(governance.enabledShieldCount) active shields and \(governance.totalRuleCount) explicit rules.")
                    Text("Current sensitivity: \(governance.emailSensitivity.displayName). Default policy: \(governance.defaultPolicy.displayName).")
                } else if let policy {
                    Text("Current sensitivity: \(policy.emailSensitivity.displayName).")
                }
                Text("Use Email Rules to edit shields, domain rules, contact overrides, keyword rules, and the default policy.")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Button("Open Email Rules") {
                store.agentFocus = selectedAgent == .codex ? .codex : .claude
                store.selectedTab = .emails
                store.emailRulesDestination = .policy
                dismiss()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reviewAccess.openEmailRules")
        }
        .padding(Spacing.edge)
    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack(spacing: Spacing.standard) {
            let agentName = selectedAgent == .codex ? "Codex" : "Claude"
            let policy = store.policy.policy(for: selectedAgent)
            let governance = store.policy.emailGovernance(for: selectedAgent)
            let sourceCount = policy?.allowedSourceIDs.count ?? 0
            let ruleCount = governance?.totalRuleCount ?? 0
            Text("\(agentName): \(sourceCount) sources \u{00B7} \(ruleCount) email rules")
                .font(Typ.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button(primaryButtonLabel) {
                commitPolicyChange()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(Spacing.edge)
    }

    // MARK: - Helpers

    private var primaryButtonLabel: String {
        if let change = pendingChange {
            switch change.kind {
            case .explicit: return "Update Access"
            case .startWorkBlock: return "Track Changes"
            default: return "Allow Access"
            }
        }
        return "Update Access"
    }

    /// Commit the pending policy change via PolicyModel.
    private func commitPolicyChange() {
        guard let change = pendingChange else { return }
        Task {
            switch change.kind {
            case .addSource(let sourceID, _):
                await store.policy.addSource(sourceID, to: selectedAgent)
            case .bulkSources(let sourceIDs):
                for id in sourceIDs {
                    await store.policy.addSource(id, to: selectedAgent)
                }
            case .explicit:
                // Apply the draft policy — add new sources, remove unchecked ones
                let current = store.policy.policy(for: selectedAgent)?.allowedSourceIDs ?? []
                let toAdd = draftAllowedSources.subtracting(current)
                let toRemove = current.subtracting(draftAllowedSources)
                for id in toAdd { await store.policy.addSource(id, to: selectedAgent) }
                for id in toRemove { await store.policy.removeSource(id, from: selectedAgent) }
            case .startWorkBlock:
                // Apply access changes first, then work block starts from the caller
                let current = store.policy.policy(for: selectedAgent)?.allowedSourceIDs ?? []
                let toAdd = draftAllowedSources.subtracting(current)
                for id in toAdd { await store.policy.addSource(id, to: selectedAgent) }
            }
        }
    }

    private func isNewAddition(_ source: SourceRecord) -> Bool {
        guard let change = pendingChange else { return false }
        switch change.kind {
        case .addSource(let sourceID, _):
            return source.sourceID == sourceID
        case .bulkSources(let ids):
            return ids.contains(source.sourceID)
        default:
            return false
        }
    }

}
