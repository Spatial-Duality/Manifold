// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// PrivacySettingsPane — the Privacy tab in the Settings window.
//
// Five sections, top to bottom:
//   1. Scanner Model    — install/uninstall, effective scanner, cache
//   2. Auto-Settings     — Off / Balanced / Strict / Custom preset tiles
//   3. My Identity       — suggestion triage + accepted identity table
//   4. Org Allowlist     — domains/addresses that suppress model findings
//   5. Index Status      — queued/running/indexed counts + rescan trigger
//
// Per-agent policy editors stay in AgentsSettingsPane (where the other
// per-agent knobs live); this pane owns model lifecycle, identity, and
// allowlist — the things that cross agent boundaries.

import SwiftUI
import ManifoldKit

struct PrivacySettingsPane: View {
    @Environment(ManifoldStore.self) private var store
    @State private var showAddIdentity = false
    @State private var showAddAllowEntry = false

    var body: some View {
        Form {
            modelSection
            presetsSection
            FilterModeSection()
            identitySection
            allowlistSection
            indexStatusSection
        }
        .formStyle(.grouped)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.privacy.pane")
        .task {
            await store.governance.loadPolicies()
            await store.governance.loadPrivacyDiscovery()
        }
        .sheet(isPresented: $showAddIdentity) {
            AddPrivacyIdentitySheet()
                .environment(store)
        }
        .sheet(isPresented: $showAddAllowEntry) {
            AddOrgAllowEntrySheet()
                .environment(store)
        }
    }

    // MARK: - 1. Scanner Model

    @ViewBuilder
    private var modelSection: some View {
        Section {
            if let settings = store.governance.privacySettings,
               let status = store.governance.privacyRuntimeStatus {
                PrivacyModelCard(settings: settings, status: status)
            } else {
                ProgressView("Loading scanner model…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Fast Local Scanner").font(ManifoldType.title)
        }
    }

    // MARK: - 2. Presets

    @ViewBuilder
    private var presetsSection: some View {
        Section {
            if store.governance.privacySettings != nil {
                PrivacyPresetsRow()
            }
        } header: {
            Text("Auto-Settings").font(ManifoldType.title)
        } footer: {
            Text("Presets write global privacy settings and seed per-agent policies. Hand-tuned changes in Agents ▸ Privacy switch the preset to Custom.")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text2)
        }
    }

    // MARK: - 3. My Identity

    @ViewBuilder
    private var identitySection: some View {
        Section {
            if !store.governance.privacyIdentitySuggestions.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("Suggestions")
                        .font(ManifoldType.captionMedium)
                        .foregroundStyle(ManifoldPalette.text2)
                    ForEach(store.governance.privacyIdentitySuggestions) { suggestion in
                        IdentitySuggestionRow(suggestion: suggestion)
                        if suggestion.id != store.governance.privacyIdentitySuggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.bottom, Spacing.s2)
            }
            if store.governance.privacyIdentities.isEmpty {
                HStack(spacing: Spacing.s3) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No identities yet")
                            .font(ManifoldType.bodyMedium)
                        Text("Add yourself so the privacy model knows what to treat as sensitive about *you* — not just anyone.")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                IdentityTable(identities: store.governance.privacyIdentities)
            }
            HStack {
                Spacer()
                Button {
                    showAddIdentity = true
                } label: {
                    Label("Add Identity", systemImage: "plus")
                }
                .controlSize(.small)
                .accessibilityIdentifier("settings.privacy.identities.add")
            }
        } header: {
            Text("My Identity").font(ManifoldType.title)
        } footer: {
            Text("Identities in this list are treated as you. Anything matching here is redacted or blocked before agents see it, even if nothing else would have flagged it.")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text2)
        }
    }

    // MARK: - 4. Org Allowlist

    @ViewBuilder
    private var allowlistSection: some View {
        Section {
            if store.governance.privacyOrgAllowEntries.isEmpty {
                HStack(spacing: Spacing.s3) {
                    Image(systemName: "building.2")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No allowlist entries")
                            .font(ManifoldType.bodyMedium)
                        Text("Add your org's domain so internal emails and links aren't flagged as personal contact data.")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                OrgAllowlistTable(entries: store.governance.privacyOrgAllowEntries)
            }
            HStack {
                Spacer()
                Button {
                    showAddAllowEntry = true
                } label: {
                    Label("Add Allowlist Entry", systemImage: "plus")
                }
                .controlSize(.small)
                .accessibilityIdentifier("settings.privacy.allowlist.add")
            }
        } header: {
            Text("Org Allowlist").font(ManifoldType.title)
        } footer: {
            Text("Allowlist entries suppress contact-category findings (emails, URLs) from their domain. Secrets and identity matches are never suppressed.")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text2)
        }
    }

    // MARK: - 5. Index Status

    @ViewBuilder
    private var indexStatusSection: some View {
        Section {
            IndexStatusCard()
        } header: {
            Text("Index Status").font(ManifoldType.title)
        } footer: {
            Text("Content is scanned when folders or mailboxes change. Findings feed the approval queue and the My Identity suggestions list.")
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text2)
        }
    }
}

