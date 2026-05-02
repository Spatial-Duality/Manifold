// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("DiagnosticEvent")
struct DiagnosticEventTests {

    @Test("Event names are stable strings derived from the closed enum")
    func eventNamesStable() {
        // Hard-coded golden values — changing them requires updating the
        // server schema and migrating clients.
        #expect(DiagnosticEvent.appLaunch.name == "appLaunch")
        #expect(DiagnosticEvent.runtimeRegistrationAttempted.name == "runtimeRegistrationAttempted")
        #expect(DiagnosticEvent.runtimeRegistrationFailedHelperMissing.name == "runtimeRegistrationFailedHelperMissing")
        #expect(DiagnosticEvent.runtimeRegistrationFailedLaunchctlBootstrap(code: 5).name
                == "runtimeRegistrationFailedLaunchctlBootstrap")
        #expect(DiagnosticEvent.runtimeUnexpectedExit(launchUUID: "x", lastState: .running).name
                == "runtimeUnexpectedExit")
        #expect(DiagnosticEvent.versionMismatchRestart(appVersion: "a", runtimeVersion: "b").name
                == "versionMismatchRestart")
        #expect(DiagnosticEvent.privacyModelInstallStateChanged(.installed).name
                == "privacyModelInstallStateChanged")
        #expect(DiagnosticEvent.sparkleUpdateApplied(from: "0.4.0", to: "0.4.1").name
                == "sparkleUpdateApplied")
    }

    @Test("Payloads only carry primitives that the variant explicitly captures")
    func payloadShape() {
        let bootstrap = DiagnosticEvent.runtimeRegistrationFailedLaunchctlBootstrap(code: 5).payload
        #expect(bootstrap.bootstrapCode == 5)
        #expect(bootstrap.appVersion == nil)
        #expect(bootstrap.launchUUID == nil)

        let mismatch = DiagnosticEvent.versionMismatchRestart(
            appVersion: "0.4.0", runtimeVersion: "0.3.9"
        ).payload
        #expect(mismatch.appVersion == "0.4.0")
        #expect(mismatch.runtimeVersion == "0.3.9")
        #expect(mismatch.bootstrapCode == nil)

        let exit = DiagnosticEvent.runtimeUnexpectedExit(
            launchUUID: "uuid-1", lastState: .running
        ).payload
        #expect(exit.launchUUID == "uuid-1")
        #expect(exit.agentLastState == .running)

        let privacy = DiagnosticEvent.privacyModelInstallStateChanged(.failed).payload
        #expect(privacy.privacyState == .failed)
        #expect(privacy.appVersion == nil)
    }

    @Test("Empty-payload events have empty payloads")
    func emptyPayloads() {
        for event in [DiagnosticEvent.appLaunch,
                      .appWillTerminate,
                      .onboardingCompleted,
                      .runtimeRegistrationAttempted,
                      .runtimeRegistrationSucceeded,
                      .runtimeRegistrationFailedHelperMissing,
                      .runtimePingTimeout,
                      .ruleSeedFailure,
                      .sparkleUpdateChecked] {
            #expect(event.payload == .empty, "Expected empty payload for \(event.name)")
        }
    }
}
