// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("XOAUTH2 builder")
struct XOAUTH2BuilderTests {
    @Test("Builds Microsoft-compatible SASL payload")
    func buildsPayload() throws {
        let raw = XOAUTH2Builder.rawPayload(user: "person@example.com", accessToken: "token-123")
        #expect(String(data: raw, encoding: .utf8) == "user=person@example.com\u{001}auth=Bearer token-123\u{001}\u{001}")
        #expect(XOAUTH2Builder.payload(user: "person@example.com", accessToken: "token-123") == raw.base64EncodedString())
        #expect(XOAUTH2Builder.payload(user: "person@example.com", accessToken: "token-123") == raw.base64EncodedString())
    }
}
