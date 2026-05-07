// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ManifoldReliabilityConstants {
    public static let effectiveAccessResolverVersion = "effective-access-snapshot-v1"
}

public struct ManifoldRequestID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String
    public var description: String { rawValue }

    public init(_ rawValue: String = "req-\(UUID().uuidString.prefix(12).lowercased())") {
        self.rawValue = rawValue
    }

    public static func make(jsonRPCID: Any? = nil) -> ManifoldRequestID {
        guard let jsonRPCID else { return ManifoldRequestID() }
        let suffix: String
        switch jsonRPCID {
        case let value as String:
            suffix = value
        case let value as Int:
            suffix = "\(value)"
        case let value as Double:
            suffix = "\(value)"
        default:
            suffix = "\(UUID().uuidString.prefix(8).lowercased())"
        }
        let sanitized = suffix
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return ManifoldRequestID("req-\(String(sanitized).prefix(40))")
    }
}

public struct EffectiveAccessMetadata: Sendable, Codable, Equatable {
    public let snapshotID: String
    public let resolverVersion: String
    public let domain: String
    public let mode: String
    public let sourceCount: Int
    public let workBlockID: String?
    public let sourceIDs: [String]

    public init(
        snapshotID: String,
        resolverVersion: String = ManifoldReliabilityConstants.effectiveAccessResolverVersion,
        domain: String,
        mode: String,
        sourceCount: Int,
        workBlockID: String? = nil,
        sourceIDs: [String] = []
    ) {
        self.snapshotID = snapshotID
        self.resolverVersion = resolverVersion
        self.domain = domain
        self.mode = mode
        self.sourceCount = sourceCount
        self.workBlockID = workBlockID
        self.sourceIDs = sourceIDs
    }
}

public enum MCPFailureBoundary: String, Sendable, Codable, CaseIterable {
    case stdio
    case mcpAdapter = "mcp_adapter"
    case xpcClient = "xpc_client"
    case xpcService = "xpc_service"
    case bridgeResolver = "bridge_resolver"
    case bridgeTool = "bridge_tool"
    case store
    case filesystem
    case privacyFilter = "privacy_filter"
}

public enum MCPFailurePhase: String, Sendable, Codable, CaseIterable {
    case decode
    case connect
    case authorize
    case resolve
    case execute
    case serialize
    case reply
    case disconnect
    case timeout
}

public enum MCPFailureClassification: String, Sendable, Codable, CaseIterable {
    case transportStdinEOF = "transport.stdin_eof"
    case transportMalformedMessage = "transport.malformed_message"
    case xpcRuntimeUnavailable = "xpc.runtime_unavailable"
    case xpcConnectionInvalidated = "xpc.connection_invalidated"
    case xpcReplyMalformed = "xpc.reply_malformed"
    case xpcTimeout = "xpc.timeout"
    case identityVerificationFailed = "identity.verification_failed"
    case accessNoAccessConfigured = "access.no_access_configured"
    case accessPaused = "access.paused"
    case accessSourceUnavailable = "access.source_unavailable"
    case accessScopeStale = "access.scope_stale"
    case pathAmbiguous = "path.ambiguous"
    case pathOutsideRoot = "path.outside_root"
    case privacyBlocked = "privacy.blocked"
    case writeConflict = "write.conflict"
    case storeMigrationMissing = "store.migration_missing"
    case unknown
}

public struct MCPFailureEvent: Sendable, Identifiable, Codable, Equatable {
    public var id: String { eventID }
    public let eventID: String
    public let requestID: String
    public let agent: String
    public let clientName: String?
    public let toolName: String?
    public let boundary: MCPFailureBoundary
    public let phase: MCPFailurePhase
    public let classification: MCPFailureClassification
    public let isRetryable: Bool
    public let redactedMessage: String
    public let connectionID: String?
    public let runtimeGeneration: Int
    public let grantID: String?
    public let focusID: String?
    public let workBlockID: String?
    public let sourceIDs: [String]
    public let durationMS: Double?
    public let timestamp: Double

