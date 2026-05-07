// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Closed enumeration of diagnostic events that may be recorded locally and
/// included in a `DiagnosticReportV1`. The set is intentionally exhaustive:
/// new event names require a new ManifoldKit release. This is the structural
/// guarantee that the report cannot leak unintended values — any field not
/// modeled here cannot appear in a serialized report.
public enum DiagnosticEvent: Sendable, Hashable {
    // App lifecycle
    case appLaunch
    case appWillTerminate
    case onboardingCompleted
    case privacyModelInstallStateChanged(PrivacyModelInstallState)

    // Runtime / agent lifecycle
    case runtimeRegistrationAttempted
    case runtimeRegistrationSucceeded
    case runtimeRegistrationFailedHelperMissing
    case runtimeRegistrationFailedLaunchctlBootstrap(code: Int32)
    case runtimePingTimeout
    case runtimeInitFailure(phase: RuntimeInitPhase)
    case runtimeUnexpectedExit(launchUUID: String, lastState: AgentLastState)
    case versionMismatchRestart(appVersion: String, runtimeVersion: String)
    case runtimeRestartStarted
    case runtimeRestartSucceeded
    case runtimeRestartFailed
    case xpcConnectionInterrupted

    // MCP reliability
    case mcpRequestFailed
    case mcpTransportClosed

    // Rules / storage
    case ruleSeedFailure

    // Updates
    case sparkleUpdateChecked
    case sparkleUpdateApplied(from: String, to: String)
    case sparkleUpdateFailed(reason: SparkleUpdateFailureReason)

    public enum PrivacyModelInstallState: String, Sendable, Codable, CaseIterable {
        case notInstalled
        case installing
        case installed
        case failed
    }

    public enum RuntimeInitPhase: String, Sendable, Codable, CaseIterable {
        case storeOpen
        case migration
        case xpcListener
        case ruleSeed
    }

    public enum AgentLastState: String, Sendable, Codable, CaseIterable {
        case running
        case cleanShutdown
        case unknown
    }

    public enum SparkleUpdateFailureReason: String, Sendable, Codable, CaseIterable {
        case signatureMismatch
        case downloadFailed
        case installFailed
        case userCancelled
    }
}

/// On-disk representation of a diagnostic event. Stable across the V1 schema.
/// `name` is the closed enum case name; `payload` is a small allowlisted dict
/// keyed only with primitives that the enum case explicitly captures.
public struct DiagnosticEventRecord: Sendable, Codable, Equatable {
    /// ISO 8601 day bucket (`YYYY-MM-DD`). Never an exact timestamp.
    public let day: String
    /// Process that recorded the event: `app` or `agent`.
    public let process: Process
    /// Closed event name (the enum case label).
    public let name: String
    /// Allowlisted payload — only primitives that correspond to a specific case.
    public let payload: Payload

    public enum Process: String, Sendable, Codable, CaseIterable {
        case app
        case agent
    }

    /// Closed payload type. Each field is optional and corresponds to exactly
    /// one event variant. Keep this list short; new payload fields require a
    /// schema bump.
    public struct Payload: Sendable, Codable, Equatable {
        public var bootstrapCode: Int32?
        public var initPhase: DiagnosticEvent.RuntimeInitPhase?
        public var launchUUID: String?
        public var agentLastState: DiagnosticEvent.AgentLastState?
        public var appVersion: String?
        public var runtimeVersion: String?
        public var privacyState: DiagnosticEvent.PrivacyModelInstallState?
        public var sparkleFromVersion: String?
        public var sparkleToVersion: String?
        public var sparkleFailure: DiagnosticEvent.SparkleUpdateFailureReason?