// MARK: - Model card

private struct PrivacyModelCard: View {
    @Environment(ManifoldStore.self) private var store
    let settings: PrivacyPreflightSettings
    let status: PrivacyRuntimeStatus
    @State private var isBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(spacing: Spacing.s3) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.s2) {
                        Text("Fast Local Scanner")
                            .font(ManifoldType.bodyMedium)
                        Pill(
                            text: status.installState.displayName,
                            variant: installPillVariant,
                            systemImage: installPillIcon
                        )
                    }
                    Text(subtitle)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                .accessibilityIdentifier("settings.privacy.model.enabled")
                .disabled(status.installState == .unavailable)
            }

            runtimeSummary
            if let progress = status.downloadProgress,
               status.installState == .downloading || status.installState == .verifying {
                ProgressView(value: progress)
                    .accessibilityLabel("Privacy scanner download progress")
            }

            HStack(spacing: Spacing.s2) {
                Button {
                    Task {
                        isBusy = true
                        defer { isBusy = false }
                        await store.governance.installPrivacyRuntime()
                    }
                } label: {
                    Label(installButtonTitle,
                          systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .disabled(isBusy || status.installState == .unavailable || status.installState == .downloading || status.installState == .verifying)
                .accessibilityIdentifier("settings.privacy.runtime.install")

                Button {
                    Task {
                        isBusy = true
                        defer { isBusy = false }
                        await store.governance.uninstallPrivacyRuntime()
                    }
                } label: {
                    Label(cancelOrRemoveTitle, systemImage: status.installState == .downloading ? "xmark.circle" : "trash")
                }
                .controlSize(.small)
                .disabled(status.installState == .notInstalled || status.installState == .downloadRequired || status.installState == .unavailable || isBusy)
                .accessibilityIdentifier("settings.privacy.runtime.uninstall")

                Button {
                    Task {
                        isBusy = true
                        defer { isBusy = false }
                        await store.governance.clearPrivacyCache()
                    }
                } label: {
                    Label("Clear Cache (\(status.cacheEntryCount))", systemImage: "xmark.bin")
                }
                .controlSize(.small)
                .disabled(isBusy)
                .accessibilityIdentifier("settings.privacy.model.clearCache")

                Spacer()

                if let version = settings.modelVersion {
                    Text(version)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.tertiary)
                }
            }

            if let lastError = status.lastError, !lastError.isEmpty {
                Label(lastError, systemImage: "exclamationmark.triangle")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.attention)
            }
        }
        .task(id: status.installState) {
            guard status.installState == .downloading || status.installState == .verifying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await store.governance.loadPolicies()
            }
        }
    }

    private var runtimeSummary: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: status.verificationState == .checksumVerified ? "checkmark.seal" : "shippingbox")
                .foregroundStyle(status.verificationState == .failed ? ManifoldPalette.danger : ManifoldPalette.text2)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.runtimeDisplayName ?? "Fast Local Scanner")
                    .font(ManifoldType.captionMedium)
                Text(runtimeDetail)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s1)
    }

    private var accentColor: Color {
        switch status.installState {
        case .installed:        return ManifoldPalette.active
        case .downloading:      return ManifoldPalette.selection
        case .verifying:        return ManifoldPalette.selection
        case .downloadRequired: return ManifoldPalette.attention
        case .unavailable:      return ManifoldPalette.danger
        case .notInstalled:     return ManifoldPalette.text3
        }
    }

    private var installPillVariant: Pill.Variant {
        switch status.installState {
        case .installed:        return .session
        case .downloading:      return .defaultScope
        case .verifying:        return .defaultScope
        case .downloadRequired: return .attention
        case .unavailable:      return .attention
        case .notInstalled:     return .neutral
        }
    }

    private var installPillIcon: String {
        switch status.installState {
        case .installed:        return "checkmark.seal.fill"
        case .downloading:      return "arrow.down.circle.fill"
        case .verifying:        return "checkmark.shield"
        case .downloadRequired: return "arrow.down.circle"
        case .unavailable:      return "exclamationmark.triangle"
        case .notInstalled:     return "circle.dashed"
        }
    }

    private var subtitle: String {
        if status.installState == .unavailable {
            return "Privacy Preflight requires Apple Silicon."
        }
        if settings.isEnabled {
            return "Active scanner: \(status.effectiveBackend.displayName) · \(status.modelLoaded ? "Model loaded" : "Model unloaded")"
        }
        return "Privacy preflight is off. Agents see raw content."
    }

    private var runtimeDetail: String {
        if status.installState == .unavailable {
            return "MLX MXFP8 scanning is unavailable on this Mac."
        }
        if status.installState == .downloading || status.installState == .verifying {
            let progress = (status.downloadProgress ?? 0) * 100
            return "MLX MXFP8 · 1.47 GB · \(String(format: "%.0f", progress))% \(status.installState.displayName.lowercased())."
        }
        if let installed = status.installedVersion {
            let verification = status.verificationState?.displayName ?? "Verification unknown"
            return "MLX MXFP8 · Installed \(installed) · \(verification) · works offline."
        }
        return "MLX MXFP8 · 1.47 GB · Recommended for Apple Silicon Macs."
    }

    private var installButtonTitle: String {
        switch status.installState {
        case .installed:
            return "Update"
        case .downloadRequired where (status.downloadedBytes ?? 0) > 0:
            return "Resume"
        default:
            return "Download"
        }
    }

    private var cancelOrRemoveTitle: String {
        status.installState == .downloading || status.installState == .verifying ? "Cancel" : "Remove"
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.governance.privacySettings?.isEnabled ?? settings.isEnabled },
            set: { newValue in
                guard var updated = store.governance.privacySettings else { return }
                updated.isEnabled = newValue
                if newValue && updated.installState == .notInstalled && updated.selectedBackend == .rulesOnly {
                    updated.installState = .installed
                    updated.modelVersion = updated.modelVersion ?? "rules-only-v1"
                }
                Task { await store.governance.updatePrivacySettings(updated) }
            }
        )
    }
}

