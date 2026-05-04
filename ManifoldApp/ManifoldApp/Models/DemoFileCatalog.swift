// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

enum DemoFileCatalog {
    static let rootPath = "/Users/demo/Anthropologie"

    struct Entry: Sendable, Hashable {
        let sourceID: String
        let relativePath: String
        let sizeBytes: Int
        let modifiedAt: String

        var name: String { URL(fileURLWithPath: relativePath).lastPathComponent }
        var fileExtension: String { URL(fileURLWithPath: relativePath).pathExtension.lowercased() }
    }

    static func isDemoSource(_ source: SourceRecord) -> Bool {
        source.originalRootPath.hasPrefix(rootPath + "/")
    }

    static func files(for source: SourceRecord) -> [SourceFile] {
        guard isDemoSource(source) else { return [] }
        return entries
            .filter { $0.sourceID == source.sourceID }
            .sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
            .map { entry in
                SourceFile(
                    name: entry.name,
                    path: "\(source.originalRootPath)/\(entry.relativePath)",
                    canonicalPath: "\(source.canonicalMountName)/\(entry.relativePath)",
                    relativePath: entry.relativePath,
                    sourceName: source.displayName,
                    sourceID: source.sourceID,
                    fileExtension: entry.fileExtension,
                    sizeBytes: entry.sizeBytes,
                    modifiedDate: date(entry.modifiedAt)
                )
            }
    }

    static func relativePaths(sourceID: String) -> [String] {
        entries
            .filter { $0.sourceID == sourceID }
            .map(\.relativePath)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func children(at path: String) -> [FileNode]? {
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return nil }
        let trimmed = path == rootPath ? "" : String(path.dropFirst(rootPath.count + 1))
        let parts = trimmed.split(separator: "/").map(String.init)
        guard let sourceName = parts.first else {
            return sourceNames.map { name in
                FileNode(name: name, path: "\(rootPath)/\(name)", isDirectory: true, fileSize: 0)
            }
        }
        let sourceID = "demo-\(sourceName)"
        let parentRelative = parts.dropFirst().joined(separator: "/")
        let prefix = parentRelative.isEmpty ? "" : parentRelative + "/"
        var dirs: Set<String> = []
        var files: [Entry] = []

        for entry in entries where entry.sourceID == sourceID {
            guard entry.relativePath.hasPrefix(prefix) else { continue }
            let remainder = String(entry.relativePath.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }
            if let next = remainder.split(separator: "/").first.map(String.init), remainder.contains("/") {
                dirs.insert(next)
            } else {
                files.append(entry)
            }
        }

        let directoryNodes = dirs.sorted().map { name in
            FileNode(name: name, path: "\(path)/\(name)", isDirectory: true, fileSize: 0)
        }
        let fileNodes = files.sorted { $0.name < $1.name }.map { entry in
            FileNode(name: entry.name, path: "\(path)/\(entry.name)", isDirectory: false, fileSize: entry.sizeBytes)
        }
        return directoryNodes + fileNodes
    }

    private static func date(_ iso8601: String) -> Date {
        ISO8601DateFormatter.shared.date(from: iso8601) ?? Date(timeIntervalSince1970: 1_714_560_000)
    }