        public init(
            bootstrapCode: Int32? = nil,
            initPhase: DiagnosticEvent.RuntimeInitPhase? = nil,
            launchUUID: String? = nil,
            agentLastState: DiagnosticEvent.AgentLastState? = nil,
            appVersion: String? = nil,
            runtimeVersion: String? = nil,
            privacyState: DiagnosticEvent.PrivacyModelInstallState? = nil,
            sparkleFromVersion: String? = nil,
            sparkleToVersion: String? = nil,
            sparkleFailure: DiagnosticEvent.SparkleUpdateFailureReason? = nil
        ) {
            self.bootstrapCode = bootstrapCode
            self.initPhase = initPhase
            self.launchUUID = launchUUID
            self.agentLastState = agentLastState
            self.appVersion = appVersion
            self.runtimeVersion = runtimeVersion
            self.privacyState = privacyState
            self.sparkleFromVersion = sparkleFromVersion
            self.sparkleToVersion = sparkleToVersion
            self.sparkleFailure = sparkleFailure
        }

        public static let empty = Payload()
    }

    public init(day: String, process: Process, name: String, payload: Payload = .empty) {
        self.day = day
        self.process = process
        self.name = name
        self.payload = payload
    }
}

extension DiagnosticEvent {
    /// Stable string name used in the on-disk and on-wire schema. Adding a new
    /// case requires extending this switch — that's the point.
    public var name: String {
        switch self {
        case .appLaunch: return "appLaunch"
        case .appWillTerminate: return "appWillTerminate"
        case .onboardingCompleted: return "onboardingCompleted"
        case .privacyModelInstallStateChanged: return "privacyModelInstallStateChanged"
        case .runtimeRegistrationAttempted: return "runtimeRegistrationAttempted"
        case .runtimeRegistrationSucceeded: return "runtimeRegistrationSucceeded"
        case .runtimeRegistrationFailedHelperMissing: return "runtimeRegistrationFailedHelperMissing"
        case .runtimeRegistrationFailedLaunchctlBootstrap: return "runtimeRegistrationFailedLaunchctlBootstrap"
        case .runtimePingTimeout: return "runtimePingTimeout"
        case .runtimeInitFailure: return "runtimeInitFailure"
        case .runtimeUnexpectedExit: return "runtimeUnexpectedExit"
        case .versionMismatchRestart: return "versionMismatchRestart"
        case .runtimeRestartStarted: return "runtimeRestartStarted"
        case .runtimeRestartSucceeded: return "runtimeRestartSucceeded"
        case .runtimeRestartFailed: return "runtimeRestartFailed"
        case .xpcConnectionInterrupted: return "xpcConnectionInterrupted"
        case .mcpRequestFailed: return "mcpRequestFailed"
        case .mcpTransportClosed: return "mcpTransportClosed"
        case .ruleSeedFailure: return "ruleSeedFailure"
        case .sparkleUpdateChecked: return "sparkleUpdateChecked"
        case .sparkleUpdateApplied: return "sparkleUpdateApplied"
        case .sparkleUpdateFailed: return "sparkleUpdateFailed"
        }
    }

    public var payload: DiagnosticEventRecord.Payload {
        switch self {
        case .appLaunch, .appWillTerminate, .onboardingCompleted,
             .runtimeRegistrationAttempted, .runtimeRegistrationSucceeded,
             .runtimeRegistrationFailedHelperMissing, .runtimePingTimeout,
             .runtimeRestartStarted, .runtimeRestartSucceeded,
             .runtimeRestartFailed, .xpcConnectionInterrupted,
             .mcpRequestFailed, .mcpTransportClosed,
             .ruleSeedFailure, .sparkleUpdateChecked:
            return .empty
        case .privacyModelInstallStateChanged(let state):
            return .init(privacyState: state)
        case .runtimeRegistrationFailedLaunchctlBootstrap(let code):
            return .init(bootstrapCode: code)
        case .runtimeInitFailure(let phase):
            return .init(initPhase: phase)
        case .runtimeUnexpectedExit(let uuid, let last):
            return .init(launchUUID: uuid, agentLastState: last)
        case .versionMismatchRestart(let app, let runtime):
            return .init(appVersion: app, runtimeVersion: runtime)
        case .sparkleUpdateApplied(let from, let to):
            return .init(sparkleFromVersion: from, sparkleToVersion: to)
        case .sparkleUpdateFailed(let reason):
            return .init(sparkleFailure: reason)
        }
    }
}