// MARK: - Presets row

private struct PrivacyPresetsRow: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        HStack(spacing: Spacing.s3) {
            PresetCard(
                title: "Off",
                subtitle: "No filtering. Agents see content as-is.",
                systemImage: "shield.slash",
                accent: ManifoldPalette.text3,
                isSelected: currentPreset == .off,
                accessibilityIdentifier: "settings.privacy.preset.off",
                action: { apply(.off) }
            )
            PresetCard(
                title: "Balanced",
                subtitle: "Warn on personal info. Ask before sharing secrets.",
                systemImage: "shield.lefthalf.filled",
                accent: ManifoldPalette.selection,
                isSelected: currentPreset == .balanced,
                accessibilityIdentifier: "settings.privacy.preset.balanced",
                action: { apply(.balanced) }
            )
            PresetCard(
                title: "Strict",
                subtitle: "Redact all PII. Block secrets. Ask before code.",
                systemImage: "shield.fill",
                accent: ManifoldPalette.danger,
                isSelected: currentPreset == .strict,
                accessibilityIdentifier: "settings.privacy.preset.strict",
                action: { apply(.strict) }
            )
            PresetCard(
                title: "Custom",
                subtitle: "Hand-tuned per category and agent.",
                systemImage: "slider.horizontal.3",
                accent: ManifoldPalette.claude,
                isSelected: currentPreset == .custom,
                accessibilityIdentifier: "settings.privacy.preset.custom",
                action: {}
            )
        }
    }

    private var currentPreset: PrivacyPreset {
        PrivacyPreset.detect(
            settings: store.governance.privacySettings,
            claudePolicy: store.governance.claudePrivacyPolicy,
            codexPolicy: store.governance.codexPrivacyPolicy
        )
    }

    private func apply(_ preset: PrivacyPreset) {
        guard var settings = store.governance.privacySettings,
              let claudePolicy = store.governance.claudePrivacyPolicy,
              let codexPolicy = store.governance.codexPrivacyPolicy else { return }
        let (newSettings, newClaude, newCodex) = preset.apply(
            to: &settings,
            claude: claudePolicy,
            codex: codexPolicy
        )
        Task {
            await store.governance.updatePrivacySettings(newSettings)
            await store.governance.updatePrivacyPolicy(newClaude)
            await store.governance.updatePrivacyPolicy(newCodex)
        }
    }
}

