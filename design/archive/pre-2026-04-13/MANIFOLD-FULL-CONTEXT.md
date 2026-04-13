# Manifold — Complete App Context Document

> **Date**: April 10, 2026
> **Author**: Amar Gandhi
> **Purpose**: Full context handoff for any AI reviewer. Covers what the app is, how it works, what's built, what's being redesigned, and the open design questions.

---

## What Manifold Is

Manifold is a native macOS app that gives users ownership and control over which files and emails AI agents can access on their computer. It sits between the user's data (local folders, email accounts) and AI agents (Claude/Cowork and OpenAI Codex).

The core proposition: **You should be able to clearly see your data, clearly decide what each AI can access, and clearly track what each AI did with that access.** It's not about hiding things behind magic — it's about transparency, ownership, and control of YOUR data.

**Tech stack**: Swift 6, SwiftUI, macOS 26+ (Liquid Glass design language), SQLite3, IMAP/MIME for email, MCP (Model Context Protocol, JSON-RPC 2.0 over stdio), CryptoKit SHA-256, SPM + Xcode.

---

## How It Works — Architecture Overview

### The Three Layers

```
┌─────────────────────────────────────────────┐
│  USER'S DATA                                │
│  Local folders (~/Projects, ~/Documents)    │
│  Email accounts (IMAP sync to local backup) │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│  MANIFOLD (this app)                        │
│                                             │
│  ManifoldKit (core logic)                   │
│   ├─ GrantStore: access lifecycle           │
│   ├─ ContentStore: content-addressed blobs  │
│   ├─ SnapshotStore: file version history    │
│   ├─ MaterializationEngine: file → workspace│
│   ├─ PromoteEngine: workspace → originals   │
│   ├─ EmailStore: email backup index         │
│   ├─ EmailSensitivityFilter: domain-based   │
│   ├─ AuditStore: action logging             │
│   ├─ AccessStore: preset configurations     │
│   ├─ ContextEngine: file reading + search   │
│   ├─ WorkspaceLeaseManager: workspace runs  │
│   └─ DiffEngine: file comparison            │
│                                             │
│  ManifoldMCP (agent interface)              │
│   ├─ 16+ MCP tools via JSON-RPC 2.0 stdio  │
│   ├─ Fail-closed: no grant = no access      │
│   └─ Full audit logging of every action     │
│                                             │
│  ManifoldApp (SwiftUI UI — being rebuilt)   │
│   └─ 4-tab layout: Home, Files, Emails,    │
│      History                                │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│  AI AGENTS                                  │
│  Claude (via Cowork) — blue identity        │
│  Codex (via CLI) — purple identity          │
│  (concurrent sessions possible)             │
└─────────────────────────────────────────────┘
```

---

## Backend — ManifoldKit (Complete, 230+ tests)

### GrantStore — Access Lifecycle Manager
Tracks sources (user-approved folders) and grants (time-bounded access sessions). Key methods: `addSource()`, `activeSources()`, `startGrant()` (creates session, links sources), `endGrant()`, `expireStaleGrants()`, `touchGrant()` (refresh inactivity deadline). Handles file scopes, promotions, and session summaries. Each grant is tied to a specific agent (Claude or Codex) via `TargetApp` enum.

### GrantTypes — Core Type Definitions
- `GrantStatus`: active, ended, timedOut
- `TargetApp`: cowork (Claude), codex
- `SessionNoteCaptureMode`: off, basic, verbose
- `SourceRecord`: user-approved folder with path, display name, status
- `GrantRecord`: time-bounded session with target app, status, timeout
- `FileSelectionScope`: supports partial folder access via glob patterns
- `EmailMessageRecord`, `SharedEmailRecord`: email access tracking
- `PromotionResult`: applied, conflict, skipped, newFile
- `SessionSummaryRecord`: session notes and summaries

### ContentStore — Content-Addressed Blob Storage
SHA-256 content-addressed storage with 2-character prefix sharding. Deduplicates identical files. Methods: `ingest()` (stores blob, returns hash), `retrieve()`, reference counting (`incrementRef`/`decrementRef`), `garbageCollect()`. Immutable once written.

### SnapshotStore — File Version History
Records every file version across all runs: baselines, modifications, creations, deletions, restorations. Methods: `recordBaseline()`, `recordModification()`, `history()` (per file), `runTimeline()`, `workspaceTimeline()`. Pruning: by age, run count, file count. Maintains reference counts for garbage collection coordination with ContentStore.

### MaterializationEngine — File Copy to Workspace
Copies source files into isolated grant workspaces. Static methods: `estimateSize()`, `materialize()` (creates workspace mount, generates baseline manifest via SHA-256). Size guards: 5GB warning, 50GB hard block. Skips hidden files, `.git`, `node_modules`, etc. Respects `.manifoldignore` patterns and file selection scopes for partial materialization.

