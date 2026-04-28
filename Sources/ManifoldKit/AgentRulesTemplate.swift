// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "AgentRules")

/// Manifold-managed Markdown block for AI-tool rules files (CLAUDE.md,
/// AGENTS.md, etc.). The block is delimited by HTML-comment markers so
/// re-running `manifold-mcp --install` replaces only the Manifold section
/// while preserving everything else the user has written.
///
/// ## Why a rules file at all
///
/// Manifold registers as an MCP server, but AI tools can still ignore it
/// and hit native shell/filesystem APIs instead. The rules file is the
/// per-tool nudge that says "prefer manifold.* tools for governed work in
/// this project so cross-agent memory and the audit ledger actually
/// capture activity." Without this nudge, Claude Code's native `Read`
/// tool can shadow `manifold.read_file` and the ledger never sees the
/// activity.
///
/// ## Trust boundary
///
/// The block is honest about what's outside Manifold's coverage (system
/// shell, network, files outside approved sources). If `manifold.*` tools
/// aren't available, the rules tell the AI to fall through to native
/// tools, not to fail.
public enum AgentRulesTemplate {
    /// Comment that opens the Manifold-managed Markdown region. Re-install
    /// scans for this exact string; do not edit between releases without a
    /// migration story.
    public static let beginMarker = "<!-- manifold:rules:begin (managed by manifold-mcp --install) -->"

    /// Comment that closes the Manifold-managed region.
    public static let endMarker = "<!-- manifold:rules:end -->"

    /// The Manifold preference rules block, without the surrounding markers.
    /// Concrete tool names match `Sources/ManifoldMCP/ToolDefinitions.swift`
    /// so the AI sees the same identifiers in its tool list.
    public static let rulesBody = """
    ## Manifold MCP tools (preferred when available)

    Manifold is the user-owned control plane for files and email exposed
    to AI agents. When `manifold.*` tools are in your tool list, prefer
    them over native equivalents for work in approved Manifold sources so
    the audit ledger, cross-agent memory, and per-agent policy actually
    fire.

    - **Files in approved sources**: prefer `manifold.read_file`,
      `manifold.write_file`, `manifold.search_files`, `manifold.read_range`,
      `manifold.diff_file` over native Read/Edit/Bash for files inside
      sources the user has shared with Manifold.
    - **Cross-agent context** (the "what did the other agent do?" question):
      call `manifold.reuse_prior_context` or `manifold.was_exposed_before`
      first. Those return prior reads, edits, and saved memory from any
      agent that worked in the same source scope.
    - **Memory**: `manifold.recall_memory` surfaces prior summaries and
      decisions; `manifold.save_memory_note` persists new context (subject
      to amnesiac mode and source-lineage scope).
    - **Verification**: when the user asks you to verify what you did, call
      `manifold.verify_claimed_actions` with structured arguments
      (`tool_name` + `resource_path`, or `content_hash`). Text-only claims
      come back ambiguous by design.
    - **Coverage check**: `manifold.get_coverage_status` tells you whether
      this connection is Manifold-routed, in a tracked workspace, or
      outside coverage.

    Out of Manifold's scope (use native tools, no governance applied):
    system shell, network requests, files outside approved sources,
    computer-use / vision capabilities. Manifold is honest about this:
    these paths are not audited by `manifold.*` tools.

    If `manifold.*` tools are not in your tool list, Manifold is not
    installed for this client. Carry on with native tools; do not fail.
    """

    /// Inserts or refreshes the Manifold rules block in `existing` Markdown
    /// content. Idempotent: same input → same output.
    ///
    /// - First install: appends the block at the end of `existing`,
    ///   separated by a blank line.
    /// - Re-install with markers intact: replaces the content between
    ///   `beginMarker` and `endMarker` (inclusive). User content outside
    ///   the markers is untouched.
    /// - Corrupted state (begin marker present, end marker missing): logs
    ///   a warning and returns `existing` unchanged. The caller writes the
    ///   unchanged content back, so no data is lost; the user must fix the
    ///   corruption manually before Manifold will manage the section
    ///   again.
    public static func upsert(into existing: String) -> String {
        let wrapped = beginMarker + "\n\n" + rulesBody + "\n\n" + endMarker

        guard let beginRange = existing.range(of: beginMarker) else {
            return appendBlock(wrapped, to: existing)
        }

        guard let endRange = existing.range(
            of: endMarker,
            range: beginRange.upperBound..<existing.endIndex
        ) else {
            logger.warning("Agent rules file has \(beginMarker, privacy: .public) but no closing \(endMarker, privacy: .public) — leaving file unchanged. Fix the corruption manually to let manifold-mcp --install manage the section again.")
            return existing
        }

        return existing.replacingCharacters(
            in: beginRange.lowerBound..<endRange.upperBound,
            with: wrapped
        )
    }

    private static func appendBlock(_ block: String, to existing: String) -> String {
        if existing.isEmpty {
            return block + "\n"
        }
        var result = existing
        if !result.hasSuffix("\n") { result += "\n" }
        if !result.hasSuffix("\n\n") { result += "\n" }
        result += block + "\n"
        return result
    }
}
