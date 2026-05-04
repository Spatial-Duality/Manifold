// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

struct DemoMCPRuntime: Sendable {
    struct FileEntry: Sendable, Hashable {
        let sourceID: String
        let sourceName: String
        let relativePath: String
        let sizeBytes: Int
        let modifiedAt: String
    }

    struct EmailEntry: Sendable, Hashable {
        let id: String
        let sender: String
        let senderDomain: String
        let subject: String
        let receivedAt: String
        let preview: String
    }

    let targetApp: TargetApp

    private var allowedSourceIDs: Set<String> {
        switch targetApp {
        case .cowork:
            return ["demo-product", "demo-notes", "demo-research", "demo-design", "demo-docs", "demo-support", "demo-templates"]
        case .codex:
            return ["demo-code", "demo-notes", "demo-invoices", "demo-operations", "demo-data", "demo-sessions", "demo-experiments"]
        }
    }

    private var sharedEmailIDs: Set<String> {
        switch targetApp {
        case .cowork:
            return [
                "demo-icloud-roadmap", "demo-icloud-pricing", "demo-gmail-interview",
                "demo-icloud-support", "demo-icloud-launch", "demo-icloud-calendar",
                "demo-gmail-survey", "demo-m365-design", "demo-m365-template",
                "demo-icloud-donatella-roadmap", "demo-icloud-tom-pricing",
                "demo-icloud-mae-copy", "demo-icloud-support-vip",
                "demo-icloud-calendar-rehearsal", "demo-gmail-linen-feedback",
                "demo-gmail-retail-signal", "demo-m365-pixel-storyboard",
                "demo-m365-session-librarian", "demo-icloud-mario-approval",
                "demo-gmail-donatella-persona", "demo-icloud-claude-session",
            ]
        case .codex:
            return [
                "demo-m365-github", "demo-m365-stripe", "demo-m365-boris",
                "demo-m365-build", "demo-m365-data", "demo-m365-incident",
                "demo-m365-pr143", "demo-m365-boris-pr143",
                "demo-m365-marc-oauth", "demo-m365-stripe-story",
                "demo-m365-build-pr143", "demo-m365-data-story",
                "demo-m365-ops-rollback", "demo-m365-codex-session",
            ]
        }
    }

    private var agentDisplayName: String {
        targetApp == .codex ? "Codex" : "Claude"
    }