### PromoteEngine — Three-Way Merge Back
Writes agent changes back to originals using three-way hash comparison:
- **Baseline hash**: file state when workspace was created
- **Original hash**: current state of the original file (may have changed externally)
- **Materialized hash**: current state in agent workspace (may have been modified by agent)

Results: `applied` (safe overwrite — original unchanged, agent changed), `conflict` (both changed independently), `skipped` (agent didn't change), `newFile` (agent created). Supports `dryRun()` preview. Respects file scopes to block out-of-scope writes.

### EmailStore — Email Backup Index
IMAP email backup with local storage and FTS5 full-text search. Stores email metadata (sender, recipients, subject, date, mailbox), body content, and attachments. Smart mailbox support with rule-based filtering. UPSERT with conflict resolution.

### EmailSensitivityFilter — Domain-Based Visibility
Controls which emails AI agents can see based on sender domain categories:
- **Strict**: very limited visibility
- **Moderate**: hides banking (bankofamerica.com, chase.com, fidelity.com), health (myhealth.com, cvs.com), 2FA/verification, and transactional emails
- **Open**: everything visible except hard deny-listed domains

Static method `isVisible()` checks if a specific email should be visible at a given sensitivity level.

### AuditStore — Action Logging
Complete accountability log of every action: file reads, writes, searches, tool calls, connections, promotions, restorations. Auto-groups events into sessions with 5-minute gap tolerance. Types: `AuditEntry`, `Session`, `SessionEvent`. Enum `AuditAction` covers: sourceAdded, fileModified, promote, restore, etc.

### AccessStore — Preset Configurations
Reusable access presets (named configurations of file scopes + email selections). Methods: `allPresets()`, `loadPreset()`, `savePreset()`, `deletePreset()`. Returns `AccessPresetSnapshot`.

### ContextEngine — File Reading
Reads file contents with safety limits: max 64KB, 12K chars, 240 lines. Supports line/byte range selection with truncation notices. Methods: `read()`, `searchMatches()`, `preview()`, `estimateTokens()`. Binary file detection by extension + null-byte check.

### WorkspaceLeaseManager — Workspace Lifecycle
Manages workspace lifecycles and access runs. Methods: `registerWorkspace()`, `startRun()` (auto-ends prior active run), `endRun()`, `activeRun()`, `closeIdleRuns()` (timeout-based). Enum `RunTrigger`: userGrant, userRefresh, autoResume.

---

## ManifoldMCP — Agent Interface (Complete)

MCP server exposing ManifoldKit to AI agents via JSON-RPC 2.0 over stdio. Protocol version `2024-11-05`.

### 16+ MCP Tools
- `list_files` — list accessible files in workspace
- `read_file` — read file contents (with ContextEngine limits)
- `read_range` — read specific line range
- `write_file` — write/create file in workspace
- `search_files` — search file contents
- `search_structured` — structured search with filters
- `file_info` — file metadata
- `diff_file` — compare file versions
- `list_changes` — files modified in current session
- `list_emails` — list accessible emails
- `read_email` — read email content
- `list_archive` — list archive contents
- `extract_file` — extract from archives
- `list_sessions` — session history
- `get_session` — session details
- `save_session_note` — capture session notes
- `get_status` — current grant/workspace status

### Security Model
**Fail-closed**: if no active grant exists, all file/email access is denied. The bridge validates every request against the active grant's scope. Path traversal prevention (no `..`, no absolute paths). Full audit logging of every tool call.

### ManifoldBridge — Core Actor
Bridges MCP calls to ManifoldKit stores. Resolves grants, validates paths, maps mount names to source directories, enforces scope boundaries. Tracks runtime context: connection metadata, client info, provider/model hints.

---

## ManifoldApp — SwiftUI UI (Being Rebuilt)

The UI is being rebuilt from scratch as of April 2026. Backend is complete; frontend was stripped.

### Current Layout (v2 spec)
Inspired by the Claude desktop app:
- **Top bar**: App icon, 4-tab segmented control (Home, Files, Emails, History), search (⌘K), agent connection status
- **Left sidebar** (240pt): Context-sensitive per tab, profile/settings footer
- **Main content**: Tab-specific layouts
- **Right sidebar** (300pt, collapsed by default): File details, version history, diff preview

### Tab Purposes
- **Home**: Dashboard, session management, activity feed, stat pills
- **Files**: File browsing, source management, per-agent access defaults, content search, version history
- **Emails**: Email archive browser (read-only, no read/unread tracking), message list + reading pane, smart mailboxes, sensitivity controls
- **History**: Session history, event timeline, audit trail, promotion results, session notes

### Key UI Patterns
- macOS 26 Liquid Glass design language
- `@Observable` macro (not ObservableObject)
- `.glassEffect()` for Liquid Glass surfaces
- `Table` for sortable file lists
- `DisclosureGroup` for sidebar trees
- SF Pro + SF Mono fonts, system semantic colors, base-4 spacing

---

## Current Access Control Model (v2, being redesigned)

### Three-Layer Trust Model
1. **Persistent defaults** (Files sidebar) — Per-source checkboxes for Claude and Codex. "Include this folder by default for new sessions." Permanent preference.
2. **Session scope review** (Home tab) — Mandatory review before creating a grant. User confirms exactly what agent can access. Creates the actual grant + materializes workspace.
3. **Temporary session exceptions** (during session) — Escape hatch for adding individual hidden emails mid-session. Auto-expires on session end.

### Concurrency
Claude and Codex can have simultaneous active sessions on the same sources. Each gets its own materialized workspace (separate copy). Conflicts resolved by PromoteEngine at session end.

---

## Active Design Question: Is "Sessions" Even Right?

This is the biggest open question. The current design uses a session lifecycle (Start → Scope Review → Active → End → Promote), but neither target agent actually works this way:

### How Claude/Cowork Actually Works
You select a folder. Claude gets access to it. No ceremony. Standing permission scoped to the folder. Persists while the app is open. No "session end."

### How Codex Actually Works
You run `codex` in a working directory. Codex sees that directory. Sandbox mode (read-only/workspace-write/full-access) controls what it can DO, not what it can SEE. Sessions exist for conversation resumption, not access scoping.

### Three Alternative Models Under Consideration

**A) Standing Access** (matches how agents actually work):
User selects folders and email domains. Access is continuous until revoked. No start/end ceremony. Manifold is a persistent access control layer. Version history captures what happened. The trust boundary is always live, always visible, always adjustable.

