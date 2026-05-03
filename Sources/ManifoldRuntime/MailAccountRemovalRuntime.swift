// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import os

private let mailAccountRemovalLogger = Logger(
    subsystem: "com.spatialduality.manifold",
    category: "mail-account-removal"
)

extension ManifoldRuntime {
    public func removeEmailAccountAndLocalData(accountID: String) async throws -> MailAccountRemovalResult {
        try? await mailSyncCoordinator.pause(accountID: accountID)
        await emailSyncEngine.unregister(accountID: accountID)

        let result = try emailStore.writeAccountRemovalHistory(
            accountID: accountID,
            destinationRoot: mailAccountRemovalHistoryRoot
        )

        let removedArtifacts = try await artifactIndex.deleteMailArtifacts(accountID: accountID)
        if removedArtifacts > 0 {
            mailAccountRemovalLogger.info("Removed \(removedArtifacts) mail artifact index record(s)")
        }

        try emailStore.removeEmailAccount(id: accountID)

        do {
            let archiveStore = try MailArchiveStore(rootURL: mailArchiveRoot)
            try archiveStore.removeAccountArchive(accountID: accountID)
        } catch {
            mailAccountRemovalLogger.error("Failed to remove mail archive directory for \(accountID, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }

        try removeMailSyncTemporaryDirectory(accountID: accountID)
        await privacyIndexCoordinator.bootstrap()

        return result
    }

    private nonisolated func removeMailSyncTemporaryDirectory(accountID: String) throws {
        guard !accountID.isEmpty,
              !accountID.contains("/"),
              !accountID.contains("\\"),
              accountID != ".",
              accountID != ".." else {
            return
        }

        let syncTempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifoldMailSync", isDirectory: true)
        let accountTempURL = syncTempRoot.appendingPathComponent(accountID, isDirectory: true)
        let standardizedRoot = syncTempRoot.standardizedFileURL.path
        let standardizedAccount = accountTempURL.standardizedFileURL.path
        guard standardizedAccount.hasPrefix(standardizedRoot + "/"),
              FileManager.default.fileExists(atPath: accountTempURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: accountTempURL)
    }
}

