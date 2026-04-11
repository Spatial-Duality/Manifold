# Why Manifold Needs a Separate Runtime

## The Core Reason Manifold Exists

Every AI tool maker's incentive is to expand what the agent can access and do. More access means more capability means more revenue. Claude's sandboxing, Codex worktrees, Cursor's permissions — these are concessions to safety made by companies whose primary incentive is agent capability. They will always be "good enough" rather than "excellent" at access control, because excellent access control limits the product they are selling.

Manifold exists because of that tension. Its value is the constraint itself. The product IS the thing that sits between agents and your files and says: you can see this, you cannot see that, and here is the proof of both.

That means the architecture must reflect one absolute rule: **there is exactly one judge, and everything else asks it for permission.**

## What Is Wrong Today

Today there are two judges. The SwiftUI app (`ManifoldStore.swift`) and the MCP server (`ManifoldMCPServer.swift`) both independently create the full store graph — `DatabaseConnection`, `PolicyStore`, `GrantStore`, `AuditStore`, `SnapshotStore`, `ContentStore`, `WorkBlockStore`, `EmailStore`, `ArtifactIndex` — against the same SQLite file. They coordinate through fire-and-forget `DistributedNotificationCenter` posts.

This means:

When Claude asks "can I read this file?", the MCP server makes that decision alone. The app finds out afterward. There is no way for the app to intercept the decision, deny it, or hold it for approval. The control surface the user sees (the app) and the thing that actually decides (the MCP server process) are different things. That is a structural lie in a product whose entire value is control.

When two agents connect simultaneously (Claude and Cursor), each gets its own MCP server process with its own `ManifoldBridge` actor, its own in-memory file cache, its own access resolution state. They share the SQLite file but not the logic. If both try to start a tracked run at the same time, there is no coordinator.

When the app is closed, the MCP server still runs with full enforcement capability — which sounds fine until you need the approval queue (a denied request needs somewhere to land), or real-time UI (the user wants to see what the agent is doing right now), or concurrent state management. None of these work reliably across a `DistributedNotificationCenter` boundary.

## Why One Runtime, Not Just Better Coordination

You could try to fix this without a separate runtime. Add file locking. Use SQLite advisory locks. Make the notification protocol bidirectional. But you would be building a distributed system out of two processes that were never designed to coordinate — adding complexity to maintain a design that is fundamentally wrong.

The simpler answer: one process owns truth. It has the database, the policy engine, the audit log, the approval queue. Everything else asks it. The MCP server asks "can this agent read this file?" The app asks "what is the current policy?" The CLI asks "show me the audit log." One judge. Many clients.

## Why a LaunchAgent, Not the App

If the runtime lives inside the SwiftUI app process, enforcement depends on UI stability. A layout bug in a SwiftUI view, a rendering issue in the menu bar, an `@Observable` edge case — any of these can crash the app process. If the app is the runtime, a UI crash kills policy enforcement mid-task. The agent loses its connection. Work is interrupted.

For a trust product, that dependency direction is backwards. The enforcement layer should have zero knowledge of whether any window is open, any icon is rendering, or any UI exists.

Apple's XPC documentation frames process separation as a reliability and security tool: isolate failure-prone functionality so a crash in one part does not take down the rest. The UI is inherently more crash-prone than a headless runtime that manages a SQLite database. Separating them is not overengineering — it is the minimum correct boundary for a product that promises reliable control.

A LaunchAgent (not a LaunchDaemon) because Manifold's state is user-scoped: security-scoped bookmarks, email access, approval decisions, agent sessions. Apple defines daemons as system-context processes unaware of logged-in users. A per-user LaunchAgent fits.

A bundled LaunchAgent (not a standalone install) because the user installs one `.app` bundle. The helper lives at `Contents/Library/LaunchAgents/` inside it. Registered via `SMAppService`. One thing to install, one thing to update, one thing to trust.

## Why Standing Access Must Be Read-Only

The dual-path model — always-on access reads originals, tracked runs write to materialized copies — is Manifold's core differentiator. But it only works as a product promise if the boundary is absolute.

Today, `ManifoldBridge.writeFile()` resolves original-path mounts and writes directly during standing access. That means an agent in "always-on" mode can modify your original files without a tracked run, without materialization, without snapshots, without three-way merge on promote. The safety net that makes Manifold's promise real — "every change is versioned and reversible" — is bypassed.

The fix is simple and non-negotiable: standing access never writes. Any write attempt in always-on mode returns "escalation required — start a tracked run." This one rule makes the product much easier to explain ("ambient access reads, tracked runs change things") and much safer to trust ("my originals are never modified without an explicit tracked run").

This is also the product proof point — the demo, the Show HN screenshot, the entire thesis in one flow: agent tries to write, runtime escalates, menu bar badges, user approves, tracked run starts, changes are versioned, promotion is reviewable.

## Why AccessDecision and ExposureRecord

No other tool in the market answers two questions that Manifold can answer:

**"What could this agent have seen?"** — every access decision (allowed or denied), with the reason, the policy state, and the mode. This is the `AccessDecision` record.

**"What did this agent actually see?"** — every byte of content returned to the agent, with a hash, a byte count, and the tool call that triggered it. This is the `ExposureRecord`.

The distinction matters because tools leak content in ways that are not "reads." `search_files` returns snippets. `diff_file` returns file content. Email previews show body text. `read_range` returns partial files. All of these expose content without a `read_file` call. If your audit log only tracks explicit file reads, you are missing most of what the agent actually saw.

The exposure record captures them all. The access decision explains why each was allowed. Together they answer: "the agent could have seen everything in these three folders, but it actually saw 47 files totaling 230KB, plus 12 search snippets and 3 email bodies."

That is Manifold's deepest moat. It is the UI that no other tool can show.

## Summary

Manifold exists because agent access control should not be a side feature of the agent's own product. It should be a separate, trustworthy layer that the user controls.

For that to be true:
- One process must be the single judge (not two processes sharing a database)
- That process must survive UI crashes (LaunchAgent, not app-hosted)
- The read/write boundary must be absolute (standing access never writes)
- Every access must be explained and every exposure recorded (the moat)

The architecture follows from the product promise. Everything else is implementation.