    public init(
        eventID: String = "mcp-failure-\(UUID().uuidString.prefix(12).lowercased())",
        requestID: String,
        agent: String,
        clientName: String? = nil,
        toolName: String? = nil,
        boundary: MCPFailureBoundary,
        phase: MCPFailurePhase,
        classification: MCPFailureClassification,
        isRetryable: Bool,
        redactedMessage: String,
        connectionID: String? = nil,
        runtimeGeneration: Int = 0,
        grantID: String? = nil,
        focusID: String? = nil,
        workBlockID: String? = nil,
        sourceIDs: [String] = [],
        durationMS: Double? = nil,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.eventID = eventID
        self.requestID = requestID
        self.agent = agent
        self.clientName = clientName
        self.toolName = toolName
        self.boundary = boundary
        self.phase = phase
        self.classification = classification
        self.isRetryable = isRetryable
        self.redactedMessage = redactedMessage
        self.connectionID = connectionID
        self.runtimeGeneration = runtimeGeneration
        self.grantID = grantID
        self.focusID = focusID
        self.workBlockID = workBlockID
        self.sourceIDs = sourceIDs
        self.durationMS = durationMS
        self.timestamp = timestamp
    }
}

public enum RuntimeSupervisorRestartReason: String, Sendable, Codable, CaseIterable {
    case manual
    case runtimeCrash = "runtime_crash"
    case xpcInterrupted = "xpc_interrupted"
    case versionMismatch = "version_mismatch"
    case healthTimeout = "health_timeout"
}

public enum RuntimeSupervisorState: Sendable, Codable, Equatable {
    case stopped
    case starting(generation: Int)
    case healthy(generation: Int)
    case degraded(generation: Int, issue: String)
    case restarting(generation: Int, reason: RuntimeSupervisorRestartReason)
    case failed(generation: Int, issue: String)
}

public struct RuntimeSupervisor: Sendable, Codable, Equatable {
    public private(set) var state: RuntimeSupervisorState
    public private(set) var generation: Int
    public private(set) var consecutiveFailures: Int
    private var automaticRestartUsedForCurrentIssue: Bool

    public init(
        state: RuntimeSupervisorState = .stopped,
        generation: Int = 0,
        consecutiveFailures: Int = 0
    ) {
        self.state = state
        self.generation = generation
        self.consecutiveFailures = consecutiveFailures
        self.automaticRestartUsedForCurrentIssue = false
    }

    @discardableResult
    public mutating func markStarting() -> RuntimeSupervisorState {
        generation += 1
        state = .starting(generation: generation)
        return state
    }

    @discardableResult
    public mutating func markHealthy() -> RuntimeSupervisorState {
        consecutiveFailures = 0
        automaticRestartUsedForCurrentIssue = false
        state = .healthy(generation: generation)
        return state
    }

    @discardableResult
    public mutating func markDegraded(issue: String) -> RuntimeSupervisorState {
        state = .degraded(generation: generation, issue: issue)
        return state
    }

    @discardableResult
    public mutating func markRestarting(reason: RuntimeSupervisorRestartReason) -> RuntimeSupervisorState {
        generation += 1
        state = .restarting(generation: generation, reason: reason)
        return state
    }

    @discardableResult
    public mutating func markFailed(issue: String) -> RuntimeSupervisorState {
        consecutiveFailures += 1
        state = .failed(generation: generation, issue: issue)
        return state
    }

    public mutating func consumeAutomaticRestartSlot() -> Bool {
        guard !automaticRestartUsedForCurrentIssue else { return false }
        automaticRestartUsedForCurrentIssue = true
        return true
    }

    public var restartBackoffSeconds: TimeInterval {
        min(30, pow(2, Double(max(0, consecutiveFailures - 1))))
    }
}
