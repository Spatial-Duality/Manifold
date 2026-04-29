// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit
@testable import ManifoldRuntime

@Suite("Privacy Filter Decoder")
struct PrivacyFilterDecoderTests {
    func makeDecoder() throws -> (PrivacyFilterDecoder, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifold-privacy-decoder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configURL = tempDir.appendingPathComponent("config.json")
        let config = """
        {
          "sliding_window": 128,
          "id2label": {
            "0": "O",
            "1": "B-private_email",
            "2": "I-private_email",
            "3": "E-private_email",
            "4": "S-secret"
          }
        }
        """
        try Data(config.utf8).write(to: configURL)
        return (try PrivacyFilterDecoder(configURL: configURL, calibrationURL: nil), tempDir)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Constrained Viterbi repairs invalid argmax path")
    func constrainedViterbiRepairsInvalidArgmaxPath() throws {
        let (decoder, tempDir) = try makeDecoder()
        defer { cleanup(tempDir) }

        var logits = Array(
            repeating: Array(repeating: Float(-10), count: 5),
            count: 3
        )
        logits[0][2] = 10
        logits[1][2] = 10
        logits[2][3] = 10

        let path = try decoder.constrainedViterbi(logits: logits, operatingPoint: "default")

        #expect(path == [1, 2, 3])
    }

    @Test("BIOES decode maps token offsets to UTF-16 spans and redaction")
    func bioesDecodeMapsOffsetsAndRedacts() throws {
        let (decoder, tempDir) = try makeDecoder()
        defer { cleanup(tempDir) }
        let text = "email alice@example.com now"

        let spans = decoder.decodeSpans(
            predictions: [0, 1, 2, 3, 0],
            offsets: [
                TokenOffset(start: 0, end: 5),
                TokenOffset(start: 6, end: 11),
                TokenOffset(start: 11, end: 19),
                TokenOffset(start: 19, end: 23),
                TokenOffset(start: 24, end: 27),
            ],
            text: text,
            allowedCategories: Set(PrivacyCategory.allCases)
        )

        #expect(spans.count == 1)
        #expect(spans[0].category == .email)
        #expect(spans[0].startUTF16 == 6)
        #expect(spans[0].endUTF16 == 23)
        #expect(spans[0].textPreview == "alice@example.com")
        #expect(decoder.redactedText(text, spans: spans) == "email [EMAIL REDACTED] now")
    }
}
