// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

@Suite("AgentRulesTemplate")
struct AgentRulesTemplateTests {
    @Test("Empty file gets the manifold block")
    func freshInsert() {
        let result = AgentRulesTemplate.upsert(into: "")

        #expect(result.contains(AgentRulesTemplate.beginMarker))
        #expect(result.contains(AgentRulesTemplate.endMarker))
        #expect(result.contains("Manifold MCP tools (preferred when available)"))
        #expect(result.hasSuffix("\n"), "Output must end with a newline so editors don't complain")
    }

    @Test("Existing content without markers gets the block appended")
    func appendToExistingFile() {
        let existing = """
        # My Rules

        - Always write tests.
        - Use Swift Testing, not XCTest.
        """

        let result = AgentRulesTemplate.upsert(into: existing)

        #expect(result.hasPrefix("# My Rules"), "User content must remain at the top")
        #expect(result.contains("Use Swift Testing, not XCTest."))
        #expect(result.contains(AgentRulesTemplate.beginMarker))
        #expect(result.contains(AgentRulesTemplate.endMarker))

        // Block appears AFTER user content
        let userContentRange = try? #require(result.range(of: "Use Swift Testing, not XCTest."))
        let manifoldRange = try? #require(result.range(of: AgentRulesTemplate.beginMarker))
        if let userContentRange, let manifoldRange {
            #expect(userContentRange.upperBound < manifoldRange.lowerBound,
                    "Manifold block must come after user content")
        }
    }

    @Test("Re-install replaces the existing manifold block in place")
    func reinstallReplacesBlock() {
        let firstInstall = AgentRulesTemplate.upsert(into: "")
        let secondInstall = AgentRulesTemplate.upsert(into: firstInstall)

        // Idempotent: re-installing produces identical content
        #expect(firstInstall == secondInstall, "Re-install must be idempotent")

        // Exactly one begin marker and one end marker
        let beginCount = secondInstall.components(separatedBy: AgentRulesTemplate.beginMarker).count - 1
        let endCount = secondInstall.components(separatedBy: AgentRulesTemplate.endMarker).count - 1
        #expect(beginCount == 1, "Exactly one begin marker after re-install")
        #expect(endCount == 1, "Exactly one end marker after re-install")
    }

    /// CRITICAL regression test: a user has hand-written content above AND
    /// below the Manifold section. Re-installing must not eat their edits.
    /// Without this guarantee the install command would silently destroy
    /// user content on every upgrade.
    @Test("Re-install preserves user edits above and below the manifold block")
    func reinstallPreservesUserEdits() throws {
        // Start with user content + a Manifold block + more user content
        let withBlock = AgentRulesTemplate.upsert(into: "# Top of file\n")
        let userBookended = withBlock + "\n## My Footer Section\n\nCustom rules go here.\n"

        // Pretend the user also edited inside the existing block — those edits
        // SHOULD be overwritten because the block is Manifold-managed. But the
        // BEFORE and AFTER content must survive.
        let result = AgentRulesTemplate.upsert(into: userBookended)

        #expect(result.contains("# Top of file"),
                "Header above the manifold block must survive re-install")
        #expect(result.contains("## My Footer Section"),
                "Section below the manifold block must survive re-install")
        #expect(result.contains("Custom rules go here."),
                "User text below the manifold block must survive re-install")
        #expect(result.contains("Manifold MCP tools (preferred when available)"),
                "Manifold block must still be present")

        // And still exactly one block
        let beginCount = result.components(separatedBy: AgentRulesTemplate.beginMarker).count - 1
        #expect(beginCount == 1, "Exactly one begin marker after preserving-edits re-install")
    }

    /// User has the begin marker but the end marker is missing (file got
    /// corrupted by a bad edit). Manifold must NOT make the file worse:
    /// no new block appended, no replacement attempted, original content
    /// preserved verbatim. The corruption is the user's to fix.
    @Test("Corrupted markers (begin without end) leave the file unchanged")
    func corruptedMarkersAreLeftAlone() {
        let corrupted = """
        # My Rules

        \(AgentRulesTemplate.beginMarker)
        Some half-finished content the user is editing.
        """

        let result = AgentRulesTemplate.upsert(into: corrupted)

        #expect(result == corrupted,
                "Corrupted file must be returned unchanged so the user can fix it")
    }

    @Test("Empty marker present alone is treated as missing — block appended")
    func endMarkerWithoutBegin() {
        // No begin marker, just a stray end marker. Treat as if no manifold
        // section exists; append the block normally.
        let stray = """
        # Notes

        \(AgentRulesTemplate.endMarker)

        Some other content.
        """

        let result = AgentRulesTemplate.upsert(into: stray)

        #expect(result.contains(AgentRulesTemplate.beginMarker),
                "Block must be appended when only end marker exists")
        #expect(result.contains(stray),
                "Original content (including the stray end marker) must remain")
    }

    @Test("Block content covers the demo-critical tool surface")
    func blockMentionsHeroShotTools() {
        let body = AgentRulesTemplate.rulesBody

        // The hero shot is "what did the other agent do?" — the body must
        // point the AI at the cross-agent tools, not just the file tools.
        #expect(body.contains("reuse_prior_context"))
        #expect(body.contains("was_exposed_before"))
        #expect(body.contains("recall_memory"))
        #expect(body.contains("verify_claimed_actions"))

        // Trust boundary must be honest about what's NOT governed
        #expect(body.contains("system shell") || body.contains("native tools"))
    }
}