**B) Task-Based** (matches Codex's actual pattern):
User says "do this task" → Manifold scopes access for that task → task completes → access reverts. Lighter than sessions.

**C) Hybrid** (current front-runner):
Standing access is the default. "Tracked work blocks" are an opt-in mode for sensitive work — snapshots beforehand, tracks changes, offers rollback at the end. Most of the time, access just works. The safety net is there when you want it.

### What We Lose Without Sessions
Pre-session snapshots (rollback safety net), PromoteEngine's conflict resolution, session-scoped email exceptions that auto-expire, audit trail grouped by session.

### What We Gain With Standing Access
No reconfiguration per session. No friction for quick tasks. App feels like a control panel that's always on. Users who want safety can opt into tracked work blocks.

---

## v3 Access Grant Design (In Progress)

### Improvements Over v2
1. **Domain-level email selection** — Users check/uncheck entire domains (@company.com), not individual emails. Category chips (Work, Automated, Personal, Auto-hidden) for grouping.
2. **Centralized scope review** — One tabbed surface (Files | Emails | Options) instead of controls scattered across 4 locations.
3. **Visual toggle states** — Green row + left border = included. Dimmed = excluded. Trust boundary visible at a glance through color.
4. **Live footer counts** — Three updating numbers: files included, emails visible, emails auto-hidden. The red auto-hidden counter is the trust signal.
5. **During-session modification** — "Modify scope" reopens the scope review without restarting the session.
6. **Auto-hidden domains visible but disabled** — Banking, health, 2FA domains shown with reason badges (🚫 banking, 🚫 2FA, 🚫 health). Users see what's blocked and why.

### Critical User Feedback (Core Philosophy)
> The user must be able to clearly see their files and emails and be able to select them. The purpose of the app is to allow the user to clearly work and see, not have it be magic in the background. It's about ownership and control of THEIR DATA.

This means:
- **Files and Emails tabs are the core of the product**, not secondary. They're where users exercise ownership.
- **Access controls should live where the data lives** — inline in the Files and Emails tabs, not in a separate scope review surface.
- **History is less essential** than Files and Emails. If something needs to be cut, History can become a detail pane rather than a top-level tab.

---

## Identified Gaps and Problems

### Critical
1. **No persistent email defaults** — Every session starts from scratch on email domain selection. Users will either abandon email access or set sensitivity to "Open" (defeats trust model).
2. **No persistent sensitivity default** — Resets every session. A security setting that resets teaches users it doesn't matter.
3. **Missing panic button** — "End Session" triggers PromoteEngine (applies changes). Need "Kill Session" that immediately terminates and rolls back. Emergency exit should be the most visible control.

