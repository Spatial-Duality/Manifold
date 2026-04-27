# MCP Integration

Manifold uses MCP as the first shared integration path for Claude Desktop and Codex.

That means:

- Manifold exposes tools through `manifold-mcp`
- Claude Desktop and Codex connect to that server locally
- requests flow through XPC into the runtime
- the runtime applies access governance, records exposure, and manages tracked work

## Why MCP

MCP is the practical vendor-neutral baseline for Manifold today:

- Claude Desktop supports local MCP servers
- Codex supports MCP configuration and local tool use
- the same governed path can back both apps

MCP is the adapter, not the whole product. The runtime remains the source of truth.

## Request Flow

```mermaid
flowchart LR
    A["Claude or Codex"] --> M["manifold-mcp"]
    M --> X["ManifoldXPCClient"]
    X --> S["ManifoldXPCService"]
    S --> R["ManifoldRuntime / ManifoldBridge"]
    R --> D["Policy, stores, activity"]
```

## What `manifold-mcp` Exposes

At a high level, the tool surface covers:

- status and coverage
- governed file listing and reads
- governed email listing, reads, and search
- tracked work and activity/context queries
- scoped memory recall, memory notes, memory-source summaries, and scoped memory deletion
- capability handles and sink-flow checks for sensitive values
- strict claimed-action verification against scoped exposure evidence

See:

- [../Sources/ManifoldMCP/ToolDefinitions.swift](../Sources/ManifoldMCP/ToolDefinitions.swift)
- [../Sources/ManifoldMCP/ManifoldMCPServer.swift](../Sources/ManifoldMCP/ManifoldMCPServer.swift)

## Memory, Capability, And Proof Semantics

MCP tools are authority-bearing only when the runtime can tie them back to the current access context.

- `save_memory_note` creates agent-derived memory only when runtime memory settings allow it. Amnesiac mode returns a clear "not saved" response and records a memory-policy ledger event.
- `recall_memory`, `reuse_prior_context`, and `query_graph` expire derived memory before returning context so retention is not a cosmetic UI control.
- `forget_memory` loads the memory item first and only tombstones it when the item belongs to the current grant or every source in its lineage is available in the current scope. Missing and out-of-scope memory IDs receive the same denial.
- `check_capability_flow` loads the value handle first. Grant-backed handles must match the current grant; standing handles must have non-empty source lineage that is a subset of the current scope.
- `verify_claimed_actions` expects structured claims. A claim is `supported` only when a scoped current-connection exposure matches either `content_hash` or the same `tool_name + resource_path`. Text-only, tool-only, resource-only, and loose-overlap claims are `ambiguous`; claims without scoped evidence are `unverified`.

This is intentionally stricter than a convenience audit search. It prevents one agent session from proving, deleting, or querying artifacts that belong to another grant or source set.

## Claude Desktop

Claude Desktop uses local MCP configuration. Manifold’s installer writes the `manifold` server entry into Claude’s config so the tools appear inside Claude Desktop.

Relevant code:

- [../Sources/ManifoldKit/ConfigWriter.swift](../Sources/ManifoldKit/ConfigWriter.swift)

Practical testing guide:

- [../design/CLAUDE-CODEX-TESTING.md](../design/CLAUDE-CODEX-TESTING.md)

## Codex

Codex uses its own local MCP config. Manifold writes the matching `manifold` server block for Codex so the governed tools are available there too.

Relevant code:

- [../Sources/ManifoldKit/ConfigWriter.swift](../Sources/ManifoldKit/ConfigWriter.swift)

## Installing The Config

The normal path is through the app’s install or repair flow.

If you need the CLI path:

```bash
swift run manifold-mcp --install
```

That updates the local config files for supported hosts without overwriting unrelated servers.

## Important Boundary

Manifold governs the access path that goes through `manifold-mcp`.

It does not claim full control over native activity outside that path. That is why the app surfaces coverage states and drift signals instead of pretending every vendor capability is fully governed.