    private static var sourceNames: [String] {
        Set(entries.map { entry in
            entry.sourceID.hasPrefix("demo-")
                ? String(entry.sourceID.dropFirst("demo-".count))
                : entry.sourceID
        })
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static let entries: [Entry] = [
        Entry(sourceID: "demo-product", relativePath: "customer-proposal.docx", sizeBytes: 124_000, modifiedAt: "2026-05-01T09:16:00Z"),
        Entry(sourceID: "demo-product", relativePath: "pricing-decisions.md", sizeBytes: 18_400, modifiedAt: "2026-05-01T09:31:00Z"),
        Entry(sourceID: "demo-product", relativePath: "q3-roadmap.md", sizeBytes: 22_900, modifiedAt: "2026-05-01T09:14:00Z"),
        Entry(sourceID: "demo-product", relativePath: "launch/linen-line-brief.pdf", sizeBytes: 284_000, modifiedAt: "2026-04-29T13:10:00Z"),
        Entry(sourceID: "demo-product", relativePath: "launch/launch-copy-v4.txt", sizeBytes: 7_200, modifiedAt: "2026-04-30T15:11:00Z"),
        Entry(sourceID: "demo-product", relativePath: "research/customer-interview-synthesis.csv", sizeBytes: 42_000, modifiedAt: "2026-04-30T16:20:00Z"),
        Entry(sourceID: "demo-product", relativePath: "research/segment-notes.tsv", sizeBytes: 14_000, modifiedAt: "2026-04-28T10:05:00Z"),
        Entry(sourceID: "demo-product", relativePath: "specs/recommendation-engine-v2.json", sizeBytes: 9_900, modifiedAt: "2026-04-27T12:15:00Z"),

        Entry(sourceID: "demo-code", relativePath: "src/auth.ts", sizeBytes: 16_800, modifiedAt: "2026-05-01T10:03:00Z"),
        Entry(sourceID: "demo-code", relativePath: "src/billing.ts", sizeBytes: 13_200, modifiedAt: "2026-04-30T11:22:00Z"),
        Entry(sourceID: "demo-code", relativePath: "src/privacy/redactor.ts", sizeBytes: 15_100, modifiedAt: "2026-04-30T14:42:00Z"),
        Entry(sourceID: "demo-code", relativePath: "src/privacy/filter.test.ts", sizeBytes: 11_700, modifiedAt: "2026-04-30T14:45:00Z"),
        Entry(sourceID: "demo-code", relativePath: "src/ui/access-panel.tsx", sizeBytes: 19_200, modifiedAt: "2026-04-29T18:09:00Z"),
        Entry(sourceID: "demo-code", relativePath: "config/feature-flags.yaml", sizeBytes: 3_900, modifiedAt: "2026-04-28T08:20:00Z"),
        Entry(sourceID: "demo-code", relativePath: "config/credentials.json", sizeBytes: 2_400, modifiedAt: "2026-04-25T09:10:00Z"),
        Entry(sourceID: "demo-code", relativePath: ".env", sizeBytes: 1_100, modifiedAt: "2026-04-25T09:00:00Z"),

        Entry(sourceID: "demo-notes", relativePath: "meetings/2026-05-01-pricing-review.md", sizeBytes: 8_800, modifiedAt: "2026-05-01T11:30:00Z"),
        Entry(sourceID: "demo-notes", relativePath: "meetings/2026-04-30-coffee-tasting.md", sizeBytes: 3_200, modifiedAt: "2026-04-30T16:00:00Z"),
        Entry(sourceID: "demo-notes", relativePath: "interviews/user-12-call.md", sizeBytes: 9_100, modifiedAt: "2026-05-01T09:22:00Z"),
        Entry(sourceID: "demo-notes", relativePath: "interviews/user-14-transcript.txt", sizeBytes: 28_000, modifiedAt: "2026-05-01T09:01:00Z"),
        Entry(sourceID: "demo-notes", relativePath: "team/demis-call-summary.md", sizeBytes: 4_800, modifiedAt: "2026-05-01T16:02:00Z"),
        Entry(sourceID: "demo-notes", relativePath: "team/openai-eval-cupcakes.txt", sizeBytes: 2_200, modifiedAt: "2026-05-01T14:51:00Z"),

        Entry(sourceID: "demo-invoices", relativePath: "2026-Q1-customer-summary.csv", sizeBytes: 64_000, modifiedAt: "2026-04-30T12:00:00Z"),
        Entry(sourceID: "demo-invoices", relativePath: "stripe/webhook-failures.csv", sizeBytes: 18_600, modifiedAt: "2026-05-01T10:11:00Z"),
        Entry(sourceID: "demo-invoices", relativePath: "stripe/payout-reconciliation.xlsx", sizeBytes: 72_000, modifiedAt: "2026-04-29T09:33:00Z"),
        Entry(sourceID: "demo-invoices", relativePath: "receipts/vendor-fabric-samples.pdf", sizeBytes: 166_000, modifiedAt: "2026-04-25T09:00:00Z"),

        Entry(sourceID: "demo-racing", relativePath: "kart-47-tire-compound-analysis.md", sizeBytes: 7_700, modifiedAt: "2026-04-27T19:00:00Z"),
        Entry(sourceID: "demo-racing", relativePath: "telemetry/lap-times.csv", sizeBytes: 31_000, modifiedAt: "2026-04-26T18:00:00Z"),
        Entry(sourceID: "demo-racing", relativePath: "telemetry/engine-map.json", sizeBytes: 12_000, modifiedAt: "2026-04-26T18:10:00Z"),
        Entry(sourceID: "demo-racing", relativePath: "photos/kart-47-front.png", sizeBytes: 440_000, modifiedAt: "2026-04-20T12:00:00Z"),

        Entry(sourceID: "demo-legal", relativePath: "cap-table-2026.docx", sizeBytes: 112_000, modifiedAt: "2026-04-22T09:00:00Z"),
        Entry(sourceID: "demo-legal", relativePath: "contracts/model-garden-nda.pdf", sizeBytes: 220_000, modifiedAt: "2026-04-21T09:00:00Z"),
        Entry(sourceID: "demo-legal", relativePath: "contracts/vendor-terms-redline.docx", sizeBytes: 146_000, modifiedAt: "2026-04-19T09:00:00Z"),
        Entry(sourceID: "demo-legal", relativePath: "private_key_do_not_share.pem", sizeBytes: 1_700, modifiedAt: "2026-04-18T09:00:00Z"),

        Entry(sourceID: "demo-research", relativePath: "surveys/q2-preference-study.csv", sizeBytes: 88_000, modifiedAt: "2026-04-28T15:00:00Z"),
        Entry(sourceID: "demo-research", relativePath: "surveys/raw/respondents-redacted.csv", sizeBytes: 144_000, modifiedAt: "2026-04-28T15:05:00Z"),
        Entry(sourceID: "demo-research", relativePath: "reports/market-map.pdf", sizeBytes: 310_000, modifiedAt: "2026-04-26T14:00:00Z"),
        Entry(sourceID: "demo-research", relativePath: "reports/parody-lab-positioning.md", sizeBytes: 11_300, modifiedAt: "2026-04-26T14:05:00Z"),

        Entry(sourceID: "demo-design", relativePath: "screens/access-matrix.png", sizeBytes: 512_000, modifiedAt: "2026-04-30T10:00:00Z"),
        Entry(sourceID: "demo-design", relativePath: "screens/mail-thread-states.png", sizeBytes: 498_000, modifiedAt: "2026-04-30T10:10:00Z"),
        Entry(sourceID: "demo-design", relativePath: "tokens/color-notes.md", sizeBytes: 4_400, modifiedAt: "2026-04-29T11:10:00Z"),
        Entry(sourceID: "demo-design", relativePath: "exports/demo-mode-badge.svg", sizeBytes: 3_100, modifiedAt: "2026-04-29T11:15:00Z"),

        Entry(sourceID: "demo-sales", relativePath: "pipeline/enterprise-pipeline.csv", sizeBytes: 58_000, modifiedAt: "2026-04-30T13:30:00Z"),
        Entry(sourceID: "demo-sales", relativePath: "pipeline/notes.txt", sizeBytes: 6_100, modifiedAt: "2026-04-30T13:40:00Z"),
        Entry(sourceID: "demo-sales", relativePath: "decks/retail-lab-demo.pdf", sizeBytes: 650_000, modifiedAt: "2026-04-27T08:20:00Z"),
        Entry(sourceID: "demo-sales", relativePath: "contracts/prospect-mutual-nostalgia.docx", sizeBytes: 84_000, modifiedAt: "2026-04-26T08:20:00Z"),

        Entry(sourceID: "demo-support", relativePath: "tickets/escalations.csv", sizeBytes: 41_000, modifiedAt: "2026-04-30T17:00:00Z"),
        Entry(sourceID: "demo-support", relativePath: "tickets/refund-policy.md", sizeBytes: 5_900, modifiedAt: "2026-04-30T17:05:00Z"),
        Entry(sourceID: "demo-support", relativePath: "macros/shipping-delay.txt", sizeBytes: 2_700, modifiedAt: "2026-04-29T17:05:00Z"),
        Entry(sourceID: "demo-support", relativePath: "macros/privacy-filter-reply.md", sizeBytes: 3_500, modifiedAt: "2026-04-29T17:10:00Z"),

        Entry(sourceID: "demo-finance", relativePath: "forecast/runway-model.xlsx", sizeBytes: 132_000, modifiedAt: "2026-04-28T09:00:00Z"),
        Entry(sourceID: "demo-finance", relativePath: "forecast/burn-notes.md", sizeBytes: 8_100, modifiedAt: "2026-04-28T09:10:00Z"),
        Entry(sourceID: "demo-finance", relativePath: "tax/2026-sales-tax.csv", sizeBytes: 25_000, modifiedAt: "2026-04-27T09:00:00Z"),
        Entry(sourceID: "demo-finance", relativePath: "tax/credentials.json", sizeBytes: 2_200, modifiedAt: "2026-04-27T09:10:00Z"),

        Entry(sourceID: "demo-operations", relativePath: "vendors/fabric-suppliers.csv", sizeBytes: 38_000, modifiedAt: "2026-04-27T12:00:00Z"),
        Entry(sourceID: "demo-operations", relativePath: "vendors/warehouse-sla.pdf", sizeBytes: 210_000, modifiedAt: "2026-04-27T12:10:00Z"),
        Entry(sourceID: "demo-operations", relativePath: "runbooks/incident-response.md", sizeBytes: 13_900, modifiedAt: "2026-04-26T12:00:00Z"),
        Entry(sourceID: "demo-operations", relativePath: "runbooks/mail-sync-checklist.txt", sizeBytes: 4_200, modifiedAt: "2026-04-26T12:10:00Z"),

        Entry(sourceID: "demo-data", relativePath: "warehouse/schema.sql", sizeBytes: 19_000, modifiedAt: "2026-04-25T12:00:00Z"),
        Entry(sourceID: "demo-data", relativePath: "warehouse/events.parquet", sizeBytes: 920_000, modifiedAt: "2026-04-25T12:10:00Z"),
        Entry(sourceID: "demo-data", relativePath: "exports/user-cohorts.csv", sizeBytes: 77_000, modifiedAt: "2026-04-24T12:00:00Z"),
        Entry(sourceID: "demo-data", relativePath: "exports/privacy-index.json", sizeBytes: 46_000, modifiedAt: "2026-04-24T12:10:00Z"),

        Entry(sourceID: "demo-docs", relativePath: "handbook/demo-mode.md", sizeBytes: 7_600, modifiedAt: "2026-04-24T09:00:00Z"),
        Entry(sourceID: "demo-docs", relativePath: "handbook/security-model.md", sizeBytes: 14_400, modifiedAt: "2026-04-24T09:10:00Z"),
        Entry(sourceID: "demo-docs", relativePath: "api/runtime-client.md", sizeBytes: 11_200, modifiedAt: "2026-04-23T09:00:00Z"),
        Entry(sourceID: "demo-docs", relativePath: "api/mail-sync.md", sizeBytes: 9_900, modifiedAt: "2026-04-23T09:10:00Z"),

        Entry(sourceID: "demo-media", relativePath: "screenshots/activity.png", sizeBytes: 620_000, modifiedAt: "2026-05-01T15:00:00Z"),
        Entry(sourceID: "demo-media", relativePath: "screenshots/mail.png", sizeBytes: 644_000, modifiedAt: "2026-05-01T15:05:00Z"),
        Entry(sourceID: "demo-media", relativePath: "video/walkthrough.mov", sizeBytes: 4_800_000, modifiedAt: "2026-04-22T15:00:00Z"),
        Entry(sourceID: "demo-media", relativePath: "audio/voiceover.wav", sizeBytes: 1_200_000, modifiedAt: "2026-04-22T15:10:00Z"),

        Entry(sourceID: "demo-sessions", relativePath: "saved/claude-roadmap-session.json", sizeBytes: 18_000, modifiedAt: "2026-05-01T11:35:00Z"),
        Entry(sourceID: "demo-sessions", relativePath: "saved/codex-auth-review.json", sizeBytes: 21_000, modifiedAt: "2026-05-01T10:24:00Z"),
        Entry(sourceID: "demo-sessions", relativePath: "mock/claude-mail-triage.transcript.txt", sizeBytes: 34_000, modifiedAt: "2026-04-30T18:00:00Z"),
        Entry(sourceID: "demo-sessions", relativePath: "mock/codex-pr-142.transcript.txt", sizeBytes: 39_000, modifiedAt: "2026-04-30T18:10:00Z"),

        Entry(sourceID: "demo-templates", relativePath: "saved-sessions/roadmap-review.manifold.json", sizeBytes: 6_800, modifiedAt: "2026-04-21T10:00:00Z"),
        Entry(sourceID: "demo-templates", relativePath: "saved-sessions/mail-privacy-review.manifold.json", sizeBytes: 7_100, modifiedAt: "2026-04-21T10:10:00Z"),
        Entry(sourceID: "demo-templates", relativePath: "prompts/pricing-rationale.md", sizeBytes: 5_500, modifiedAt: "2026-04-20T10:00:00Z"),
        Entry(sourceID: "demo-templates", relativePath: "prompts/auth-review.md", sizeBytes: 5_900, modifiedAt: "2026-04-20T10:10:00Z"),

        Entry(sourceID: "demo-experiments", relativePath: "evals/privacy-filter-results.csv", sizeBytes: 52_000, modifiedAt: "2026-04-19T11:00:00Z"),
        Entry(sourceID: "demo-experiments", relativePath: "evals/cupcake-table.md", sizeBytes: 4_900, modifiedAt: "2026-04-19T11:10:00Z"),
        Entry(sourceID: "demo-experiments", relativePath: "notebooks/sharing-simulation.ipynb", sizeBytes: 180_000, modifiedAt: "2026-04-18T11:00:00Z"),
        Entry(sourceID: "demo-experiments", relativePath: "notebooks/agent-coverage.ipynb", sizeBytes: 190_000, modifiedAt: "2026-04-18T11:10:00Z"),

        Entry(sourceID: "demo-product", relativePath: "story/mario-linen-launch-arc.md", sizeBytes: 15_800, modifiedAt: "2026-05-02T09:10:00Z"),
        Entry(sourceID: "demo-product", relativePath: "story/donatella-roadmap-notes.md", sizeBytes: 12_900, modifiedAt: "2026-05-02T09:22:00Z"),
        Entry(sourceID: "demo-product", relativePath: "story/tom-brownie-pricing-table.csv", sizeBytes: 21_600, modifiedAt: "2026-05-02T09:40:00Z"),
        Entry(sourceID: "demo-product", relativePath: "launch/mae-ribbon-copy-review.md", sizeBytes: 10_700, modifiedAt: "2026-05-02T10:05:00Z"),

        Entry(sourceID: "demo-code", relativePath: "src/story/accessNarrative.ts", sizeBytes: 12_400, modifiedAt: "2026-05-02T10:18:00Z"),
        Entry(sourceID: "demo-code", relativePath: "src/auth/marc-chenille-oauth.ts", sizeBytes: 17_600, modifiedAt: "2026-05-02T10:31:00Z"),
        Entry(sourceID: "demo-code", relativePath: "src/tests/boris-auth-edge-case.test.ts", sizeBytes: 13_900, modifiedAt: "2026-05-02T10:44:00Z"),
        Entry(sourceID: "demo-code", relativePath: "docs/codex-pr-143-notes.md", sizeBytes: 7_800, modifiedAt: "2026-05-02T11:02:00Z"),

        Entry(sourceID: "demo-notes", relativePath: "story/mario-donatella-thread.md", sizeBytes: 9_400, modifiedAt: "2026-05-02T11:20:00Z"),
        Entry(sourceID: "demo-notes", relativePath: "story/mae-ribbon-launch-room.md", sizeBytes: 8_600, modifiedAt: "2026-05-02T11:32:00Z"),
        Entry(sourceID: "demo-notes", relativePath: "meetings/2026-05-02-mustafa-partnership.md", sizeBytes: 7_900, modifiedAt: "2026-05-02T11:45:00Z"),
        Entry(sourceID: "demo-notes", relativePath: "interviews/user-18-linen-feedback.md", sizeBytes: 11_300, modifiedAt: "2026-05-02T12:00:00Z"),

        Entry(sourceID: "demo-invoices", relativePath: "story/tom-scarf-margin-check.csv", sizeBytes: 53_000, modifiedAt: "2026-05-02T12:12:00Z"),
        Entry(sourceID: "demo-invoices", relativePath: "stripe/pr-143-webhook-samples.json", sizeBytes: 24_500, modifiedAt: "2026-05-02T12:18:00Z"),
        Entry(sourceID: "demo-invoices", relativePath: "receipts/mae-ribbon-window-display.pdf", sizeBytes: 188_000, modifiedAt: "2026-05-02T12:24:00Z"),
        Entry(sourceID: "demo-invoices", relativePath: "forecast/donatella-launch-spend.xlsx", sizeBytes: 94_000, modifiedAt: "2026-05-02T12:30:00Z"),

        Entry(sourceID: "demo-racing", relativePath: "story/mario-kart-alibi.md", sizeBytes: 6_800, modifiedAt: "2026-05-02T12:40:00Z"),
        Entry(sourceID: "demo-racing", relativePath: "telemetry/demi-hassabit-lap-notes.csv", sizeBytes: 26_000, modifiedAt: "2026-05-02T12:48:00Z"),
        Entry(sourceID: "demo-racing", relativePath: "garage/spare-parts-inventory.csv", sizeBytes: 19_600, modifiedAt: "2026-05-02T12:55:00Z"),
        Entry(sourceID: "demo-racing", relativePath: "photos/demi-track-walk.png", sizeBytes: 510_000, modifiedAt: "2026-05-02T13:02:00Z"),

        Entry(sourceID: "demo-legal", relativePath: "story/sam-altmore-working-group-nda.pdf", sizeBytes: 244_000, modifiedAt: "2026-05-02T13:15:00Z"),
        Entry(sourceID: "demo-legal", relativePath: "contracts/mustafa-partnership-redline.docx", sizeBytes: 162_000, modifiedAt: "2026-05-02T13:24:00Z"),
        Entry(sourceID: "demo-legal", relativePath: "board/donatella-vote-notes.md", sizeBytes: 13_300, modifiedAt: "2026-05-02T13:31:00Z"),
        Entry(sourceID: "demo-legal", relativePath: "keys/staging_private_key.pem", sizeBytes: 1_900, modifiedAt: "2026-05-02T13:40:00Z"),

        Entry(sourceID: "demo-research", relativePath: "story/demi-market-map-annotations.md", sizeBytes: 10_900, modifiedAt: "2026-05-02T13:52:00Z"),
        Entry(sourceID: "demo-research", relativePath: "surveys/linen-launch-pulse.csv", sizeBytes: 96_000, modifiedAt: "2026-05-02T14:05:00Z"),
        Entry(sourceID: "demo-research", relativePath: "interviews/donatella-persona-synthesis.md", sizeBytes: 14_200, modifiedAt: "2026-05-02T14:11:00Z"),
        Entry(sourceID: "demo-research", relativePath: "reports/tom-brownie-price-elasticity.pdf", sizeBytes: 336_000, modifiedAt: "2026-05-02T14:19:00Z"),

        Entry(sourceID: "demo-design", relativePath: "story/mae-ribbon-window-board.png", sizeBytes: 580_000, modifiedAt: "2026-05-02T14:32:00Z"),
        Entry(sourceID: "demo-design", relativePath: "tokens/donatella-color-annotations.md", sizeBytes: 5_800, modifiedAt: "2026-05-02T14:40:00Z"),
        Entry(sourceID: "demo-design", relativePath: "screens/mario-access-storyboard.png", sizeBytes: 612_000, modifiedAt: "2026-05-02T14:48:00Z"),
        Entry(sourceID: "demo-design", relativePath: "exports/launch-room-state.svg", sizeBytes: 4_900, modifiedAt: "2026-05-02T14:55:00Z"),

        Entry(sourceID: "demo-sales", relativePath: "story/mustafa-retail-collab.md", sizeBytes: 8_500, modifiedAt: "2026-05-02T15:05:00Z"),
        Entry(sourceID: "demo-sales", relativePath: "pipeline/donatella-enterprise-followups.csv", sizeBytes: 61_000, modifiedAt: "2026-05-02T15:12:00Z"),
        Entry(sourceID: "demo-sales", relativePath: "decks/mario-board-demo-v2.pdf", sizeBytes: 704_000, modifiedAt: "2026-05-02T15:20:00Z"),
        Entry(sourceID: "demo-sales", relativePath: "contracts/tom-brownie-pilot-terms.docx", sizeBytes: 91_000, modifiedAt: "2026-05-02T15:28:00Z"),

        Entry(sourceID: "demo-support", relativePath: "story/mae-refund-escalation.md", sizeBytes: 7_400, modifiedAt: "2026-05-02T15:40:00Z"),
        Entry(sourceID: "demo-support", relativePath: "tickets/donatella-vip-escalations.csv", sizeBytes: 44_000, modifiedAt: "2026-05-02T15:48:00Z"),
        Entry(sourceID: "demo-support", relativePath: "macros/linen-launch-delay.md", sizeBytes: 3_900, modifiedAt: "2026-05-02T15:56:00Z"),
        Entry(sourceID: "demo-support", relativePath: "runbooks/mario-approval-path.md", sizeBytes: 6_300, modifiedAt: "2026-05-02T16:04:00Z"),

        Entry(sourceID: "demo-finance", relativePath: "story/tom-brownie-runway-note.md", sizeBytes: 9_200, modifiedAt: "2026-05-02T16:15:00Z"),
        Entry(sourceID: "demo-finance", relativePath: "forecast/linen-launch-sensitivity.xlsx", sizeBytes: 148_000, modifiedAt: "2026-05-02T16:24:00Z"),
        Entry(sourceID: "demo-finance", relativePath: "tax/mustafa-collab-vat.csv", sizeBytes: 27_000, modifiedAt: "2026-05-02T16:30:00Z"),
        Entry(sourceID: "demo-finance", relativePath: "tax/launch_credentials.json", sizeBytes: 2_300, modifiedAt: "2026-05-02T16:36:00Z"),

        Entry(sourceID: "demo-operations", relativePath: "story/ops-launch-day-timeline.md", sizeBytes: 12_600, modifiedAt: "2026-05-02T16:45:00Z"),
        Entry(sourceID: "demo-operations", relativePath: "vendors/mae-window-vendors.csv", sizeBytes: 41_000, modifiedAt: "2026-05-02T16:52:00Z"),
        Entry(sourceID: "demo-operations", relativePath: "runbooks/boris-deploy-rollback.md", sizeBytes: 15_400, modifiedAt: "2026-05-02T17:00:00Z"),
        Entry(sourceID: "demo-operations", relativePath: "runbooks/demi-privacy-drill.md", sizeBytes: 11_900, modifiedAt: "2026-05-02T17:08:00Z"),

        Entry(sourceID: "demo-data", relativePath: "story/character-access-graph.json", sizeBytes: 64_000, modifiedAt: "2026-05-02T17:20:00Z"),
        Entry(sourceID: "demo-data", relativePath: "warehouse/story-events.parquet", sizeBytes: 1_080_000, modifiedAt: "2026-05-02T17:28:00Z"),
        Entry(sourceID: "demo-data", relativePath: "exports/mario-donatella-cohorts.csv", sizeBytes: 84_000, modifiedAt: "2026-05-02T17:36:00Z"),
        Entry(sourceID: "demo-data", relativePath: "exports/boris-auth-index.json", sizeBytes: 52_000, modifiedAt: "2026-05-02T17:44:00Z"),

        Entry(sourceID: "demo-docs", relativePath: "story/demo-cast-bible.md", sizeBytes: 10_800, modifiedAt: "2026-05-02T18:00:00Z"),
        Entry(sourceID: "demo-docs", relativePath: "handbook/claude-codex-story-mode.md", sizeBytes: 12_700, modifiedAt: "2026-05-02T18:08:00Z"),
        Entry(sourceID: "demo-docs", relativePath: "api/story-fixture-contract.md", sizeBytes: 9_600, modifiedAt: "2026-05-02T18:16:00Z"),
        Entry(sourceID: "demo-docs", relativePath: "api/demo-email-storylines.md", sizeBytes: 10_500, modifiedAt: "2026-05-02T18:24:00Z"),

        Entry(sourceID: "demo-media", relativePath: "story/launch-room-wide.png", sizeBytes: 690_000, modifiedAt: "2026-05-02T18:35:00Z"),
        Entry(sourceID: "demo-media", relativePath: "screenshots/claude-story-recall.png", sizeBytes: 630_000, modifiedAt: "2026-05-02T18:42:00Z"),
        Entry(sourceID: "demo-media", relativePath: "video/mario-demo-rehearsal.mov", sizeBytes: 5_200_000, modifiedAt: "2026-05-02T18:50:00Z"),
        Entry(sourceID: "demo-media", relativePath: "audio/donatella-voice-note.wav", sizeBytes: 1_420_000, modifiedAt: "2026-05-02T18:58:00Z"),

        Entry(sourceID: "demo-sessions", relativePath: "story/claude-donatella-session.json", sizeBytes: 19_400, modifiedAt: "2026-05-02T19:10:00Z"),
        Entry(sourceID: "demo-sessions", relativePath: "story/codex-boris-pr-143.json", sizeBytes: 22_800, modifiedAt: "2026-05-02T19:18:00Z"),
        Entry(sourceID: "demo-sessions", relativePath: "mock/mario-briefing.transcript.txt", sizeBytes: 36_000, modifiedAt: "2026-05-02T19:26:00Z"),
        Entry(sourceID: "demo-sessions", relativePath: "mock/mae-launch-copy.transcript.txt", sizeBytes: 33_000, modifiedAt: "2026-05-02T19:34:00Z"),

        Entry(sourceID: "demo-templates", relativePath: "story/character-summary.prompt.md", sizeBytes: 6_200, modifiedAt: "2026-05-02T19:45:00Z"),
        Entry(sourceID: "demo-templates", relativePath: "saved-sessions/donatella-roadmap-review.manifold.json", sizeBytes: 7_600, modifiedAt: "2026-05-02T19:52:00Z"),
        Entry(sourceID: "demo-templates", relativePath: "prompts/boris-auth-review.md", sizeBytes: 6_400, modifiedAt: "2026-05-02T20:00:00Z"),
        Entry(sourceID: "demo-templates", relativePath: "prompts/mae-copy-polish.md", sizeBytes: 5_700, modifiedAt: "2026-05-02T20:08:00Z"),

        Entry(sourceID: "demo-experiments", relativePath: "story/agent-memory-callbacks.csv", sizeBytes: 58_000, modifiedAt: "2026-05-02T20:20:00Z"),
        Entry(sourceID: "demo-experiments", relativePath: "evals/story-mode-privacy-results.csv", sizeBytes: 55_000, modifiedAt: "2026-05-02T20:28:00Z"),
        Entry(sourceID: "demo-experiments", relativePath: "notebooks/character-access-simulation.ipynb", sizeBytes: 198_000, modifiedAt: "2026-05-02T20:36:00Z"),
        Entry(sourceID: "demo-experiments", relativePath: "evals/demi-cupcake-regression.md", sizeBytes: 5_400, modifiedAt: "2026-05-02T20:44:00Z"),
    ]
}
