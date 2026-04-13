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