    func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        switch name {
        case "get_status":
            return Self.textResult(statusText())
        case "list_files":
            return Self.textResult(listFilesText())
        case "read_file":
            guard let path = arguments["path"] as? String else {
                return Self.errorResult("'path' parameter required")
            }
            return readFile(path: path)
        case "search_files":
            guard let query = arguments["query"] as? String else {
                return Self.errorResult("'query' parameter required")
            }
            return Self.textResult(searchFilesText(query: query))
        case "list_emails":
            return Self.textResult(listEmailsText())
        case "read_email":
            guard let id = arguments["id"] as? String else {
                return Self.errorResult("'id' parameter required")
            }
            return readEmail(id: id)
        case "search_emails":
            guard let query = arguments["query"] as? String else {
                return Self.errorResult("'query' parameter required")
            }
            return Self.textResult(searchEmailsText(query: query))
        default:
            return Self.errorResult("Demo Mode supports get_status, list_files, read_file, search_files, list_emails, read_email, and search_emails. Disable Demo Mode to use '\(name)' against the local runtime.")
        }
    }

    func resourceText(uri: String) -> String? {
        switch uri {
        case "manifold://status":
            return statusText()
        case "manifold://files":
            return listFilesText()
        case "manifold://emails":
            return listEmailsText()
        default:
            return nil
        }
    }

    private func statusText() -> String {
        """
        Manifold Demo Mode
        Runtime: synthetic demo data
        Agent: \(agentDisplayName)
        Files visible: \(visibleFiles.count)
        Emails visible: \(visibleEmails.count)
        Note: Demo Mode returns fake Anthropologie data and does not read local files or mail.
        """
    }

    private func listFilesText() -> String {
        let files = visibleFiles
        guard !files.isEmpty else { return "No files available." }
        let sourceNames = Set(files.map(\.sourceName)).sorted().joined(separator: ", ")
        let rows = files.map { file in
            "[\(file.sourceName)] \(file.sourceName.lowercased())/\(file.relativePath)  (\(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file)), modified: \(file.modifiedAt.prefix(10)))"
        }
        return "Source folders: \(sourceNames)\n\n" + rows.joined(separator: "\n")
    }

    private func readFile(path: String) -> [String: Any] {
        guard let file = fileEntry(matching: path) else {
            return Self.errorResult("Demo file not shared with \(agentDisplayName): \(path)")
        }
        return Self.textResult(fileBody(file))
    }

    private func searchFilesText(query: String) -> String {
        let term = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = visibleFiles.filter { file in
            file.relativePath.lowercased().contains(term)
                || file.sourceName.lowercased().contains(term)
                || fileBody(file).lowercased().contains(term)
        }
        guard !matches.isEmpty else { return "No matches found for '\(query)'" }
        return matches.map { file in
            "## [\(file.sourceName)] \(file.sourceName.lowercased())/\(file.relativePath)\n" +
            fileBody(file).split(separator: "\n").prefix(3).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func listEmailsText() -> String {
        let emails = visibleEmails
        guard !emails.isEmpty else { return "No shared emails." }
        return emails.map { "[\($0.id)] \($0.sender) — \($0.subject) (\($0.receivedAt))" }
            .joined(separator: "\n")
    }

    private func readEmail(id: String) -> [String: Any] {
        guard let email = visibleEmails.first(where: { $0.id == id }) else {
            return Self.errorResult("Demo email not shared with \(agentDisplayName): \(id)")
        }
        return Self.textResult("""
        From: \(email.sender)
        Subject: \(email.subject)
        Date: \(email.receivedAt)

        \(email.preview)
        """)
    }

    private func searchEmailsText(query: String) -> String {
        let term = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = visibleEmails.filter { email in
            [email.id, email.sender, email.senderDomain, email.subject, email.preview]
                .joined(separator: "\n")
                .lowercased()
                .contains(term)
        }
        guard !matches.isEmpty else { return "No governed emails matched '\(query)'." }
        return matches.map { "[\($0.id)] \($0.sender) — \($0.subject)\n\($0.preview)" }
            .joined(separator: "\n\n")
    }

    private var visibleFiles: [FileEntry] {
        Self.files
            .filter { allowedSourceIDs.contains($0.sourceID) }
            .filter { file in
                !(file.sourceID == "demo-code" && file.relativePath == ".env")
                    && !(file.relativePath.hasSuffix("credentials.json"))
                    && !file.relativePath.contains("private_key")
                    && !(targetApp == .codex && file.sourceID == "demo-notes" && file.relativePath == "meetings/2026-05-01-pricing-review.md")
            }
            .sorted {
                if $0.sourceName != $1.sourceName { return $0.sourceName < $1.sourceName }
                return $0.relativePath < $1.relativePath
            }
    }

    private var visibleEmails: [EmailEntry] {
        Self.emails
            .filter { sharedEmailIDs.contains($0.id) }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    private func fileEntry(matching path: String) -> FileEntry? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let absolutePrefix = Self.rootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return visibleFiles.first { file in
            file.relativePath == normalized
                || "\(file.sourceName.lowercased())/\(file.relativePath)" == normalized.lowercased()
                || "\(absolutePrefix)/\(file.sourceName.lowercased())/\(file.relativePath)" == normalized.lowercased()
        }
    }

    private func fileBody(_ file: FileEntry) -> String {
        switch (file.sourceID, file.relativePath) {
        case ("demo-code", "src/auth.ts"):
            return """
            export function authenticate(token?: string) {
              if (!token) { return null }
              return verifyBearerToken(token)
            }
            """
        case ("demo-code", "src/billing.ts"):
            return "Stripe webhook reconciliation notes for failed event delivery and payout matching.\n"
        case ("demo-product", "q3-roadmap.md"):
            return "# Q3 roadmap\nLinen launch, recommendation engine v2, and pricing rationale for Claude review.\n"
        case ("demo-product", "pricing-decisions.md"):
            return "# Pricing decisions\nReturned to flat pricing after the abandoned tiered model.\n"
        case ("demo-product", "story/mario-linen-launch-arc.md"):
            return "# Mario linen launch arc\nDonatella wants Mario to explain the launch as a trust story. Mae owns the human sentence, and Tom owns the margin table.\n"
        case ("demo-product", "story/donatella-roadmap-notes.md"):
            return "# Donatella roadmap notes\nFewer metrics. More consequences. The roadmap should show who gets access, why, and what stays private.\n"
        case ("demo-notes", "team/openai-eval-cupcakes.txt"):
            return "OpenAI set the table with eval cupcakes during the demo-mode review.\n"
        case ("demo-notes", "meetings/2026-04-30-coffee-tasting.md"):
            return "Coffee tasting moved to 4pm. Keep the personal chatter out of Codex context.\n"
        case ("demo-notes", "story/mario-donatella-thread.md"):
            return "# Mario and Donatella thread\nMario asks Claude for a board-ready briefing. Donatella pushes for a cleaner story about access boundaries.\n"
        case ("demo-code", "src/story/accessNarrative.ts"):
            return """
            export function accessNarrative(agent: "claude" | "codex") {
              return agent === "codex" ? "Boris PR #143" : "Donatella roadmap story"
            }
            """
        case ("demo-code", "src/auth/marc-chenille-oauth.ts"):
            return "export const oauthFixture = { reviewer: \"Marc Chenille\", guardRequired: true }\n"
        case ("demo-operations", "runbooks/incident-response.md"):
            return "# Incident response\nMail sync incident review checklist for Codex runbook edits.\n"
        case ("demo-operations", "runbooks/boris-deploy-rollback.md"):
            return "# Boris deploy rollback\nIf PR #143 drops the null guard, restore v8 and rerun accessNarrative tests before promotion.\n"
        case ("demo-data", "exports/privacy-index.json"):
            return #"{"status":"complete","indexed_items":42,"privacy_filter":"demo"}"#
        case ("demo-data", "story/character-access-graph.json"):
            return #"{"mario":["roadmap","approval"],"donatella":["roadmap"],"boris":["pr143"],"mae":["launch_copy"]}"#
        default:
            return "# \(file.relativePath)\nSynthetic Demo Mode content for \(file.sourceName). This is fake data safe for Claude and Codex demos.\n"
        }
    }

    static func isEnabled(arguments: [String] = CommandLine.arguments, env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if arguments.contains("--demo") { return true }
        if ["1", "true", "yes"].contains((env["MANIFOLD_DEMO_MODE"] ?? "").lowercased()) { return true }
        let key = "manifold.demoMode"
        if UserDefaults.standard.bool(forKey: key) { return true }
        return UserDefaults(suiteName: "com.spatialduality.manifold")?.bool(forKey: key) == true
    }

    static func textResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    static func errorResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": true]
    }

    private static let rootPath = "/Users/demo/Anthropologie"

    private static let files: [FileEntry] = [
        FileEntry(sourceID: "demo-product", sourceName: "product", relativePath: "customer-proposal.docx", sizeBytes: 124_000, modifiedAt: "2026-05-01T09:16:00Z"),
        FileEntry(sourceID: "demo-product", sourceName: "product", relativePath: "pricing-decisions.md", sizeBytes: 18_400, modifiedAt: "2026-05-01T09:31:00Z"),
        FileEntry(sourceID: "demo-product", sourceName: "product", relativePath: "q3-roadmap.md", sizeBytes: 22_900, modifiedAt: "2026-05-01T09:14:00Z"),
        FileEntry(sourceID: "demo-product", sourceName: "product", relativePath: "launch/launch-copy-v4.txt", sizeBytes: 7_200, modifiedAt: "2026-04-30T15:11:00Z"),
        FileEntry(sourceID: "demo-code", sourceName: "code", relativePath: "src/auth.ts", sizeBytes: 16_800, modifiedAt: "2026-05-01T10:03:00Z"),
        FileEntry(sourceID: "demo-code", sourceName: "code", relativePath: "src/billing.ts", sizeBytes: 13_200, modifiedAt: "2026-04-30T11:22:00Z"),
        FileEntry(sourceID: "demo-code", sourceName: "code", relativePath: "src/privacy/redactor.ts", sizeBytes: 15_100, modifiedAt: "2026-04-30T14:42:00Z"),
        FileEntry(sourceID: "demo-code", sourceName: "code", relativePath: ".env", sizeBytes: 1_100, modifiedAt: "2026-04-25T09:00:00Z"),
        FileEntry(sourceID: "demo-notes", sourceName: "notes", relativePath: "meetings/2026-05-01-pricing-review.md", sizeBytes: 8_800, modifiedAt: "2026-05-01T11:30:00Z"),
        FileEntry(sourceID: "demo-notes", sourceName: "notes", relativePath: "meetings/2026-04-30-coffee-tasting.md", sizeBytes: 3_200, modifiedAt: "2026-04-30T16:00:00Z"),
        FileEntry(sourceID: "demo-notes", sourceName: "notes", relativePath: "team/openai-eval-cupcakes.txt", sizeBytes: 2_200, modifiedAt: "2026-05-01T14:51:00Z"),
        FileEntry(sourceID: "demo-invoices", sourceName: "invoices", relativePath: "stripe/webhook-failures.csv", sizeBytes: 18_600, modifiedAt: "2026-05-01T10:11:00Z"),
        FileEntry(sourceID: "demo-operations", sourceName: "operations", relativePath: "runbooks/incident-response.md", sizeBytes: 13_900, modifiedAt: "2026-04-26T12:00:00Z"),
        FileEntry(sourceID: "demo-data", sourceName: "data", relativePath: "exports/privacy-index.json", sizeBytes: 46_000, modifiedAt: "2026-04-24T12:10:00Z"),
        FileEntry(sourceID: "demo-docs", sourceName: "docs", relativePath: "handbook/demo-mode.md", sizeBytes: 7_600, modifiedAt: "2026-04-24T09:00:00Z"),
        FileEntry(sourceID: "demo-support", sourceName: "support", relativePath: "macros/privacy-filter-reply.md", sizeBytes: 3_500, modifiedAt: "2026-04-29T17:10:00Z"),
        FileEntry(sourceID: "demo-design", sourceName: "design", relativePath: "tokens/color-notes.md", sizeBytes: 4_400, modifiedAt: "2026-04-29T11:10:00Z"),
        FileEntry(sourceID: "demo-templates", sourceName: "templates", relativePath: "prompts/auth-review.md", sizeBytes: 5_900, modifiedAt: "2026-04-20T10:10:00Z"),
        FileEntry(sourceID: "demo-sessions", sourceName: "sessions", relativePath: "saved/codex-auth-review.json", sizeBytes: 21_000, modifiedAt: "2026-05-01T10:24:00Z"),
        FileEntry(sourceID: "demo-experiments", sourceName: "experiments", relativePath: "evals/privacy-filter-results.csv", sizeBytes: 52_000, modifiedAt: "2026-04-19T11:00:00Z"),
        FileEntry(sourceID: "demo-product", sourceName: "product", relativePath: "story/mario-linen-launch-arc.md", sizeBytes: 15_800, modifiedAt: "2026-05-02T09:10:00Z"),
        FileEntry(sourceID: "demo-product", sourceName: "product", relativePath: "story/donatella-roadmap-notes.md", sizeBytes: 12_900, modifiedAt: "2026-05-02T09:22:00Z"),
        FileEntry(sourceID: "demo-code", sourceName: "code", relativePath: "src/story/accessNarrative.ts", sizeBytes: 12_400, modifiedAt: "2026-05-02T10:18:00Z"),
        FileEntry(sourceID: "demo-code", sourceName: "code", relativePath: "src/auth/marc-chenille-oauth.ts", sizeBytes: 17_600, modifiedAt: "2026-05-02T10:31:00Z"),
        FileEntry(sourceID: "demo-code", sourceName: "code", relativePath: "src/tests/boris-auth-edge-case.test.ts", sizeBytes: 13_900, modifiedAt: "2026-05-02T10:44:00Z"),
        FileEntry(sourceID: "demo-notes", sourceName: "notes", relativePath: "story/mario-donatella-thread.md", sizeBytes: 9_400, modifiedAt: "2026-05-02T11:20:00Z"),
        FileEntry(sourceID: "demo-notes", sourceName: "notes", relativePath: "story/mae-ribbon-launch-room.md", sizeBytes: 8_600, modifiedAt: "2026-05-02T11:32:00Z"),
        FileEntry(sourceID: "demo-invoices", sourceName: "invoices", relativePath: "stripe/pr-143-webhook-samples.json", sizeBytes: 24_500, modifiedAt: "2026-05-02T12:18:00Z"),
        FileEntry(sourceID: "demo-operations", sourceName: "operations", relativePath: "runbooks/boris-deploy-rollback.md", sizeBytes: 15_400, modifiedAt: "2026-05-02T17:00:00Z"),
        FileEntry(sourceID: "demo-operations", sourceName: "operations", relativePath: "runbooks/demi-privacy-drill.md", sizeBytes: 11_900, modifiedAt: "2026-05-02T17:08:00Z"),
        FileEntry(sourceID: "demo-data", sourceName: "data", relativePath: "story/character-access-graph.json", sizeBytes: 64_000, modifiedAt: "2026-05-02T17:20:00Z"),
        FileEntry(sourceID: "demo-docs", sourceName: "docs", relativePath: "story/demo-cast-bible.md", sizeBytes: 10_800, modifiedAt: "2026-05-02T18:00:00Z"),
        FileEntry(sourceID: "demo-support", sourceName: "support", relativePath: "story/mae-refund-escalation.md", sizeBytes: 7_400, modifiedAt: "2026-05-02T15:40:00Z"),
        FileEntry(sourceID: "demo-design", sourceName: "design", relativePath: "tokens/donatella-color-annotations.md", sizeBytes: 5_800, modifiedAt: "2026-05-02T14:40:00Z"),
        FileEntry(sourceID: "demo-templates", sourceName: "templates", relativePath: "story/character-summary.prompt.md", sizeBytes: 6_200, modifiedAt: "2026-05-02T19:45:00Z"),
        FileEntry(sourceID: "demo-sessions", sourceName: "sessions", relativePath: "story/codex-boris-pr-143.json", sizeBytes: 22_800, modifiedAt: "2026-05-02T19:18:00Z"),
        FileEntry(sourceID: "demo-sessions", sourceName: "sessions", relativePath: "story/claude-donatella-session.json", sizeBytes: 19_400, modifiedAt: "2026-05-02T19:10:00Z"),
        FileEntry(sourceID: "demo-experiments", sourceName: "experiments", relativePath: "story/agent-memory-callbacks.csv", sizeBytes: 58_000, modifiedAt: "2026-05-02T20:20:00Z"),
    ]

    private static let emails: [EmailEntry] = [
        EmailEntry(id: "demo-icloud-roadmap", sender: "Donatella Amodei <donatella@anthropologie.test>", senderDomain: "anthropologie.test", subject: "Re: Q3 roadmap - happy to look at this", receivedAt: "2026-05-01T08:42:00Z", preview: "Claude can see this thread. The linen launch and model roadmap still need separate headings."),
        EmailEntry(id: "demo-icloud-pricing", sender: "Tom Brownie <tom@anthropologie.test>", senderDomain: "anthropologie.test", subject: "Pricing review notes", receivedAt: "2026-05-01T08:21:00Z", preview: "Claude shared. Token pricing and scarf pricing both need one clean table."),
        EmailEntry(id: "demo-gmail-interview", sender: "Calendar <calendar@gmail.test>", senderDomain: "gmail.test", subject: "Customer interview #14 confirmed - Tuesday 2pm", receivedAt: "2026-05-01T09:01:00Z", preview: "Shared with Claude for research prep."),
        EmailEntry(id: "demo-icloud-support", sender: "Support Queue <support@anthropologie.test>", senderDomain: "anthropologie.test", subject: "Refund macro needs privacy-safe wording", receivedAt: "2026-05-01T06:58:00Z", preview: "Claude can use this for support macro cleanup."),
        EmailEntry(id: "demo-icloud-launch", sender: "Mae Ribbon <mae@anthropologie.test>", senderDomain: "anthropologie.test", subject: "Launch copy v4 attached", receivedAt: "2026-05-01T06:31:00Z", preview: "Claude shared. Copy references linen launch, not lab roadmap."),
        EmailEntry(id: "demo-icloud-calendar", sender: "Calendar <calendar@anthropologie.test>", senderDomain: "anthropologie.test", subject: "Coffee tasting notes moved to 4pm", receivedAt: "2026-04-30T16:12:00Z", preview: "Claude can see the meeting note summary."),
        EmailEntry(id: "demo-gmail-survey", sender: "Research Panel <panel@survey.test>", senderDomain: "survey.test", subject: "Q2 preference study export ready", receivedAt: "2026-05-01T08:12:00Z", preview: "Shared with Claude only after PII redaction."),
        EmailEntry(id: "demo-m365-design", sender: "Pixel Desk <design@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Access matrix screenshot notes", receivedAt: "2026-05-01T11:22:00Z", preview: "Claude can see this design thread."),
        EmailEntry(id: "demo-m365-template", sender: "Session Librarian <sessions@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Saved session templates refreshed", receivedAt: "2026-05-01T12:15:00Z", preview: "Shared with Claude for onboarding polish."),
        EmailEntry(id: "demo-m365-github", sender: "GitHub <support@github.test>", senderDomain: "github.test", subject: "[github] PR #142 needs review - auth.ts refactor", receivedAt: "2026-05-01T10:01:00Z", preview: "Shared with Codex. Tracked Work Block #142 is in review."),
        EmailEntry(id: "demo-m365-stripe", sender: "Stripe <accounts@stripe.test>", senderDomain: "stripe.test", subject: "Stripe webhook event delivery failures", receivedAt: "2026-05-01T10:11:00Z", preview: "Shared with Codex for billing.ts checks."),
        EmailEntry(id: "demo-m365-boris", sender: "Boris Cherrybomb <boris@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Re: auth.ts edge case (long)", receivedAt: "2026-05-01T10:19:00Z", preview: "Respectfully: this regresses the v6 null check."),
        EmailEntry(id: "demo-m365-build", sender: "Build Bot <ci@github.test>", senderDomain: "github.test", subject: "PR #142 checks failing on auth.test.ts", receivedAt: "2026-05-01T10:22:00Z", preview: "Shared with Codex for the tracked work review."),
        EmailEntry(id: "demo-m365-data", sender: "Data Warehouse <warehouse@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Privacy index export completed", receivedAt: "2026-05-01T10:33:00Z", preview: "Codex can inspect the privacy-index schema only."),
        EmailEntry(id: "demo-m365-incident", sender: "Ops Desk <ops@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Mail sync incident review", receivedAt: "2026-05-01T10:45:00Z", preview: "Shared with Codex for runbook edits."),
        EmailEntry(id: "demo-icloud-donatella-roadmap", sender: "Donatella Amodei <donatella@anthropologie.test>", senderDomain: "anthropologie.test", subject: "Roadmap sequel - Mario needs a cleaner arc", receivedAt: "2026-05-02T09:14:00Z", preview: "Claude shared. Donatella wants the Q3 roadmap framed as a story about trust, not just feature velocity."),
        EmailEntry(id: "demo-icloud-tom-pricing", sender: "Tom Brownie <tom@anthropologie.test>", senderDomain: "anthropologie.test", subject: "Scarf margin table v2", receivedAt: "2026-05-02T09:32:00Z", preview: "Claude shared. Tom asks whether flat pricing still works once Mae adds the window display bundle."),
        EmailEntry(id: "demo-icloud-mae-copy", sender: "Mae Ribbon <mae@anthropologie.test>", senderDomain: "anthropologie.test", subject: "Launch copy needs one human sentence", receivedAt: "2026-05-02T09:48:00Z", preview: "Claude shared. Mae wants the linen launch copy to mention Mario's approval path without sounding procedural."),
        EmailEntry(id: "demo-gmail-linen-feedback", sender: "Research Panel <panel@survey.test>", senderDomain: "survey.test", subject: "Linen launch pulse ready", receivedAt: "2026-05-02T10:35:00Z", preview: "Claude shared after redaction. Customer feedback says Mae's copy lands better with Donatella's trust story."),
        EmailEntry(id: "demo-m365-pixel-storyboard", sender: "Pixel Desk <design@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Mario access storyboard exported", receivedAt: "2026-05-02T11:05:00Z", preview: "Claude shared. The storyboard shows which demo cards reveal Donatella, Mae, and Tom."),
        EmailEntry(id: "demo-m365-pr143", sender: "GitHub <support@github.test>", senderDomain: "github.test", subject: "[github] PR #143 story access narrative", receivedAt: "2026-05-02T12:01:00Z", preview: "Shared with Codex. Marc Chenille added an accessNarrative helper and Boris requested tests."),
        EmailEntry(id: "demo-m365-boris-pr143", sender: "Boris Cherrybomb <boris@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Re: PR #143 auth edge case still bites", receivedAt: "2026-05-02T12:12:00Z", preview: "Shared with Codex. Boris says the OAuth callback loses the null guard when Marc's helper runs first."),
        EmailEntry(id: "demo-m365-marc-oauth", sender: "Marc Chenille <marc@openai.test>", senderDomain: "openai.test", subject: "OAuth callback fixture for Codex", receivedAt: "2026-05-02T12:24:00Z", preview: "Shared with Codex through explicit PR context. Marc included a safe fixture and asked Codex to avoid .env."),
        EmailEntry(id: "demo-m365-stripe-story", sender: "Stripe <accounts@stripe.test>", senderDomain: "stripe.test", subject: "Webhook replay for story bundle", receivedAt: "2026-05-02T12:38:00Z", preview: "Shared with Codex. Stripe failures now include Mae's display invoice and Tom's margin check."),
        EmailEntry(id: "demo-m365-build-pr143", sender: "Build Bot <ci@github.test>", senderDomain: "github.test", subject: "PR #143 checks failing on accessNarrative.test.ts", receivedAt: "2026-05-02T12:51:00Z", preview: "Shared with Codex. The failing test proves Codex should see code/story but not legal/story."),
        EmailEntry(id: "demo-m365-data-story", sender: "Data Warehouse <warehouse@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Character access graph exported", receivedAt: "2026-05-02T13:06:00Z", preview: "Shared with Codex. The graph links Mario to roadmap, Boris to PR #143, and Mae to launch copy."),
        EmailEntry(id: "demo-m365-ops-rollback", sender: "Ops Desk <ops@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Rollback runbook for Boris deploy", receivedAt: "2026-05-02T13:20:00Z", preview: "Shared with Codex for the deploy rollback runbook after the auth narrative patch."),
        EmailEntry(id: "demo-icloud-mario-approval", sender: "Mario Amodei <mario@anthropologie.test>", senderDomain: "anthropologie.test", subject: "Approval path for launch day", receivedAt: "2026-05-02T16:10:00Z", preview: "Claude shared. Mario asks Claude to turn the approval path into a short briefing for Donatella."),
        EmailEntry(id: "demo-gmail-donatella-persona", sender: "Research Panel <panel@survey.test>", senderDomain: "survey.test", subject: "Donatella persona synthesis ready", receivedAt: "2026-05-02T16:25:00Z", preview: "Claude shared after redaction. Donatella keeps asking for fewer metrics and more consequences."),
        EmailEntry(id: "demo-m365-codex-session", sender: "Session Librarian <sessions@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Codex Boris PR #143 session saved", receivedAt: "2026-05-02T16:42:00Z", preview: "Shared with Codex. The replay records the failing test, rollback runbook, and safe fixture."),
        EmailEntry(id: "demo-icloud-claude-session", sender: "Session Librarian <sessions@anthropologie.org>", senderDomain: "anthropologie.org", subject: "Claude Donatella roadmap session saved", receivedAt: "2026-05-02T16:55:00Z", preview: "Claude shared. The replay follows Donatella from roadmap critique to launch-room copy."),
    ]
}