### Honesty Problems
4. **Category chips look like access controls but are just view filters** — User clicks "Work" and expects they've done something to work email access. They haven't. Should either be actual bulk actions or visually distinct from controls.
5. **Email domain count is a snapshot presented as a boundary** — "247 emails" implies a fixed set, but it's actually a live stream of all future emails from that domain during the session.

### Asymmetries
6. **Files have persistent defaults but emails don't** — Mental model for files doesn't transfer to emails. @company.com is as stable as ~/Projects/web-app.
7. **"Add to this session" vs "Modify scope"** — Two paths to the same outcome (changing active access). Nothing explains when to use which.

### Edge Cases
8. **Concurrent session scope modification** — When modifying Claude's scope while Codex is also active, the agent picker should be locked to prevent accidentally modifying the wrong session.
9. **Cannot change timeout mid-session** — No path to extend or reduce timeout during active work.

---

## Design Principles

1. **Visibility is the product.** Users must SEE their data to CONTROL their data. You can't make informed access decisions about abstractions.
2. **Users think in categories, not items.** Domain-level email grouping. Folder-level file grouping. Bulk actions first, per-item as escape hatch.
3. **The toggle should feel satisfying.** Green = included, dim = excluded. Trust boundary visible through color, not labels.
4. **Access controls live where the data lives.** Don't force a context switch to configure access. The Files tab shows files AND their access state. The Emails tab shows emails AND their visibility.
5. **Show me the incentive and I'll show you the outcome.** If granting access is too frictional, users will set everything to Open. If it's too easy, users won't think. The right choice must be the easy choice.
6. **Care is the signal** (LoveFrom/Ive). When users feel the app was made with care for them and their data, they trust it. Transparency, clear feedback, satisfying interactions.

---

## File Inventory

| File | Purpose | Status |
|------|---------|--------|
| `Package.swift` | SPM manifest: ManifoldKit, ManifoldCLI, ManifoldMCP | Complete |
| `Sources/ManifoldKit/` (34 files) | Core backend logic | Complete, 230+ tests |
| `Sources/ManifoldMCP/` (5 files) | MCP server, 16+ tools | Complete |
| `Sources/ManifoldCLI/` | CLI interface | Complete |
| `ManifoldApp/ManifoldApp/` | SwiftUI app | Being rebuilt |
| `design/LAYOUT-SPEC.md` | Authoritative UI spec (v2) | Needs v3 update |
| `design/manifold-wireframe.html` | Interactive prototype (v2) | Needs v3 update |
| `design/permission-controls.html` | Access pattern exploration | Needs v3 update |
| `design/navigation-flows.mermaid` | Navigation flow diagram | Needs v3 update |
| `design/access-grant-v3.html` | v3 scope review prototype | NEW, under review |
| `design/ACCESS-GRANT-SUMMARY.md` | Complete access grant summary | Current |
| `design/access-grant-interactions.mermaid` | All interaction paths diagram | Current |
| `design/access-grant-lovefrom-review.html` | LoveFrom design critique + interaction map | Current, amended |

---

## Key Swift Data Structures

```swift
// Agent identity
enum TargetApp { case cowork, codex }

// Grant lifecycle
enum GrantStatus { case active, ended, timedOut }

// Email sensitivity levels
enum EmailSensitivity { case strict, moderate, open }

// Session options
enum SessionNoteCaptureMode { case off, basic, verbose }

// Promotion results (3-way merge)
enum PromotionOutcome { case applied, conflict, skipped, newFile }

// Source = user-approved folder
struct SourceRecord {
    let id: String
    let path: String
    let displayName: String
    let status: SourceStatus
}

// Grant = time-bounded access session
struct GrantRecord {
    let id: String
    let targetApp: TargetApp
    let status: GrantStatus
    let createdAt: Date
    let endedAt: Date?
    let timeoutInterval: TimeInterval
}

// Per-source default access (persistent preference)
struct SourceDefaultAccess {
    let sourceID: String
    let includeForClaude: Bool
    let includeForCodex: Bool
}

// Session scope review state
struct SessionReviewState {
    var targetApp: TargetApp
    var selectedSourceIDs: Set<String>
    var emailSensitivity: EmailSensitivity
    var selectedEmailDomains: Set<String>
    var temporaryEmailExceptions: Set<String>
    var noteMode: NoteCaptureMode
    var timeout: TimeInterval
    var preset: DomainPreset?
}
```

---

## Dependencies (from SPM resolution)

- swift-system (Apple)
- swift-nio (Apple — networking)
- swift-log (Apple — logging)
- swift-collections (Apple — data structures)
- swift-atomics (Apple — concurrency primitives)
- eventsource (SSE client)
- swift-sdk (Anthropic/OpenAI SDK)

No third-party UI libraries. No Electron, no web views. Pure native SwiftUI.
