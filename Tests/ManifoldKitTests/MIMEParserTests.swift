// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("MIMEParser")
struct MIMEParserTests {
    @Test("Safe excerpt strips HTML content")
    func safeExcerptStripsHTML() {
        let email = MIMEParser.ParsedEmail(
            headers: [:],
            textBody: nil,
            htmlBody: "<p>Hello <strong>world</strong></p>",
            attachments: [],
            allParts: []
        )

        #expect(email.safeExcerpt() == "Hello world")
    }

    @Test("Multipart parsing caps the number of parsed parts")
    func multipartParsingCapsPartCount() {
        let boundary = "boundary"
        let parts = (0..<300).map { index in
            """
            --\(boundary)
            Content-Type: text/plain

            Part \(index)
            """
        }.joined(separator: "\r\n")
        let raw = """
        Content-Type: multipart/mixed; boundary="\(boundary)"

        \(parts)
        --\(boundary)--
        """

        let parsed = MIMEParser.parse(raw: raw)
        #expect(parsed.allParts.count <= 255)
        #expect(parsed.allParts.count > 0)
    }

    @Test("Attachment filenames are sanitized")
    func sanitizeFilenameStripsPathSeparators() {
        let filename = MIMEParser.sanitizeFilename("../secret\\\\report.pdf")
        #expect(filename == ".._secret__report.pdf")
    }
}
