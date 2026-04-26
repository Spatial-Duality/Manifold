// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("DiagnosticReportV1")
struct DiagnosticReportV1Tests {

    private func sampleReport(installID: String? = nil) -> DiagnosticReportV1 {
        DiagnosticReportV1(
            app: .init(version: "0.4.0", build: "418", channel: .directDownload),
            platform: .init(osMajor: 26, osMinor: 0, arch: .arm64),
            consent: .init(diagnosticSharingEnabled: installID != nil, updateChecksEnabled: true),
            installID: installID,
            runtimeHealth: .init(
                runtimeConnected: true,
                agentBootstrapped: true,
                lastRegistrationOutcome: .succeeded
            ),
            rollups: [
                .init(day: "2026-04-25", process: .app, name: "appLaunch", count: 3),
                .init(day: "2026-04-25", process: .agent, name: "runtimeRegistrationSucceeded", count: 1)
            ],
            signatures: [
                .init(component: "app", kind: .crash, signature: "abc123", count: 1, firstDay: "2026-04-25", lastDay: "2026-04-25")
            ],
            metricKitPayloads: [
                .init(day: "2026-04-25", cumulativeCPUSeconds: 12.3, memoryPeakMB: 320, hangSeconds: 0.4, crashCount: 0)
            ]
        )
    }

    @Test("Top-level encoded keys exactly match the documented allowlist")
    func topLevelKeysMatchAllowlist() throws {
        let report = sampleReport(installID: "install-123")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        let any = try JSONSerialization.jsonObject(with: data)
        let dict = try #require(any as? [String: Any])
        let actual = Set(dict.keys)
        #expect(actual == DiagnosticReportV1.allowedTopLevelKeys)
    }

    @Test("Forbidden keys never appear at any nesting level")
    func forbiddenKeysAbsent() throws {
        let report = sampleReport(installID: "install-123")
        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let any = try JSONSerialization.jsonObject(with: data)

        var seenKeys: Set<String> = []
        collectAllKeys(any, into: &seenKeys)

        let intersection = seenKeys.intersection(DiagnosticReportV1.forbiddenKeys)
        #expect(intersection.isEmpty, "Forbidden keys leaked into report: \(intersection)")
    }

    @Test("installID can be omitted (consent off) and JSON omits the key")
    func installIDOmittedWhenNil() throws {
        let report = sampleReport(installID: nil)
        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let any = try JSONSerialization.jsonObject(with: data)
        let dict = try #require(any as? [String: Any])
        // With Codable's default encoding, an Optional<String> nil writes
        // `"installID": null`. We accept either an absent key or null — both
        // express "no identifier."
        if let value = dict["installID"] {
            #expect(value is NSNull, "installID present but not null when consent is off")
        }
    }

    @Test("Round-trips through JSON without lossy fields")
    func roundTrip() throws {
        let report = sampleReport(installID: "install-456")
        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let decoded = try JSONDecoder().decode(DiagnosticReportV1.self, from: data)
        #expect(decoded == report)
    }

    @Test("Schema version is locked to 1")
    func schemaVersionLocked() {
        let report = sampleReport()
        #expect(report.schemaVersion == 1)
    }

    // MARK: - helpers

    private func collectAllKeys(_ json: Any, into keys: inout Set<String>) {
        if let dict = json as? [String: Any] {
            for (k, v) in dict {
                keys.insert(k)
                collectAllKeys(v, into: &keys)
            }
        } else if let array = json as? [Any] {
            for v in array { collectAllKeys(v, into: &keys) }
        }
    }
}
