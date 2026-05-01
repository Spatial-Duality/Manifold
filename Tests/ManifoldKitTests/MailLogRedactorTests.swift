// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Mail log redaction")
struct MailLogRedactorTests {
    @Test("Redacts credentials, tokens, addresses, subjects, and filenames")
    func redactsSensitiveMailDiagnostics() {
        let input = """
        C: M0001 LOGIN "person@example.com" "correct horse battery staple"
        C: M0002 AUTHENTICATE XOAUTH2 dXNlcj1wZXJzb25AZXhhbXBsZS5jb20BYXV0aD1CZWFyZXIgdG9rZW4BAQ==
        access_token: abc.def.ghi
        refresh_token="refresh-secret"
        Subject: Board plan
        Content-Disposition: attachment; filename="payroll.pdf"
        Server mentions person@example.com in banner
        """

        let redacted = MailLogRedactor().redact(input)
        #expect(!redacted.contains("correct horse battery staple"))
        #expect(!redacted.contains("dXNlcj1wZXJzb25AZXhhbXBsZS5jb20"))
        #expect(!redacted.contains("abc.def.ghi"))
        #expect(!redacted.contains("refresh-secret"))
        #expect(!redacted.contains("person@example.com"))
        #expect(!redacted.contains("Board plan"))
        #expect(!redacted.contains("payroll.pdf"))
        #expect(redacted.contains("[EMAIL]"))
        #expect(redacted.contains("[REDACTED]"))
    }
}
