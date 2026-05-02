// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Versioned, allowlisted diagnostic report. Every field is exhaustively
/// modeled — the encoder cannot emit a key that is not declared here.
///
/// Forbidden by construction: paths, filenames, prompts, email addresses /
/// domains / subjects, exposure payloads, content hashes, raw audit rows,
/// raw stack traces, exact event timestamps, request IPs, cookies.
///
/// New fields require a `DiagnosticReportV2`; the V1 type is frozen once
/// the first official build ships.
public struct DiagnosticReportV1: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public let app: AppInfo
    public let platform: PlatformInfo
    public let consent: ConsentState
    /// Resettable anonymous install ID — present only when the user has
    /// enabled diagnostic exports.
    public let installID: String?
    public let runtimeHealth: RuntimeHealth
    public let rollups: [Rollup]
    public let signatures: [Signature]
    public let metricKitPayloads: [MetricKitSummary]

    public init(
        app: AppInfo,
        platform: PlatformInfo,
        consent: ConsentState,
        installID: String?,
        runtimeHealth: RuntimeHealth,
        rollups: [Rollup],
        signatures: [Signature],
        metricKitPayloads: [MetricKitSummary]
    ) {
        self.schemaVersion = 1
        self.app = app
        self.platform = platform
        self.consent = consent
        self.installID = installID
        self.runtimeHealth = runtimeHealth
        self.rollups = rollups
        self.signatures = signatures
        self.metricKitPayloads = metricKitPayloads
    }

    public struct AppInfo: Sendable, Codable, Equatable {
        public let version: String          // e.g. "0.4.0"
        public let build: String            // e.g. "418" — CFBundleVersion
        public let channel: Channel

        public enum Channel: String, Sendable, Codable, CaseIterable {
            case directDownload
            case sourceBuild
        }

        public init(version: String, build: String, channel: Channel) {
            self.version = version
            self.build = build
            self.channel = channel
        }
    }

    public struct PlatformInfo: Sendable, Codable, Equatable {
        public let osMajor: Int             // e.g. 26
        public let osMinor: Int             // e.g. 0
        public let arch: Arch

        public enum Arch: String, Sendable, Codable, CaseIterable {
            case arm64
            case x86_64
        }

        public init(osMajor: Int, osMinor: Int, arch: Arch) {
            self.osMajor = osMajor
            self.osMinor = osMinor
            self.arch = arch
        }
    }

    public struct ConsentState: Sendable, Codable, Equatable {
        public let diagnosticSharingEnabled: Bool
        public let updateChecksEnabled: Bool

        public init(diagnosticSharingEnabled: Bool, updateChecksEnabled: Bool) {
            self.diagnosticSharingEnabled = diagnosticSharingEnabled
            self.updateChecksEnabled = updateChecksEnabled
        }
    }

    public struct RuntimeHealth: Sendable, Codable, Equatable {
        public let runtimeConnected: Bool
        public let agentBootstrapped: Bool
        public let lastRegistrationOutcome: RegistrationOutcome

        public enum RegistrationOutcome: String, Sendable, Codable, CaseIterable {
            case unknown
            case succeeded
            case helperMissing
            case launchctlBootstrapFailed
            case pingTimeout
        }

        public init(
            runtimeConnected: Bool,
            agentBootstrapped: Bool,
            lastRegistrationOutcome: RegistrationOutcome
        ) {
            self.runtimeConnected = runtimeConnected
            self.agentBootstrapped = agentBootstrapped
            self.lastRegistrationOutcome = lastRegistrationOutcome
        }
    }

    public struct Rollup: Sendable, Codable, Equatable {
        public let day: String              // ISO 8601 day, "YYYY-MM-DD"
        public let process: DiagnosticEventRecord.Process
        public let name: String             // closed event name
        public let count: Int

        public init(day: String, process: DiagnosticEventRecord.Process, name: String, count: Int) {
            self.day = day
            self.process = process
            self.name = name
            self.count = count
        }
    }

    /// Opaque crash/hang signature. The signature itself is a stable hash of
    /// the topmost frames produced by MetricKit; it never includes raw symbols
    /// or paths. `component` is a high-level area like "app" or "agent".
    public struct Signature: Sendable, Codable, Equatable {
        public let component: String
        public let kind: Kind
        public let signature: String        // opaque hash, stable across reports
        public let count: Int
        public let firstDay: String
        public let lastDay: String

        public enum Kind: String, Sendable, Codable, CaseIterable {
            case crash
            case hang
            case cpuException
            case diskWriteException
        }

        public init(
            component: String,
            kind: Kind,
            signature: String,
            count: Int,
            firstDay: String,
            lastDay: String
        ) {
            self.component = component
            self.kind = kind
            self.signature = signature
            self.count = count
            self.firstDay = firstDay
            self.lastDay = lastDay
        }
    }

    /// Bounded MetricKit summary — only aggregate counters, never raw payloads.
    public struct MetricKitSummary: Sendable, Codable, Equatable {
        public let day: String
        public let cumulativeCPUSeconds: Double?
        public let memoryPeakMB: Double?
        public let hangSeconds: Double?
        public let crashCount: Int

        public init(
            day: String,
            cumulativeCPUSeconds: Double?,
            memoryPeakMB: Double?,
            hangSeconds: Double?,
            crashCount: Int
        ) {
            self.day = day
            self.cumulativeCPUSeconds = cumulativeCPUSeconds
            self.memoryPeakMB = memoryPeakMB
            self.hangSeconds = hangSeconds
            self.crashCount = crashCount
        }
    }
}

// MARK: - Sanitizer guarantees

extension DiagnosticReportV1 {
    /// The exact set of top-level keys that the encoder will produce. Tests
    /// assert against this constant — adding a key here without updating the
    /// type (or vice versa) is a build-time guarantee that the schema and
    /// implementation agree.
    public static let allowedTopLevelKeys: Set<String> = [
        "schemaVersion", "app", "platform", "consent", "installID",
        "runtimeHealth", "rollups", "signatures", "metricKitPayloads"
    ]

    /// Keys that must NEVER appear at any nesting level. Used by the
    /// app-side encoder tests and any future ingest validator.
    public static let forbiddenKeys: Set<String> = [
        "path", "paths", "filename", "filenames",
        "prompt", "prompts",
        "email", "emails", "domain", "domains", "subject", "subjects",
        "payload", "payloads", "rawPayload",
        "contentHash", "contentHashes", "hash",
        "auditRow", "auditRows",
        "stack", "stackTrace", "stackFrames",
        "ip", "ipAddress", "remoteAddress",
        "cookie", "cookies",
        "timestamp", "ts", "epoch", "exactTime"
    ]
}
