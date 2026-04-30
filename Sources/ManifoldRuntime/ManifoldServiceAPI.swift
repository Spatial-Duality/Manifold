// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public protocol ManifoldServiceAPI: Sendable {
    func connect(
        agent: String,
        clientName: String?,
        clientVersion: String?,
        initializeParams: [String: Any]
    ) async throws -> String

    func disconnect(connectionID: String) async

    func getStatus(connectionID: String) async throws -> RuntimeStatus
    func listTrustedFolders(agent: String) async throws -> [TrustedFolder]

    func listFiles(connectionID: String) async throws -> [FileEntry]
    func readFile(connectionID: String, path: String) async throws -> FileContent
    func readRange(connectionID: String, path: String, startLine: Int, endLine: Int) async throws -> FileContent
    func searchFiles(connectionID: String, query: String) async throws -> [SearchHit]
    func searchStructured(connectionID: String, query: String, limit: Int) async throws -> String
    func fileInfo(connectionID: String, path: String) async throws -> FileMetadata
    func diffFile(connectionID: String, path: String) async throws -> String
    func listArchive(connectionID: String, path: String) async throws -> [String]
    func extractFile(connectionID: String, archivePath: String, filePath: String) async throws -> String

    func writeFile(connectionID: String, path: String, content: String) async throws -> WriteResult
    func writeBinaryFile(
        connectionID: String,
        path: String,
        contentBase64: String,
        mimeType: String?,
        expectedBeforeHash: String?,
        writeMode: String?
    ) async throws -> WriteResult
    func annotatePDF(
        connectionID: String,
        path: String,
        mark: String,
        expectedBeforeHash: String?,
        writeMode: String?
    ) async throws -> WriteResult

    func startGatewaySession(connectionID: String, folderIDs: [String], fileScopes: [FileScope], emailIDs: [String]) async throws -> GatewaySession
    func pauseGatewaySession(connectionID: String) async throws
    func resumeGatewaySession(connectionID: String) async throws
    func endGatewaySession(connectionID: String) async throws
    func listChanges(connectionID: String) async throws -> [ChangeEntry]

    func listEmails(connectionID: String) async throws -> [EmailEntry]
    func readEmail(connectionID: String, id: String) async throws -> EmailContent
    func requestEmailReveal(connectionID: String, emailID: String) async throws -> RevealResult

    func listSessions(connectionID: String, limit: Int) async throws -> [SessionEntry]
    func getSession(connectionID: String, grantID: String) async throws -> SessionDetail
    func saveSessionNote(connectionID: String, note: String, noteType: String) async throws -> String

    func pauseAgent(_ agent: String) async throws
    func resumeAgent(_ agent: String) async throws
    func updateAlwaysOnAccess(
        agent: String,
        addFolders: [String],
        removeFolders: [String],
        addEmailDomains: [String],
        removeEmailDomains: [String],
        sensitivity: String?
    ) async throws

    func listApprovalRequests() async throws -> [ApprovalRequest]
    func approveRequest(id: String) async throws
    func denyRequest(id: String) async throws

    func explainDecision(connectionID: String, path: String, action: String) async throws -> AccessExplanation
    func exposureLog(connectionID: String, limit: Int) async throws -> [ExposureEntry]
    func recentActivity(limit: Int) async throws -> [AuditEntry]
}
