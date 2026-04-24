// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ClientVerificationStatus: String, Sendable, Codable, CaseIterable {
    case verified
    case unverified
    case unknown

    public var displayName: String {
        switch self {
        case .verified:
            return "Verified"
        case .unverified:
            return "Unverified"
        case .unknown:
            return "Unknown"
        }
    }
}

public struct VerifiedClientIdentity: Sendable, Codable, Hashable {
    public let requestedTargetApp: String
    public let effectiveTargetApp: String?
    public let clientProcessID: Int32
    public let clientExecutablePath: String?
    public let hostProcessID: Int32?
    public let hostBundleIdentifier: String?
    public let hostExecutablePath: String?
    public let status: ClientVerificationStatus
    public let reason: String

    public init(
        requestedTargetApp: String,
        effectiveTargetApp: String?,
        clientProcessID: Int32,
        clientExecutablePath: String?,
        hostProcessID: Int32?,
        hostBundleIdentifier: String?,
        hostExecutablePath: String?,
        status: ClientVerificationStatus,
        reason: String
    ) {
        self.requestedTargetApp = requestedTargetApp
        self.effectiveTargetApp = effectiveTargetApp
        self.clientProcessID = clientProcessID
        self.clientExecutablePath = clientExecutablePath
        self.hostProcessID = hostProcessID
        self.hostBundleIdentifier = hostBundleIdentifier
        self.hostExecutablePath = hostExecutablePath
        self.status = status
        self.reason = reason
    }

    public var resolvedTargetApp: TargetApp? {
        guard let effectiveTargetApp else { return nil }
        return TargetApp(rawValue: effectiveTargetApp)
    }

    public var isVerified: Bool {
        status == .verified && resolvedTargetApp != nil
    }
}

public enum CoverageState: String, Sendable, Codable, CaseIterable {
    case manifoldRouted = "manifold_routed"
    case trackedWorkspace = "tracked_workspace"
    case outsideCoverage = "outside_coverage"

    public var displayName: String {
        switch self {
        case .manifoldRouted:
            return "Manifold-Routed"
        case .trackedWorkspace:
            return "Tracked Workspace"
        case .outsideCoverage:
            return "Outside Coverage"
        }
    }
}

public enum AccessRecordingLevel: String, Sendable, Codable, CaseIterable {
    case lightweight
    case summary
    case detailed

    public var displayName: String {
        switch self {
        case .lightweight:
            return "Lightweight"
        case .summary:
            return "Summary"
        case .detailed:
            return "Detailed"
        }
    }

    public var guidance: String {
        switch self {
        case .lightweight:
            return "Record access with minimal friction."
        case .summary:
            return "Require a short sentence describing what the agent is doing."
        case .detailed:
            return "Require a short summary plus richer context about why the content is needed."
        }
    }
}

public struct AccessIntent: Sendable, Codable, Hashable {
    public let summary: String?
    public let details: String?

    public init(summary: String?, details: String?) {
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.details = details?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var isEmpty: Bool {
        summary == nil && details == nil
    }
}

public struct AgentCoverageSnapshot: Sendable, Codable, Hashable, Identifiable {
    public var id: String { agent }
    public let agent: String
    public let coverageState: CoverageState
    public let verificationStatus: ClientVerificationStatus
    public let hostBundleIdentifier: String?
    public let reason: String?

    public init(
        agent: String,
        coverageState: CoverageState,
        verificationStatus: ClientVerificationStatus,
        hostBundleIdentifier: String?,
        reason: String?
    ) {
        self.agent = agent
        self.coverageState = coverageState
        self.verificationStatus = verificationStatus
        self.hostBundleIdentifier = hostBundleIdentifier
        self.reason = reason
    }
}

public struct CoverageEvent: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let agent: String
    public let coverageState: CoverageState
    public let eventType: String
    public let message: String
    public let resourcePath: String?
    public let timestamp: String
    public let metadata: String?

    public init(
        id: String,
        agent: String,
        coverageState: CoverageState,
        eventType: String,
        message: String,
        resourcePath: String?,
        timestamp: String,
        metadata: String?
    ) {
        self.id = id
        self.agent = agent
        self.coverageState = coverageState
        self.eventType = eventType
        self.message = message
        self.resourcePath = resourcePath
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public struct DataControlSummary: Sendable, Codable {
    public struct Agent: Sendable, Codable, Hashable, Identifiable {
        public var id: TargetApp { agent }
        public let agent: TargetApp
        public let isConnected: Bool
        public let verificationStatus: ClientVerificationStatus
        public let coverageState: CoverageState?
        public let isPaused: Bool
        public let defaultFileScopeCount: Int
        public let visibleEmailCount: Int
        public let sharedEmailCount: Int
        public let emailSensitivity: EmailSensitivityLevel
        public let defaultEmailPolicy: EmailDefaultPolicy

        public init(
            agent: TargetApp,
            isConnected: Bool,
            verificationStatus: ClientVerificationStatus,
            coverageState: CoverageState?,
            isPaused: Bool,
            defaultFileScopeCount: Int,
            visibleEmailCount: Int,
            sharedEmailCount: Int,
            emailSensitivity: EmailSensitivityLevel,
            defaultEmailPolicy: EmailDefaultPolicy
        ) {
            self.agent = agent
            self.isConnected = isConnected
            self.verificationStatus = verificationStatus
            self.coverageState = coverageState
            self.isPaused = isPaused
            self.defaultFileScopeCount = defaultFileScopeCount
            self.visibleEmailCount = visibleEmailCount
            self.sharedEmailCount = sharedEmailCount
            self.emailSensitivity = emailSensitivity
            self.defaultEmailPolicy = defaultEmailPolicy
        }
    }

    public struct Exposure: Sendable, Codable, Hashable, Identifiable {
        public let id: Int
        public let timestamp: String
        public let agent: TargetApp?
        public let action: String
        public let resourcePath: String?
        public let sessionID: String?
        public let grantID: String?

        public init(
            id: Int,
            timestamp: String,
            agent: TargetApp?,
            action: String,
            resourcePath: String?,
            sessionID: String?,
            grantID: String?
        ) {
            self.id = id
            self.timestamp = timestamp
            self.agent = agent
            self.action = action
            self.resourcePath = resourcePath
            self.sessionID = sessionID
            self.grantID = grantID
        }
    }

    public let runtimeConnected: Bool
    public let activeBridgeCount: Int
    public let agents: [Agent]
    public let activeWorkBlock: WorkBlockRecord?
    public let pendingApprovalCount: Int
    public let lastExposure: Exposure?
    public let recentHandoffSessions: [Session]

    public init(
        runtimeConnected: Bool,
        activeBridgeCount: Int,
        agents: [Agent],
        activeWorkBlock: WorkBlockRecord?,
        pendingApprovalCount: Int,
        lastExposure: Exposure?,
        recentHandoffSessions: [Session]
    ) {
        self.runtimeConnected = runtimeConnected
        self.activeBridgeCount = activeBridgeCount
        self.agents = agents
        self.activeWorkBlock = activeWorkBlock
        self.pendingApprovalCount = pendingApprovalCount
        self.lastExposure = lastExposure
        self.recentHandoffSessions = recentHandoffSessions
    }
}
