// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("RegexFilterFindingsProvider")
struct RegexFilterFindingsProviderTests {
    private let provider = RegexFilterFindingsProvider()

    @Test("Empty content returns empty summary")
    func emptyContent() async {
        let summary = await provider.findings(forFile: "x.txt", content: "")
        #expect(summary.isEmpty)
        #expect(summary.totalCount == 0)
    }

    @Test("Nil content returns empty summary")
    func nilContent() async {
        let summary = await provider.findings(forFile: "x.bin", content: nil)
        #expect(summary.isEmpty)
    }

    @Test("Detects an AWS access key id")
    func awsAccessKey() async {
        let content = "config = { aws: 'AKIAIOSFODNN7EXAMPLE' }"
        let summary = await provider.findings(forFile: "config.js", content: content)
        #expect(summary.secretCount >= 1)
        #expect(summary.totalCount >= 1)
    }

    @Test("Detects a GitHub PAT")
    func githubPAT() async {
        let content = "GH_TOKEN=ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJ"
        let summary = await provider.findings(forFile: ".env", content: content)
        #expect(summary.secretCount >= 1)
    }

    @Test("Detects an OpenAI sk- key")
    func openAIKey() async {
        let content = "openai_api_key = \"sk-abcdefghijklmnopqrstuvwxyz\""
        let summary = await provider.findings(forFile: ".env", content: content)
        #expect(summary.secretCount >= 1)
    }

    @Test("Detects a JWT")
    func jwt() async {
        // Valid JWT structure: header.payload.signature, all base64url.
        let content = """
        Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
        """
        let summary = await provider.findings(forFile: "headers.txt", content: content)
        #expect(summary.secretCount >= 1)
    }

    @Test("Detects a Slack token")
    func slackToken() async {
        let content = "SLACK=xoxb-123456789012-abcdefghijklmnop"
        let summary = await provider.findings(forFile: ".env", content: content)
        #expect(summary.secretCount >= 1)
    }

    @Test("Detects a Stripe live key")
    func stripeLive() async {
        let content = "STRIPE_KEY = sk_live_abcdefghijklmnopqrstuvwx"
        let summary = await provider.findings(forFile: ".env", content: content)
        #expect(summary.secretCount >= 1)
    }

    @Test("Detects a Google API key")
    func googleApiKey() async {
        // AIza + exactly 35 base64-shaped chars per the canonical Google
        // API key format.
        let content = "GOOGLE = AIzaSyA1234567890abcdefghij1234567890AB"
        let summary = await provider.findings(forFile: ".env", content: content)
        #expect(summary.secretCount >= 1)
    }

    @Test("Detects an SSN-shaped value")
    func ssn() async {
        let content = "patient ssn: 123-45-6789"
        let summary = await provider.findings(forFile: "intake.txt", content: content)
        #expect(summary.piiCount >= 1)
    }

    @Test("Detects a credit-card-shaped value")
    func creditCard() async {
        let content = "card 4111-1111-1111-1111 expires"
        let summary = await provider.findings(forFile: "payment.txt", content: content)
        #expect(summary.piiCount >= 1)
    }

    @Test("Plain prose with no secrets returns empty")
    func ordinaryProse() async {
        let content = """
        Today the team shipped the v0.5 release. We went over the rollback
        plan, double-checked the staging deploy, and gave Sarah the keys
        to the kingdom.
        """
        let summary = await provider.findings(forFile: "notes.md", content: content)
        #expect(summary.isEmpty,
            "Ordinary prose should not trip the regex scanner — false positives erode trust")
    }

    @Test("Email addresses alone do NOT count as a finding")
    func emailNotFlagged() async {
        // Per the docstring: emails are too common in code + prose to be
        // a useful block signal. The scanner intentionally ignores them.
        let content = "contact: alice@example.com"
        let summary = await provider.findings(forFile: "readme.md", content: content)
        #expect(summary.isEmpty)
    }

    @Test("Multiple secrets in the same file each count")
    func multipleMatches() async {
        let content = """
        AWS=AKIAIOSFODNN7EXAMPLE
        GH=ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJ
        OPENAI=sk-abcdefghijklmnopqrstuvwxyz
        """
        let summary = await provider.findings(forFile: ".env", content: content)
        #expect(summary.secretCount >= 3)
    }
}

@Suite("NullFilterModeFindingsProvider")
struct NullFilterModeFindingsProviderTests {
    @Test("Always returns empty regardless of content")
    func alwaysEmpty() async {
        let provider = NullFilterModeFindingsProvider()
        let withSecret = await provider.findings(
            forFile: ".env",
            content: "AWS=AKIAIOSFODNN7EXAMPLE"
        )
        #expect(withSecret.isEmpty)
    }
}
