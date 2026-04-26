// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Sparkle
import ManifoldKit
@testable import Manifold

/// Pure-logic tests for `UpdaterModel.classify(_:)`. The full Sparkle
/// controller is too heavy for unit tests (it spawns helpers and inspects
/// system state); the failure-classifier is the testable seam.
final class UpdaterModelClassifyTests: XCTestCase {

    private func make(_ rawCode: Int) -> NSError {
        NSError(domain: SUSparkleErrorDomain, code: rawCode)
    }

    func testSignatureMismatchClassification() {
        XCTAssertEqual(
            UpdaterModel.classify(make(Int(SUError.signatureError.rawValue))),
            .signatureMismatch
        )
        XCTAssertEqual(
            UpdaterModel.classify(make(Int(SUError.validationError.rawValue))),
            .signatureMismatch
        )
    }

    func testDownloadFailedClassification() {
        XCTAssertEqual(
            UpdaterModel.classify(make(Int(SUError.appcastError.rawValue))),
            .downloadFailed
        )
        XCTAssertEqual(
            UpdaterModel.classify(make(Int(SUError.appcastParseError.rawValue))),
            .downloadFailed
        )
        XCTAssertEqual(
            UpdaterModel.classify(make(Int(SUError.downloadError.rawValue))),
            .downloadFailed
        )
    }

    func testInstallFailedClassification() {
        XCTAssertEqual(
            UpdaterModel.classify(make(Int(SUError.installationError.rawValue))),
            .installFailed
        )
        XCTAssertEqual(
            UpdaterModel.classify(make(Int(SUError.relaunchError.rawValue))),
            .installFailed
        )
        XCTAssertEqual(
            UpdaterModel.classify(make(Int(SUError.unarchivingError.rawValue))),
            .installFailed
        )
    }

    func testUserCancelledClassification() {
        XCTAssertEqual(
            UpdaterModel.classify(make(Int(SUError.installationCanceledError.rawValue))),
            .userCancelled
        )
        XCTAssertEqual(
            UpdaterModel.classify(make(Int(SUError.installationAuthorizeLaterError.rawValue))),
            .userCancelled
        )
    }

    func testUnknownErrorFallsBackToDownloadFailed() {
        // Arbitrary high-numbered error not in our switch: should default to
        // downloadFailed (the safest "we don't know what happened" bucket).
        XCTAssertEqual(
            UpdaterModel.classify(make(99_999)),
            .downloadFailed
        )
    }
}
