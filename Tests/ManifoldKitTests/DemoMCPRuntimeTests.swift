// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import ManifoldMCP
import ManifoldKit

@Suite("Demo MCP Runtime")
struct DemoMCPRuntimeTests {
    @Test("Codex can read shared demo code and cannot read denied demo env")
    func codexDemoFilesRespectPolicy() {
        let runtime = DemoMCPRuntime(targetApp: .codex)

        let list = text(from: runtime.callTool(name: "list_files", arguments: [:]))
        #expect(list.contains("code/src/auth.ts"))
        #expect(list.contains("code/src/story/accessNarrative.ts"))
        #expect(!list.contains("code/.env"))

        let read = runtime.callTool(name: "read_file", arguments: ["path": "code/src/auth.ts"])
        #expect(read["isError"] as? Bool != true)
        #expect(text(from: read).contains("verifyBearerToken"))

        let denied = runtime.callTool(name: "read_file", arguments: ["path": "code/.env"])
        #expect(denied["isError"] as? Bool == true)
    }

    @Test("Claude can read roadmap demo data while Codex cannot read Claude-only pricing note")
    func claudeAndCodexSeeDifferentDemoScopes() {
        let claude = DemoMCPRuntime(targetApp: .cowork)
        let codex = DemoMCPRuntime(targetApp: .codex)

        let claudeRoadmap = claude.callTool(name: "read_file", arguments: ["path": "product/q3-roadmap.md"])
        #expect(claudeRoadmap["isError"] as? Bool != true)
        #expect(text(from: claudeRoadmap).contains("Q3 roadmap"))

        let codexPricing = codex.callTool(name: "read_file", arguments: ["path": "notes/meetings/2026-05-01-pricing-review.md"])
        #expect(codexPricing["isError"] as? Bool == true)
    }

    @Test("Story emails are visible to the intended demo agent")
    func storyEmailsFollowAgentScopes() {
        let claude = DemoMCPRuntime(targetApp: .cowork)
        let codex = DemoMCPRuntime(targetApp: .codex)

        #expect(text(from: claude.callTool(name: "search_emails", arguments: ["query": "Donatella"])).contains("demo-icloud-donatella-roadmap"))
        #expect(text(from: codex.callTool(name: "search_emails", arguments: ["query": "PR #143"])).contains("demo-m365-pr143"))
        #expect(!text(from: codex.callTool(name: "search_emails", arguments: ["query": "Donatella roadmap"])).contains("demo-icloud-donatella-roadmap"))
    }

    @Test("Demo MCP mode can be enabled explicitly")
    func demoModeFlagAndEnvironmentEnableRuntime() {
        #expect(DemoMCPRuntime.isEnabled(arguments: ["manifold-mcp", "--demo"], env: [:]))
        #expect(DemoMCPRuntime.isEnabled(arguments: ["manifold-mcp"], env: ["MANIFOLD_DEMO_MODE": "1"]))
    }

    private func text(from result: [String: Any]) -> String {
        let content = result["content"] as? [[String: Any]]
        return content?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
    }
}
