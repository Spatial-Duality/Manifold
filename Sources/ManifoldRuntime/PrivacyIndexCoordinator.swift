// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import ManifoldKit

public actor PrivacyIndexCoordinator {
    private let store: PrivacyStore
    private let grantStore: GrantStore
    private let emailStore: EmailStore
    private let emailSyncEngine: EmailSyncEngine
    private let defaultStoragePath: String
    private let rulesOnlyBackend: RulesOnlyPrivacyBackend
    private let mlxBackend: MLXPrivacyBackend
    private let extractor = PrivacyContentExtractor()
    private let identityRegistry: PrivacyIdentityRegistryActor
    private let decisionEngine = PrivacyDecisionEngine()

    private var sourceWatchers: [String: PrivacySourceWatcher] = [:]
    private var processingTask: Task<Void, Never>?
    private var emailIndexer: PrivacyEmailIndexer?
    private var lastError: String?
    private var hasBootstrapped = false

    init(
        store: PrivacyStore,
        grantStore: GrantStore,
        emailStore: EmailStore,
        emailSyncEngine: EmailSyncEngine,
        defaultStoragePath: String,
        rulesOnlyBackend: RulesOnlyPrivacyBackend,
        mlxBackend: MLXPrivacyBackend
    ) {
        self.store = store
        self.grantStore = grantStore
        self.emailStore = emailStore
        self.emailSyncEngine = emailSyncEngine
        self.defaultStoragePath = defaultStoragePath
        self.rulesOnlyBackend = rulesOnlyBackend
        self.mlxBackend = mlxBackend
        self.identityRegistry = PrivacyIdentityRegistryActor(store: store, emailStore: emailStore, grantStore: grantStore)
    }

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        do {
            try await identityRegistry.refresh()
            try await identityRegistry.refreshSuggestions()
            try await reconcileSources()
            try await enqueueBaselineEmails()
            try seedPrivacySmartMailboxes()
            await startEmailIndexer()
            startProcessingLoopIfNeeded()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func reconcileSources() async throws {
        let sources = try await grantStore.allSources().filter { $0.isAccessible && !$0.isRemoved }
        let activeIDs = Set(sources.map(\.sourceID))

        for (sourceID, watcher) in sourceWatchers where !activeIDs.contains(sourceID) {
            await watcher.stop()
            sourceWatchers.removeValue(forKey: sourceID)
        }

        for source in sources {
            if sourceWatchers[source.sourceID] == nil {
                sourceWatchers[source.sourceID] = PrivacySourceWatcher(source: source) { [weak self] paths in
                    await self?.handleSourceEvents(source: source, changedPaths: paths)
                }
                try await enqueueBaselineForSource(source)
            }
        }
    }

    public func runtimeStatus() async throws -> PrivacyIndexRuntimeStatus {
        let settings = try await store.settings(defaultStoragePath: defaultStoragePath)
        let counters = try await store.indexRuntimeCounters()
        return PrivacyIndexRuntimeStatus(
            enabled: settings.isEnabled,
            queuedJobs: counters.queued,
            runningJobs: counters.running,
            failedJobs: counters.failed,
            indexedItems: counters.indexed,
            staleItems: counters.stale,
            watchedSources: sourceWatchers.keys.sorted(),
            lastError: lastError
        )
    }

    public func listIndex(
        scope: PrivacyIndexScope,
        filter: PrivacyIndexFilter,
        limit: Int
    ) async throws -> [PrivacyIndexRecord] {
        try await store.listContentIndex(scope: scope, filter: filter, limit: limit)
    }

    public func listIdentitySuggestions() async throws -> [PrivacyIdentitySuggestion] {
        try await identityRegistry.suggestions()
    }

    public func acceptIdentitySuggestion(id: String) async throws {
        try await identityRegistry.acceptSuggestion(id: id)
    }

    public func rejectIdentitySuggestion(id: String) async throws {
        try await identityRegistry.rejectSuggestion(id: id)
    }

    public func upsertIdentity(_ record: PrivacyIdentityRecord) async throws {
        try await identityRegistry.upsertIdentity(record)
    }

    public func upsertOrgAllowEntry(_ entry: PrivacyOrgAllowEntry) async throws {
        try await identityRegistry.upsertAllowEntry(entry)
    }

    public func listIdentities() async throws -> [PrivacyIdentityRecord] {
        try await store.identities(enabledOnly: false)
    }

    public func listOrgAllowEntries() async throws -> [PrivacyOrgAllowEntry] {
        try await store.orgAllowlistEntries(enabledOnly: false)
    }

    public func deleteIdentity(id: String) async throws {
        try await store.deleteIdentity(id: id)
        try await identityRegistry.refresh()
    }

    public func deleteOrgAllowEntry(id: String) async throws {
        try await store.deleteOrgAllowEntry(id: id)
        try await identityRegistry.refresh()
    }

    public func rescan(contentIDs: [String]) async throws {
        for contentID in contentIDs {
            _ = try await store.enqueueIndexJob(
                PrivacyIndexJobRecord(contentID: contentID, reason: "manual_rescan", priority: 0)
            )
        }
        startProcessingLoopIfNeeded()
    }

    public func sourceDidChange() async throws {
        try await reconcileSources()
    }

    func recordEmailEvent(_ event: EmailSyncEvent) async throws {
        if let email = try emailStore.emailMessage(id: event.emailID) {
            try await enqueueEmailBody(email, reason: "email_sync", priority: 1)
        }
        let attachments = try emailStore.emailAttachments(emailIDs: [event.emailID])
        for attachment in attachments where event.attachmentIDs.isEmpty || event.attachmentIDs.contains(attachment.attachmentID) {
            try await enqueueEmailAttachment(attachment, reason: "email_sync", priority: 1)
        }
        startProcessingLoopIfNeeded()
    }

    private func startEmailIndexer() async {
        guard emailIndexer == nil else { return }
        emailIndexer = PrivacyEmailIndexer(emailSyncEngine: emailSyncEngine) { [weak self] event in
            try await self?.recordEmailEvent(event)
        }
        await emailIndexer?.start()
    }

    private func startProcessingLoopIfNeeded() {
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in
            await self?.runProcessingLoop()
        }
    }

    private func runProcessingLoop() async {
        while !Task.isCancelled {
            do {
                let settings = try await store.settings(defaultStoragePath: defaultStoragePath)
                guard settings.isEnabled else {
                    try await Task.sleep(for: .seconds(1))
                    continue
                }

                let jobs = try await store.pendingIndexJobs(limit: 12)
                guard !jobs.isEmpty else {
                    try await Task.sleep(for: .milliseconds(400))
                    continue
                }

                try await store.markIndexJobsRunning(ids: jobs.map(\.id))
                let prepared = try await jobs.asyncCompactMap { [self] in
                    try await self.prepare(job: $0)
                }

                let singlePass = prepared.filter { !$0.requiresSegmentation }
                let segmented = prepared.filter(\.requiresSegmentation)

                for batch in batched(singlePass.sorted(by: { $0.text.count < $1.text.count }), size: 8) {
                    try await processBatch(batch, settings: settings)
                }

                for item in segmented {
                    try await processSingle(item, settings: settings)
                }
            } catch {
                lastError = error.localizedDescription
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func processBatch(
        _ batch: [PreparedPrivacyJob],
        settings: PrivacyPreflightSettings
    ) async throws {
        guard !batch.isEmpty else { return }
        let backend = await effectiveBackend(for: settings)
        let requests = batch.map(\.request)
        let results = try await backend.scanBatch(requests)
        for (item, result) in zip(batch, results) {
            try await finish(item: item, scanResult: result)
        }
    }

    private func processSingle(
        _ item: PreparedPrivacyJob,
        settings: PrivacyPreflightSettings
    ) async throws {
        let scanResult = try await scanItem(item, settings: settings)
        try await finish(item: item, scanResult: scanResult)
    }

    private func finish(item: PreparedPrivacyJob, scanResult: PrivacyScanResult) async throws {
        let identityMatches = try await identityRegistry.match(text: item.text)
        let allowMatches = try await identityRegistry.matchAllowlist(text: item.text)
        let decision = decisionEngine.merge(
            text: item.text,
            modelResult: scanResult,
            identityMatches: identityMatches,
            allowMatches: allowMatches
        )
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let spanRecords = decision.spanRecords.map { span in
            PrivacySpanRecord(
                id: span.id,
                contentID: item.record.id,
                category: span.category,
                startUTF16: span.startUTF16,
                endUTF16: span.endUTF16,
                confidence: span.confidence,
                source: span.source,
                placeholder: span.placeholder,
                textHash: span.textHash,
                createdAt: span.createdAt
            )
        }
        var updated = item.record
        updated.extractor = item.extraction.extractor
        updated.extractStatus = item.extraction.extractStatus
        updated.scanStatus = .scanned
        updated.contentHash = item.extraction.contentHash
        updated.backend = scanResult.backend
        updated.modelVersion = scanResult.modelVersion
        updated.containsSensitive = decision.containsSensitive
        updated.containsMyInfo = decision.containsMyInfo
        updated.containsThirdPartyPrivate = decision.containsThirdPartyPrivate
        updated.containsSecret = decision.containsSecret
        updated.containsOrgOnly = decision.containsOrgOnly
        updated.severity = decision.severity
        updated.matchedCategories = decision.matchedCategories
        updated.matchedIdentityIDs = decision.matchedIdentityIDs
        updated.matchedAllowIDs = decision.matchedAllowIDs
        updated.redactedPreview = decision.redactedPreview
        updated.findingsSummary = decision.findingsSummary
        updated.spanCount = spanRecords.count
        updated.lastScannedAt = now
        updated.updatedAt = now
        updated.lastError = item.extraction.lastError

        try await store.upsertContentIndexRecord(updated)
        try await store.replaceSpans(for: item.record.id, spans: spanRecords)
        try await store.markIndexJobCompleted(id: item.job.id)
    }

    private func prepare(job: PrivacyIndexJobRecord) async throws -> PreparedPrivacyJob? {
        guard var record = try await store.contentIndexRecord(id: job.contentID) else {
            try await store.markIndexJobFailed(id: job.id, error: "Content record is missing.")
            return nil
        }

        let extraction = try await extraction(for: record)
        guard let text = extraction.text, !text.isEmpty else {
            record.extractor = extraction.extractor
            record.extractStatus = extraction.extractStatus
            record.scanStatus = .failed
            record.contentHash = extraction.contentHash
            record.updatedAt = ISO8601DateFormatter.shared.string(from: Date())
            record.lastError = extraction.lastError
            try await store.upsertContentIndexRecord(record)
            try await store.markIndexJobFailed(id: job.id, error: extraction.lastError ?? "No text was extracted.")
            return nil
        }

        if record.scanStatus == .scanned,
           record.contentHash == extraction.contentHash,
           job.reason != "manual_rescan" {
            try await store.markIndexJobCompleted(id: job.id)
            return nil
        }

        record.extractor = extraction.extractor
        record.extractStatus = extraction.extractStatus
        record.scanStatus = .running
        record.contentHash = extraction.contentHash
        record.updatedAt = ISO8601DateFormatter.shared.string(from: Date())
        record.lastError = extraction.lastError
        try await store.upsertContentIndexRecord(record)

        return PreparedPrivacyJob(
            job: job,
            record: record,
            extraction: extraction,
            text: text,
            request: PrivacyScanRequest(
                inputHash: sha256(text),
                text: text,
                categories: PrivacyCategory.allCases,
                operatingPoint: job.reason == "backfill" ? "high-recall" : "balanced",
                contentKind: contentKind(for: record.subjectKind),
                backend: .mlx,
                agent: .codex,
                resourcePath: record.relativePath ?? record.emailID ?? record.attachmentID,
                toolName: "privacy_index"
            )
        )
    }

    private func extraction(for record: PrivacyIndexRecord) async throws -> PrivacyExtractionResult {
        switch record.subjectKind {
        case .sourceFile:
            guard let sourceID = record.sourceID,
                  let relativePath = record.relativePath,
                  let source = try await grantStore.source(id: sourceID) else {
                return PrivacyExtractionResult(
                    text: nil,
                    mimeType: record.mimeType,
                    extractor: "source-file",
                    extractStatus: .failed,
                    contentHash: nil,
                    lastError: "Source file metadata is incomplete."
                )
            }
            return await extractor.extractSourceFile(source: source, relativePath: relativePath)
        case .emailBody:
            guard let emailID = record.emailID,
                  let email = try emailStore.emailMessage(id: emailID) else {
                return PrivacyExtractionResult(
                    text: nil,
                    mimeType: record.mimeType,
                    extractor: "email-body",
                    extractStatus: .failed,
                    contentHash: nil,
                    lastError: "Email is missing."
                )
            }
            return await extractor.extractEmailBody(email)
        case .emailAttachment:
            guard let emailID = record.emailID,
                  let attachmentID = record.attachmentID,
                  let email = try emailStore.emailMessage(id: emailID),
                  let attachment = try emailStore.emailAttachment(id: attachmentID) else {
                return PrivacyExtractionResult(
                    text: nil,
                    mimeType: record.mimeType,
                    extractor: "email-attachment",
                    extractStatus: .failed,
                    contentHash: nil,
                    lastError: "Attachment is missing."
                )
            }
            return await extractor.extractEmailAttachment(attachment, email: email)
        }
    }

    private func scanItem(
        _ item: PreparedPrivacyJob,
        settings: PrivacyPreflightSettings
    ) async throws -> PrivacyScanResult {
        guard item.requiresSegmentation else {
            let backend = await effectiveBackend(for: settings)
            return try await backend.scan(item.request)
        }

        let backend = await effectiveBackend(for: settings)
        let segments = segments(for: item.text)
        var mergedSpans: [DetectedSpan] = []
        var redacted = item.text
        var elapsedMs = 0
        for segment in segments {
            let segmentRequest = PrivacyScanRequest(
                inputHash: sha256(segment.text),
                text: segment.text,
                categories: item.request.categories,
                operatingPoint: item.request.operatingPoint,
                contentKind: item.request.contentKind,
                backend: item.request.backend,
                agent: item.request.agent,
                resourcePath: item.request.resourcePath,
                toolName: item.request.toolName
            )
            let result = try await backend.scan(segmentRequest)
            elapsedMs += result.elapsedMs
            mergedSpans.append(
                contentsOf: result.spans.map { span in
                    DetectedSpan(
                        startUTF16: span.startUTF16 + segment.offsetUTF16,
                        endUTF16: span.endUTF16 + segment.offsetUTF16,
                        category: span.category,
                        confidence: span.confidence,
                        textPreview: span.textPreview,
                        replacement: span.replacement
                    )
                }
            )
        }
        mergedSpans = mergedSpans.sorted(by: {
            if $0.startUTF16 != $1.startUTF16 { return $0.startUTF16 < $1.startUTF16 }
            return $0.endUTF16 < $1.endUTF16
        })
        redacted = redact(text: item.text, spans: mergedSpans)
        return PrivacyScanResult(
            spans: mergedSpans,
            redactedText: redacted,
            findingsSummary: "\(mergedSpans.count) spans detected",
            backend: backend.kind,
            modelVersion: settings.modelVersion ?? "privacy-index",
            elapsedMs: elapsedMs,
            cacheHit: false
        )
    }

    private func effectiveBackend(for settings: PrivacyPreflightSettings) async -> any PrivacyBackend {
        if settings.selectedBackend == .mlx,
           settings.installState == .installed,
           (await mlxBackend.modelInfo()).available {
            return mlxBackend
        }
        return rulesOnlyBackend
    }

    private func enqueueBaselineForSource(_ source: SourceRecord) async throws {
        let root = Self.canonicalFileURL(URL(fileURLWithPath: source.originalRootPath))
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let basePath = root.path + "/"
        while let url = enumerator.nextObject() as? URL {
            let canonicalURL = Self.canonicalFileURL(url)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard canonicalURL.path.hasPrefix(basePath) else { continue }
            let relativePath = String(canonicalURL.path.dropFirst(basePath.count))
            try await enqueueSourceFile(source: source, relativePath: relativePath, reason: "backfill", priority: 4)
        }
    }

    private func enqueueBaselineEmails() async throws {
        let emails = try emailStore.allEmailMessages(limit: 50_000)
        for email in emails {
            try await enqueueEmailBody(email, reason: "backfill", priority: 4)
        }
        let attachments = try emailStore.emailAttachments()
        for attachment in attachments {
            try await enqueueEmailAttachment(attachment, reason: "backfill", priority: 4)
        }
    }

    private func enqueueSourceFile(
        source: SourceRecord,
        relativePath: String,
        reason: String,
        priority: Int
    ) async throws {
        let contentID = Self.contentIDForSource(sourceID: source.sourceID, relativePath: relativePath)
        try await store.upsertContentIndexRecord(
            PrivacyIndexRecord(
                id: contentID,
                subjectKind: .sourceFile,
                sourceID: source.sourceID,
                relativePath: relativePath,
                displayName: URL(fileURLWithPath: relativePath).lastPathComponent,
                extractStatus: .pending,
                scanStatus: .queued,
                updatedAt: ISO8601DateFormatter.shared.string(from: Date())
            )
        )
        _ = try await store.enqueueIndexJob(
            PrivacyIndexJobRecord(contentID: contentID, reason: reason, priority: priority)
        )
    }

    private func enqueueEmailBody(
        _ email: EmailMessageRecord,
        reason: String,
        priority: Int
    ) async throws {
        let contentID = Self.contentIDForEmailBody(emailID: email.emailID)
        try await store.upsertContentIndexRecord(
            PrivacyIndexRecord(
                id: contentID,
                subjectKind: .emailBody,
                emailID: email.emailID,
                displayName: email.subject,
                mimeType: email.contentType,
                extractStatus: .pending,
                scanStatus: .queued,
                updatedAt: ISO8601DateFormatter.shared.string(from: Date())
            )
        )
        _ = try await store.enqueueIndexJob(
            PrivacyIndexJobRecord(contentID: contentID, reason: reason, priority: priority)
        )
    }

    private func enqueueEmailAttachment(
        _ attachment: EmailAttachmentRecord,
        reason: String,
        priority: Int
    ) async throws {
        let contentID = Self.contentIDForAttachment(attachmentID: attachment.attachmentID)
        try await store.upsertContentIndexRecord(
            PrivacyIndexRecord(
                id: contentID,
                subjectKind: .emailAttachment,
                emailID: attachment.emailID,
                attachmentID: attachment.attachmentID,
                displayName: attachment.filename,
                mimeType: attachment.mimeType,
                extractStatus: .pending,
                scanStatus: .queued,
                updatedAt: ISO8601DateFormatter.shared.string(from: Date())
            )
        )
        _ = try await store.enqueueIndexJob(
            PrivacyIndexJobRecord(contentID: contentID, reason: reason, priority: priority)
        )
    }

    private func handleSourceEvents(source: SourceRecord, changedPaths: [String]) async {
        let root = Self.canonicalFileURL(URL(fileURLWithPath: source.originalRootPath))
        for path in changedPaths {
            let url = Self.canonicalFileURL(URL(fileURLWithPath: path))
            guard url.path.hasPrefix(root.path) else { continue }
            let relativePath = Self.relativePath(file: url, base: root)
            if FileManager.default.fileExists(atPath: url.path) {
                try? await enqueueSourceFile(source: source, relativePath: relativePath, reason: "file_change", priority: 2)
            } else {
                let contentID = Self.contentIDForSource(sourceID: source.sourceID, relativePath: relativePath)
                try? await store.deleteContentIndex(contentID: contentID)
            }
        }
        startProcessingLoopIfNeeded()
    }

    private func seedPrivacySmartMailboxes() throws {
        let existing = Set(try emailStore.allSmartMailboxes().map(\.displayName))
        let definitions: [(String, SmartMailboxRules)] = [
            ("Has My Info", SmartMailboxRules(match: .all, conditions: [RuleCondition(field: "privacy_contains_my_info", op: .equals, value: "true")])),
            ("Has Secret", SmartMailboxRules(match: .all, conditions: [RuleCondition(field: "privacy_contains_secret", op: .equals, value: "true")])),
            ("Third-Party Private", SmartMailboxRules(match: .all, conditions: [RuleCondition(field: "privacy_contains_third_party_private", op: .equals, value: "true")])),
            ("Org Only", SmartMailboxRules(match: .all, conditions: [RuleCondition(field: "privacy_contains_org_only", op: .equals, value: "true")])),
            ("Needs Review", SmartMailboxRules(match: .all, conditions: [RuleCondition(field: "privacy_contains_sensitive", op: .equals, value: "true")])),
        ]

        for (name, rules) in definitions where !existing.contains(name) {
            try emailStore.createSmartMailbox(
                displayName: name,
                iconName: "shield.lefthalf.filled",
                rulesJSON: rules.toJSON() ?? "[]"
            )
        }
    }

    private func segments(for text: String) -> [Segment] {
        let maxCharacters = 320_000
        let overlap = 8_000
        guard text.count > maxCharacters else {
            return [Segment(text: text, offsetUTF16: 0)]
        }

        var segments: [Segment] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxCharacters, limitedBy: text.endIndex) ?? text.endIndex
            let segmentText = String(text[start..<end])
            let offsetUTF16 = text.utf16.distance(from: text.utf16.startIndex, to: start.samePosition(in: text.utf16)!)
            segments.append(Segment(text: segmentText, offsetUTF16: offsetUTF16))
            if end == text.endIndex { break }
            start = text.index(end, offsetBy: -overlap, limitedBy: text.startIndex) ?? text.startIndex
        }
        return segments
    }

    private func redact(text: String, spans: [DetectedSpan]) -> String {
        var output = text
        for span in spans.sorted(by: { $0.startUTF16 > $1.startUTF16 }) {
            let start = String.Index(utf16Offset: span.startUTF16, in: output)
            let end = String.Index(utf16Offset: span.endUTF16, in: output)
            output.replaceSubrange(start..<end, with: span.replacement)
        }
        return output
    }

    private func batched<T>(_ values: [T], size: Int) -> [[T]] {
        stride(from: 0, to: values.count, by: size).map { start in
            Array(values[start..<min(start + size, values.count)])
        }
    }

    private func contentKind(for subjectKind: PrivacyIndexedContentKind) -> PrivacyContentKind {
        switch subjectKind {
        case .sourceFile:
            return .document
        case .emailBody:
            return .email
        case .emailAttachment:
            return .document
        }
    }

    private func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func contentIDForSource(sourceID: String, relativePath: String) -> String {
        "source:\(sourceID):\(relativePath)"
    }

    private static func contentIDForEmailBody(emailID: String) -> String {
        "email:\(emailID):body"
    }

    private static func contentIDForAttachment(attachmentID: String) -> String {
        "attachment:\(attachmentID)"
    }

    private static func relativePath(file: URL, base: URL) -> String {
        let filePath = Self.canonicalFileURL(file).path
        let basePath = Self.canonicalFileURL(base).path + "/"
        if filePath.hasPrefix(basePath) {
            return String(filePath.dropFirst(basePath.count))
        }
        return file.lastPathComponent
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

private struct PreparedPrivacyJob: Sendable {
    let job: PrivacyIndexJobRecord
    let record: PrivacyIndexRecord
    let extraction: PrivacyExtractionResult
    let text: String
    let request: PrivacyScanRequest

    var requiresSegmentation: Bool {
        text.count > 320_000
    }
}

private struct Segment: Sendable {
    let text: String
    let offsetUTF16: Int
}

private actor PrivacyEmailIndexer {
    private let emailSyncEngine: EmailSyncEngine
    private let handler: @Sendable (EmailSyncEvent) async throws -> Void
    private var task: Task<Void, Never>?

    init(
        emailSyncEngine: EmailSyncEngine,
        handler: @escaping @Sendable (EmailSyncEvent) async throws -> Void
    ) {
        self.emailSyncEngine = emailSyncEngine
        self.handler = handler
    }

    func start() {
        guard task == nil else { return }
        task = Task {
            for await event in await emailSyncEngine.events() {
                try? await handler(event)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

private extension Array {
    func asyncCompactMap<T: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> T?
    ) async throws -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            if let value = try await transform(element) {
                values.append(value)
            }
        }
        return values
    }
}