enum PrivacyPreset: Equatable {
    case off, balanced, strict, custom

    static func detect(
        settings: PrivacyPreflightSettings?,
        claudePolicy: AgentPrivacyPolicy?,
        codexPolicy: AgentPrivacyPolicy?
    ) -> PrivacyPreset {
        guard let settings else { return .custom }
        if !settings.isEnabled { return .off }
        guard let claude = claudePolicy, let codex = codexPolicy else { return .custom }
        if matchesBalanced(claude) && matchesBalanced(codex) { return .balanced }
        if matchesStrict(claude) && matchesStrict(codex) { return .strict }
        return .custom
    }

    private static func matchesBalanced(_ p: AgentPrivacyPolicy) -> Bool {
        p.textHandling == .warn
            && p.codeHandling == .warn
            && p.secretHandling == .ask
            && p.enabledCategories == Set(PrivacyCategory.allCases)
    }

    private static func matchesStrict(_ p: AgentPrivacyPolicy) -> Bool {
        p.textHandling == .redact
            && p.codeHandling == .redact
            && p.secretHandling == .block
            && p.enabledCategories == Set(PrivacyCategory.allCases)
    }

    func apply(
        to settings: inout PrivacyPreflightSettings,
        claude: AgentPrivacyPolicy,
        codex: AgentPrivacyPolicy
    ) -> (PrivacyPreflightSettings, AgentPrivacyPolicy, AgentPrivacyPolicy) {
        switch self {
        case .off:
            settings.isEnabled = false
            return (settings, claude, codex)
        case .balanced:
            settings.isEnabled = true
            return (settings,
                    Self.policy(claude, text: .warn, code: .warn, secret: .ask),
                    Self.policy(codex,  text: .warn, code: .warn, secret: .ask))
        case .strict:
            settings.isEnabled = true
            return (settings,
                    Self.policy(claude, text: .redact, code: .redact, secret: .block),
                    Self.policy(codex,  text: .redact, code: .redact, secret: .block))
        case .custom:
            return (settings, claude, codex)
        }
    }

    private static func policy(
        _ p: AgentPrivacyPolicy,
        text: PrivacyHandlingMode,
        code: PrivacyHandlingMode,
        secret: PrivacySecretHandling
    ) -> AgentPrivacyPolicy {
        var updated = p
        updated.textHandling = text
        updated.codeHandling = code
        updated.secretHandling = secret
        updated.enabledCategories = Set(PrivacyCategory.allCases)
        return updated
    }
}

// MARK: - Identity suggestion row

