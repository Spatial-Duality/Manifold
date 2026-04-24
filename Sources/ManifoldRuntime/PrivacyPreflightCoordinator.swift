// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import ManifoldKit

struct PrivacyDelivery: Sendable {
    let deliveredText: String?
    let redactedText: String
    let outcome: PrivacyOutcome
    let findingsSummary: String
    let matchedCategories: [PrivacyCategory]
    let severity: PrivacySeverity
    let backend: PrivacyBackendKind
    let modelVersion: String
    let inputHash: String
    let deliveredHash: String?
    let approvalContext: PrivacyApprovalContext?
}

public actor PrivacyPreflightCoordinator {
    private let store: PrivacyStore
    private let defaultStorageURL: URL
    private let rulesOnlyBackend: RulesOnlyPrivacyBackend
    private let officialCLIBackend: OfficialCLIPrivacyBackend
    private let mlxBackend = PlaceholderPrivacyBackend(
        kind: .mlx,
        note: "MLX backend is reserved for a later native runtime implementation."
    )
    private let coreMLBackend = PlaceholderPrivacyBackend(
        kind: .coreML,
        note: "Core ML backend is reserved for a later production experiment."
    )
    private var lastError: String?

    init(
        store: PrivacyStore,
        defaultStorageURL: URL,
        rulesOnlyBackend: RulesOnlyPrivacyBackend = RulesOnlyPrivacyBackend(),
        officialCLIBackend: OfficialCLIPrivacyBackend? = nil
    ) {
        self.store = store
        self.defaultStorageURL = defaultStorageURL
        self.rulesOnlyBackend = rulesOnlyBackend
        self.officialCLIBackend = officialCLIBackend ?? OfficialCLIPrivacyBackend(storageURL: defaultStorageURL)
    }

    public func settingsBundle() async throws -> PrivacySettingsBundle {
        try PrivacySettingsBundle(
            settings: await store.settings(defaultStoragePath: defaultStorageURL.path),
            claudePolicy: await store.policy(for: .cowork),
            codexPolicy: await store.policy(for: .codex)
        )
    }

    public func updateSettings(_ settings: PrivacyPreflightSettings) async throws {
        try await store.upsertSettings(settings)
    }

    public func updatePolicy(_ policy: AgentPrivacyPolicy) async throws {
        try await store.upsertPolicy(policy)
    }

    public func installModel() async throws -> PrivacyRuntimeStatus {
        var settings = try await store.settings(defaultStoragePath: defaultStorageURL.path)
        try FileManager.default.createDirectory(at: defaultStorageURL, withIntermediateDirectories: true)

        switch settings.selectedBackend {
        case .rulesOnly:
            let info = try await rulesOnlyBackend.install()
            settings.isEnabled = true
            settings.installState = .installed
            settings.modelVersion = info.modelVersion
            settings.installedAt = ISO8601DateFormatter.shared.string(from: Date())
            settings.storagePath = defaultStorageURL.path
            try await store.upsertSettings(settings)
            lastError = nil
        case .officialCLI:
            let info = try await officialCLIBackend.install()
            settings.isEnabled = true
            settings.installState = .installed
            settings.modelVersion = info.modelVersion
            settings.installedAt = ISO8601DateFormatter.shared.string(from: Date())
            settings.storagePath = defaultStorageURL.path
            try await store.upsertSettings(settings)
            lastError = nil
        case .mlx, .coreML:
            settings.isEnabled = true
            settings.installState = .downloadRequired
            settings.storagePath = defaultStorageURL.path
            try await store.upsertSettings(settings)
            lastError = "Managed install is not available for \(settings.selectedBackend.displayName) yet. Rules only remains the effective backend."
        }

        return try await runtimeStatus()
    }

    public func uninstallModel() async throws -> PrivacyRuntimeStatus {
        var settings = try await store.settings(defaultStoragePath: defaultStorageURL.path)
        if settings.selectedBackend == .officialCLI {
            try await officialCLIBackend.uninstall()
        }
        settings.isEnabled = false
        settings.installState = .notInstalled
        settings.modelVersion = nil
        settings.installedAt = nil
        try await store.upsertSettings(settings)
        lastError = nil
        return try await runtimeStatus()
    }

    @discardableResult
    public func clearCache() async throws -> Int {
        try await store.clearCache()
    }

    public func runtimeStatus() async throws -> PrivacyRuntimeStatus {
        let settings = try await store.settings(defaultStoragePath: defaultStorageURL.path)
        let effective = await effectiveBackend(for: settings)
        let statuses = try await backendStatuses(for: settings)
        return PrivacyRuntimeStatus(
            featureEnabled: settings.isEnabled,
            selectedBackend: settings.selectedBackend,
            effectiveBackend: effective.kind,
            installState: settings.installState,
            modelLoaded: (await effective.modelInfo()).loaded,
            cacheEntryCount: try await store.cacheEntryCount(),
            lastError: lastError,
            storagePath: settings.storagePath,
            backends: statuses
        )
    }

    func preflight(
        agent: TargetApp,
        toolName: String,
        resourcePath: String?,
        text: String,
        contentKind: PrivacyContentKind,
        accessDecisionID: String?
    ) async throws -> PrivacyDelivery {
        let settings = try await store.settings(defaultStoragePath: defaultStorageURL.path)
        let inputHash = Self.sha256(text)

        guard settings.isEnabled else {
            return PrivacyDelivery(
                deliveredText: text,
                redactedText: text,
                outcome: .clean,
                findingsSummary: "Privacy Preflight is off.",
                matchedCategories: [],
                severity: .none,
                backend: settings.selectedBackend,
                modelVersion: settings.modelVersion ?? "disabled",
                inputHash: inputHash,
                deliveredHash: inputHash,
                approvalContext: nil
            )
        }

        let policy = try await store.policy(for: agent)
        let effective = await effectiveBackend(for: settings)
        let effectiveInfo = await effective.modelInfo()
        let categories = policy.enabledCategories.sorted(by: { $0.rawValue < $1.rawValue })
        let operatingPoint = Self.operatingPoint(policy: policy)

        let scanResult: PrivacyScanResult
        if settings.cacheEnabled,
           let cached = try await store.cachedResult(
                inputHash: inputHash,
                backend: effective.kind,
                modelVersion: effectiveInfo.modelVersion,
                operatingPoint: operatingPoint,
                categories: categories,
                contentKind: contentKind
           ) {
            scanResult = cached
        } else {
            let request = PrivacyScanRequest(
                inputHash: inputHash,
                text: text,
                categories: categories,
                operatingPoint: operatingPoint,
                contentKind: contentKind,
                backend: effective.kind,
                agent: agent,
                resourcePath: resourcePath,
                toolName: toolName
            )
            let scanned = try await scanWithFallback(request: request, preferred: effective)
            if settings.cacheEnabled {
                try await store.cache(
                    scanned,
                    inputHash: inputHash,
                    operatingPoint: operatingPoint,
                    categories: categories,
                    contentKind: contentKind
                )
            }
            scanResult = scanned
        }

        let matchedCategories = Array(Set(scanResult.spans.map(\.category))).sorted(by: { $0.rawValue < $1.rawValue })
        let severity = Self.severity(for: matchedCategories)
        let hasSecrets = matchedCategories.contains(.secret)
        let resourceKey = resourcePath ?? toolName
        let override = try await store.approvalOverride(
            agent: agent,
            resourceKey: resourceKey,
            inputHash: inputHash,
            contentKind: contentKind
        )

        let handling = contentKind.isCodeLike ? policy.codeHandling : policy.textHandling
        let delivery: PrivacyDelivery

        if scanResult.spans.isEmpty {
            delivery = PrivacyDelivery(
                deliveredText: text,
                redactedText: scanResult.redactedText,
                outcome: .clean,
                findingsSummary: scanResult.findingsSummary,
                matchedCategories: matchedCategories,
                severity: severity,
                backend: scanResult.backend,
                modelVersion: scanResult.modelVersion,
                inputHash: inputHash,
                deliveredHash: inputHash,
                approvalContext: nil
            )
        } else if let override {
            switch override {
            case .shareOriginalOnce:
                delivery = PrivacyDelivery(
                    deliveredText: text,
                    redactedText: scanResult.redactedText,
                    outcome: .warning,
                    findingsSummary: scanResult.findingsSummary,
                    matchedCategories: matchedCategories,
                    severity: severity,
                    backend: scanResult.backend,
                    modelVersion: scanResult.modelVersion,
                    inputHash: inputHash,
                    deliveredHash: inputHash,
                    approvalContext: nil
                )
            case .shareRedacted:
                delivery = PrivacyDelivery(
                    deliveredText: scanResult.redactedText,
                    redactedText: scanResult.redactedText,
                    outcome: .filtered,
                    findingsSummary: scanResult.findingsSummary,
                    matchedCategories: matchedCategories,
                    severity: severity,
                    backend: scanResult.backend,
                    modelVersion: scanResult.modelVersion,
                    inputHash: inputHash,
                    deliveredHash: Self.sha256(scanResult.redactedText),
                    approvalContext: nil
                )
            }
        } else if hasSecrets && policy.secretHandling == .block {
            delivery = PrivacyDelivery(
                deliveredText: nil,
                redactedText: scanResult.redactedText,
                outcome: .blocked,
                findingsSummary: scanResult.findingsSummary,
                matchedCategories: matchedCategories,
                severity: severity,
                backend: scanResult.backend,
                modelVersion: scanResult.modelVersion,
                inputHash: inputHash,
                deliveredHash: nil,
                approvalContext: nil
            )
        } else if hasSecrets && policy.secretHandling == .ask {
            delivery = PrivacyDelivery(
                deliveredText: nil,
                redactedText: scanResult.redactedText,
                outcome: .approvalRequired,
                findingsSummary: scanResult.findingsSummary,
                matchedCategories: matchedCategories,
                severity: severity,
                backend: scanResult.backend,
                modelVersion: scanResult.modelVersion,
                inputHash: inputHash,
                deliveredHash: nil,
                approvalContext: makeApprovalContext(
                    toolName: toolName,
                    contentKind: contentKind,
                    inputHash: inputHash,
                    scanResult: scanResult,
                    recommendation: "Share redacted unless the exact original is required."
                )
            )
        } else {
            switch handling {
            case .off:
                delivery = PrivacyDelivery(
                    deliveredText: text,
                    redactedText: scanResult.redactedText,
                    outcome: .clean,
                    findingsSummary: scanResult.findingsSummary,
                    matchedCategories: matchedCategories,
                    severity: severity,
                    backend: scanResult.backend,
                    modelVersion: scanResult.modelVersion,
                    inputHash: inputHash,
                    deliveredHash: inputHash,
                    approvalContext: nil
                )
            case .warn:
                delivery = PrivacyDelivery(
                    deliveredText: text,
                    redactedText: scanResult.redactedText,
                    outcome: .warning,
                    findingsSummary: scanResult.findingsSummary,
                    matchedCategories: matchedCategories,
                    severity: severity,
                    backend: scanResult.backend,
                    modelVersion: scanResult.modelVersion,
                    inputHash: inputHash,
                    deliveredHash: inputHash,
                    approvalContext: nil
                )
            case .redact:
                delivery = PrivacyDelivery(
                    deliveredText: scanResult.redactedText,
                    redactedText: scanResult.redactedText,
                    outcome: .filtered,
                    findingsSummary: scanResult.findingsSummary,
                    matchedCategories: matchedCategories,
                    severity: severity,
                    backend: scanResult.backend,
                    modelVersion: scanResult.modelVersion,
                    inputHash: inputHash,
                    deliveredHash: Self.sha256(scanResult.redactedText),
                    approvalContext: nil
                )
            case .ask:
                delivery = PrivacyDelivery(
                    deliveredText: nil,
                    redactedText: scanResult.redactedText,
                    outcome: .approvalRequired,
                    findingsSummary: scanResult.findingsSummary,
                    matchedCategories: matchedCategories,
                    severity: severity,
                    backend: scanResult.backend,
                    modelVersion: scanResult.modelVersion,
                    inputHash: inputHash,
                    deliveredHash: nil,
                    approvalContext: makeApprovalContext(
                        toolName: toolName,
                        contentKind: contentKind,
                        inputHash: inputHash,
                        scanResult: scanResult,
                        recommendation: "Review before sharing original code-like content."
                    )
                )
            }
        }

        if let accessDecisionID, delivery.outcome != .clean {
            try await store.recordEvent(
                PrivacyScanEventRecord(
                    accessDecisionID: accessDecisionID,
                    agent: agent,
                    toolName: toolName,
                    resourcePath: resourcePath,
                    backend: delivery.backend,
                    modelVersion: delivery.modelVersion,
                    contentKind: contentKind,
                    inputHash: delivery.inputHash,
                    deliveredHash: delivery.deliveredHash,
                    outcome: delivery.outcome,
                    findingsSummary: delivery.findingsSummary,
                    findingsCount: scanResult.spans.count,
                    matchedCategories: delivery.matchedCategories
                )
            )
        }

        return delivery
    }

    private func scanWithFallback(
        request: PrivacyScanRequest,
        preferred: any PrivacyBackend
    ) async throws -> PrivacyScanResult {
        do {
            return try await preferred.scan(request)
        } catch {
            guard preferred.kind != .rulesOnly else { throw error }
            lastError = error.localizedDescription
            return try await rulesOnlyBackend.scan(
                PrivacyScanRequest(
                    inputHash: request.inputHash,
                    text: request.text,
                    categories: request.categories,
                    operatingPoint: request.operatingPoint,
                    contentKind: request.contentKind,
                    backend: .rulesOnly,
                    agent: request.agent,
                    resourcePath: request.resourcePath,
                    toolName: request.toolName
                )
            )
        }
    }

    private func effectiveBackend(for settings: PrivacyPreflightSettings) async -> any PrivacyBackend {
        let selected = backend(for: settings.selectedBackend)
        let info = await selected.modelInfo()
        switch settings.selectedBackend {
        case .rulesOnly:
            return rulesOnlyBackend
        case .officialCLI, .mlx, .coreML:
            if settings.installState == .installed && info.available {
                return selected
            }
            return rulesOnlyBackend
        }
    }

    private func backendStatuses(for settings: PrivacyPreflightSettings) async throws -> [PrivacyBackendStatus] {
        var statuses: [PrivacyBackendStatus] = []
        for kind in PrivacyBackendKind.allCases {
            let backend = backend(for: kind)
            let info = await backend.modelInfo()
            let installed: Bool
            if kind == .rulesOnly {
                installed = settings.installState == .installed && settings.selectedBackend == .rulesOnly
            } else {
                installed = settings.installState == .installed && settings.selectedBackend == kind
            }
            statuses.append(
                PrivacyBackendStatus(
                    kind: kind,
                    available: info.available,
                    installed: installed,
                    note: info.note
                )
            )
        }
        return statuses
    }

    private func backend(for kind: PrivacyBackendKind) -> any PrivacyBackend {
        switch kind {
        case .rulesOnly:
            return rulesOnlyBackend
        case .officialCLI:
            return officialCLIBackend
        case .mlx:
            return mlxBackend
        case .coreML:
            return coreMLBackend
        }
    }

    private func makeApprovalContext(
        toolName: String,
        contentKind: PrivacyContentKind,
        inputHash: String,
        scanResult: PrivacyScanResult,
        recommendation: String
    ) -> PrivacyApprovalContext {
        PrivacyApprovalContext(
            toolName: toolName,
            contentKind: contentKind,
            inputHash: inputHash,
            findingsSummary: scanResult.findingsSummary,
            matchedCategories: Array(Set(scanResult.spans.map(\.category))).sorted(by: { $0.rawValue < $1.rawValue }),
            redactedPreview: String(scanResult.redactedText.prefix(280)),
            recommendation: recommendation
        )
    }

    private static func operatingPoint(policy: AgentPrivacyPolicy) -> String {
        [
            "text:\(policy.textHandling.rawValue)",
            "code:\(policy.codeHandling.rawValue)",
            "secret:\(policy.secretHandling.rawValue)",
        ].joined(separator: "|")
    }

    private static func severity(for categories: [PrivacyCategory]) -> PrivacySeverity {
        if categories.contains(.secret) {
            return .critical
        }
        if categories.contains(.accountNumber) {
            return .high
        }

        let contactCategoryCount = categories.filter {
            [.privatePerson, .email, .phone, .address].contains($0)
        }.count
        if contactCategoryCount > 1 {
            return .high
        }
        if contactCategoryCount == 1 {
            return .medium
        }
        if categories.contains(.url) || categories.contains(.date) {
            return .low
        }
        return .none
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