private struct IdentitySuggestionRow: View {
    @Environment(ManifoldStore.self) private var store
    let suggestion: PrivacyIdentitySuggestion

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: Self.icon(for: suggestion.kind))
                .font(.system(size: 14))
                .foregroundStyle(ManifoldPalette.claude)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.displayName)
                    .font(ManifoldType.bodyMedium)
                HStack(spacing: Spacing.s1) {
                    Text(suggestion.value)
                        .font(ManifoldType.mono)
                        .foregroundStyle(ManifoldPalette.text2)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(Int(suggestion.confidence * 100))% confidence")
                        .font(ManifoldType.caption)
                        .foregroundStyle(ManifoldPalette.text2)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(Self.sourceLabel(for: suggestion.sourceKind))
                        .font(ManifoldType.caption)
                        .foregroundStyle(ManifoldPalette.text2)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: Spacing.s1) {
                Button("Reject") {
                    Task { await store.governance.rejectPrivacyIdentitySuggestion(id: suggestion.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("settings.privacy.suggestion.reject.\(suggestion.id)")

                Button("Accept") {
                    Task { await store.governance.acceptPrivacyIdentitySuggestion(id: suggestion.id) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("settings.privacy.suggestion.accept.\(suggestion.id)")
            }
        }
        .accessibilityIdentifier("settings.privacy.suggestion.\(suggestion.id)")
    }

    private static func icon(for kind: PrivacyIdentityKind) -> String {
        switch kind {
        case .personName:    return "person.crop.circle"
        case .email:         return "envelope"
        case .phone:         return "phone"
        case .address:       return "mappin.and.ellipse"
        case .accountNumber: return "creditcard"
        case .url:           return "link"
        case .secret:        return "lock.shield"
        }
    }

    private static func sourceLabel(for source: PrivacySuggestionSourceKind) -> String {
        switch source {
        case .emailAccount:   return "From email account"
        case .emailHeader:    return "From email header"
        case .emailSignature: return "From signature"
        case .sourceRoot:     return "From folder root"
        case .manual:         return "Manual"
        }
    }
}

// MARK: - Identity table

private struct IdentityTable: View {
    @Environment(ManifoldStore.self) private var store
    let identities: [PrivacyIdentityRecord]
    @State private var selection: PrivacyIdentityRecord.ID?

    var body: some View {
        Table(identities, selection: $selection) {
            TableColumn("Name") { identity in
                HStack(spacing: Spacing.s2) {
                    Image(systemName: IdentityTable.icon(for: identity.kind))
                        .foregroundStyle(identity.isEnabled ? ManifoldPalette.claude : ManifoldPalette.text3)
                    Text(identity.displayName)
                        .foregroundStyle(identity.isEnabled ? ManifoldPalette.text : ManifoldPalette.text3)
                }
            }
            TableColumn("Kind") { identity in
                Text(IdentityTable.kindLabel(for: identity.kind))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Value") { identity in
                Text(identity.value)
                    .font(ManifoldType.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TableColumn("Match") { identity in
                Text(IdentityTable.matchLabel(for: identity.matchingMode))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Enabled") { identity in
                Toggle("", isOn: enabledBinding(for: identity))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .width(min: 56, max: 72)
        }
        .frame(minHeight: 120, maxHeight: 260)
        .accessibilityIdentifier("settings.privacy.identities.table")
        .contextMenu(forSelectionType: PrivacyIdentityRecord.ID.self) { ids in
            if let id = ids.first {
                Button(role: .destructive) {
                    Task { await store.governance.deletePrivacyIdentity(id: id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } primaryAction: { _ in }
    }

    private func enabledBinding(for identity: PrivacyIdentityRecord) -> Binding<Bool> {
        Binding(
            get: { identity.isEnabled },
            set: { newValue in
                var updated = identity
                updated.isEnabled = newValue
                Task { await store.governance.upsertPrivacyIdentity(updated) }
            }
        )
    }

    static func icon(for kind: PrivacyIdentityKind) -> String {
        switch kind {
        case .personName:    return "person.crop.circle"
        case .email:         return "envelope"
        case .phone:         return "phone"
        case .address:       return "mappin.and.ellipse"
        case .accountNumber: return "creditcard"
        case .url:           return "link"
        case .secret:        return "lock.shield"
        }
    }

    static func kindLabel(for kind: PrivacyIdentityKind) -> String {
        switch kind {
        case .personName:    return "Person"
        case .email:         return "Email"
        case .phone:         return "Phone"
        case .address:       return "Address"
        case .accountNumber: return "Account"
        case .url:           return "URL"
        case .secret:        return "Secret"
        }
    }

    static func matchLabel(for mode: PrivacyMatchMode) -> String {
        switch mode {
        case .exact:        return "Exact"
        case .contains:     return "Contains"
        case .domainSuffix: return "Domain"
        }
    }
}

// MARK: - Org allowlist table

private struct OrgAllowlistTable: View {
    @Environment(ManifoldStore.self) private var store
    let entries: [PrivacyOrgAllowEntry]
    @State private var selection: PrivacyOrgAllowEntry.ID?

    var body: some View {
        Table(entries, selection: $selection) {
            TableColumn("Pattern") { entry in
                HStack(spacing: Spacing.s2) {
                    Image(systemName: OrgAllowlistTable.icon(for: entry.kind))
                        .foregroundStyle(entry.isEnabled ? ManifoldPalette.selection : ManifoldPalette.text3)
                    Text(entry.pattern)
                        .font(ManifoldType.mono)
                        .foregroundStyle(entry.isEnabled ? ManifoldPalette.text : ManifoldPalette.text3)
                }
            }
            TableColumn("Kind") { entry in
                Text(OrgAllowlistTable.kindLabel(for: entry.kind))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Match") { entry in
                Text(IdentityTable.matchLabel(for: entry.matchMode))
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Source") { entry in
                Text(entry.source)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Enabled") { entry in
                Toggle("", isOn: enabledBinding(for: entry))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .width(min: 56, max: 72)
        }
        .frame(minHeight: 120, maxHeight: 260)
        .accessibilityIdentifier("settings.privacy.allowlist.table")
        .contextMenu(forSelectionType: PrivacyOrgAllowEntry.ID.self) { ids in
            if let id = ids.first {
                Button(role: .destructive) {
                    Task { await store.governance.deletePrivacyOrgAllowEntry(id: id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } primaryAction: { _ in }
    }

    private func enabledBinding(for entry: PrivacyOrgAllowEntry) -> Binding<Bool> {
        Binding(
            get: { entry.isEnabled },
            set: { newValue in
                var updated = entry
                updated.isEnabled = newValue
                Task { await store.governance.upsertPrivacyOrgAllowEntry(updated) }
            }
        )
    }

    static func icon(for kind: PrivacyOrgAllowKind) -> String {
        switch kind {
        case .senderDomain:     return "at.badge.plus"
        case .organizationName: return "building.2"
        case .emailAddress:     return "envelope.badge"
        case .url:              return "link"
        }
    }

    static func kindLabel(for kind: PrivacyOrgAllowKind) -> String {
        switch kind {
        case .senderDomain:     return "Sender domain"
        case .organizationName: return "Org name"
        case .emailAddress:     return "Email address"
        case .url:              return "URL"
        }
    }
}

// MARK: - Index status

private struct IndexStatusCard: View {
    @Environment(ManifoldStore.self) private var store
    @State private var isRescanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            if let status = store.governance.privacyIndexStatus {
                HStack(spacing: Spacing.s5) {
                    indexStat(label: "Indexed",
                              value: "\(status.indexedItems)",
                              accent: ManifoldPalette.active)
                    indexStat(label: "In flight",
                              value: "\(status.runningJobs)",
                              accent: ManifoldPalette.claude)
                    indexStat(label: "Queued",
                              value: "\(status.queuedJobs)",
                              accent: ManifoldPalette.selection)
                    indexStat(label: "Failed",
                              value: "\(status.failedJobs)",
                              accent: status.failedJobs > 0 ? ManifoldPalette.attention : ManifoldPalette.text3)
                    indexStat(label: "Stale",
                              value: "\(status.staleItems)",
                              accent: status.staleItems > 0 ? ManifoldPalette.paused : ManifoldPalette.text3)
                    Spacer()
                }

                if !status.watchedSources.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watched sources")
                            .font(ManifoldType.tiny)
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .foregroundStyle(ManifoldPalette.text2)
                        Text(status.watchedSources.count == 1
                             ? "1 source"
                             : "\(status.watchedSources.count) sources")
                            .font(ManifoldType.caption)
                            .foregroundStyle(ManifoldPalette.text2)
                    }
                }

                if let lastError = status.lastError, !lastError.isEmpty {
                    Label(lastError, systemImage: "exclamationmark.triangle")
                        .font(ManifoldType.caption)
                        .foregroundStyle(ManifoldPalette.attention)
                }
            } else {
                ProgressView("Loading index status…")
            }

            HStack {
                Spacer()
                Button {
                    Task {
                        isRescanning = true
                        defer { isRescanning = false }
                        let ids = store.governance.privacyRecentIndex.map(\.id)
                        await store.governance.rescanPrivacyContent(contentIDs: ids)
                    }
                } label: {
                    Label(isRescanning ? "Rescanning…" : "Rescan Flagged",
                          systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(isRescanning || store.governance.privacyRecentIndex.isEmpty)
                .accessibilityIdentifier("settings.privacy.index.rescan")

                Button {
                    Task { await store.governance.loadPrivacyDiscovery() }
                } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.small)
                .accessibilityIdentifier("settings.privacy.index.refresh")
            }
        }
    }

    private func indexStat(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
            Text(label)
                .font(ManifoldType.tiny)
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(ManifoldPalette.text2)
        }
        .accessibilityIdentifier("settings.privacy.index.stat.\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}

// MARK: - Add identity sheet

private struct AddPrivacyIdentitySheet: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: PrivacyIdentityKind = .email
    @State private var displayName: String = ""
    @State private var value: String = ""
    @State private var matchingMode: PrivacyMatchMode = .exact

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Add Identity")
                    .font(ManifoldType.heading)
                Text("Anything matching this value will be treated as yours and redacted or blocked before agents see it.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s4)

            Divider()

            Form {
                Picker("Kind", selection: $kind) {
                    Text("Person name").tag(PrivacyIdentityKind.personName)
                    Text("Email").tag(PrivacyIdentityKind.email)
                    Text("Phone").tag(PrivacyIdentityKind.phone)
                    Text("Address").tag(PrivacyIdentityKind.address)
                    Text("Account number").tag(PrivacyIdentityKind.accountNumber)
                    Text("URL").tag(PrivacyIdentityKind.url)
                    Text("Secret").tag(PrivacyIdentityKind.secret)
                }
                TextField("Display name", text: $displayName, prompt: Text("e.g. Home email"))
                TextField("Value", text: $value, prompt: Text("e.g. ada@example.com"))
                Picker("Match", selection: $matchingMode) {
                    Text("Exact").tag(PrivacyMatchMode.exact)
                    Text("Contains").tag(PrivacyMatchMode.contains)
                    Text("Domain suffix").tag(PrivacyMatchMode.domainSuffix)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 220)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let record = PrivacyIdentityRecord(
                        kind: kind,
                        displayName: displayName.isEmpty ? value : displayName,
                        value: value,
                        matchingMode: matchingMode
                    )
                    Task {
                        await store.governance.upsertPrivacyIdentity(record)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Spacing.s4)
        }
        .frame(width: 460)
    }
}

// MARK: - Add allowlist sheet

private struct AddOrgAllowEntrySheet: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: PrivacyOrgAllowKind = .senderDomain
    @State private var pattern: String = ""
    @State private var matchMode: PrivacyMatchMode = .domainSuffix

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Add Allowlist Entry")
                    .font(ManifoldType.heading)
                Text("Suppress contact-category findings from this source. Secrets and identity matches are never suppressed.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s4)

            Divider()

            Form {
                Picker("Kind", selection: $kind) {
                    Text("Sender domain").tag(PrivacyOrgAllowKind.senderDomain)
                    Text("Organization name").tag(PrivacyOrgAllowKind.organizationName)
                    Text("Email address").tag(PrivacyOrgAllowKind.emailAddress)
                    Text("URL").tag(PrivacyOrgAllowKind.url)
                }
                TextField("Pattern", text: $pattern, prompt: Text("e.g. acme.com"))
                Picker("Match", selection: $matchMode) {
                    Text("Exact").tag(PrivacyMatchMode.exact)
                    Text("Contains").tag(PrivacyMatchMode.contains)
                    Text("Domain suffix").tag(PrivacyMatchMode.domainSuffix)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 180)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let entry = PrivacyOrgAllowEntry(
                        kind: kind,
                        pattern: pattern,
                        matchMode: matchMode,
                        source: "user"
                    )
                    Task {
                        await store.governance.upsertPrivacyOrgAllowEntry(entry)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Spacing.s4)
        }
        .frame(width: 460)
    }
}
