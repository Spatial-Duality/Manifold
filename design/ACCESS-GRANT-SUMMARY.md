# Manifold Access Grant — Complete Summary for Review

> **Date**: April 10, 2026
> **Author**: Amar Gandhi + Claude
> **Purpose**: Complete summary of the access grant design — the core function of Manifold. Covers all ideas, issues, resolved decisions, and open questions. Intended as a handoff document for Codex review.

---

## What Manifold Is

Manifold is a native macOS app (Swift 6, SwiftUI, macOS 26 Liquid Glass) that controls which files and emails AI agents can access. It sits between your data (local folders, email accounts) and AI agents (Claude/Cowork and Codex). The entire product reduces to one question: **"What can this AI see?"**

The backend is complete: ManifoldKit (GrantStore, ContentStore, SnapshotStore, MaterializationEngine, PromoteEngine, EmailStore, AuditStore) and ManifoldMCP (12+ MCP tools via JSON-RPC 2.0 stdio). The UI is being rebuilt from scratch.

---

## The Three-Layer Trust Model

Access control operates across three layers, inspired by Apple's privacy patterns:

### Layer 1: Persistent Defaults (Files sidebar)
- **What**: Per-source folder checkboxes — one for Claude (blue), one for Codex (purple)
- **Scope**: Permanent user preference. Survives across sessions.
- **Effect**: Pre-populates Layer 2. Does NOT grant access on its own.
- **Location**: Files tab → Left sidebar → "Default access for new sessions" section
- **Granularity**: Source folder level only (not individual files)
- **Design rationale**: NN/g checkbox guidelines (independent, non-exclusive selections), Cooper mental model matching ("I usually share web-app with Claude")

### Layer 2: Session Scope Review (Home tab, mandatory)
- **What**: The trust boundary commitment. User reviews and confirms exactly what the agent can access before a session starts.
- **Scope**: Per-session, per-agent. Dies when session ends.
- **Effect**: Creates the actual grant. Materializes the workspace.
- **Location**: Home tab → triggered by "Start Session" button
- **Granularity**: Source folder toggles (files) + domain-level bulk selection (emails) + sensitivity floor
- **Design rationale**: Apple's "Selected Photos" picker pattern — you decide scope upfront, not item-by-item during use

### Layer 3: Temporary Session Exceptions (during active session)
- **What**: Escape hatch for adding access to something not in the original scope
- **Scope**: Per-session only. Auto-expires when session ends.
- **Effect**: Amends the active grant without restarting
- **Location**: During-session access bar (Home tab) or Email reading pane
- **Granularity**: Individual email level (for sensitivity-hidden emails), individual source folder level (for files)
- **Design rationale**: Apple's "Allow Once" — scoped, explicit, self-cleaning. No permanent per-email overrides in v1.

---

## Concurrency Model

Claude and Codex can run simultaneous sessions on the same sources. Each gets its own materialized workspace (copy). If both modify the same file, PromoteEngine handles conflict resolution at session end. The UI shows both agents in the top bar with status dots (blue=Claude, purple=Codex) and stacks session cards when concurrent.

---

## Issues Identified with v2 Design

### Issue 1: Email access model is backwards (P1)
- **Problem**: v2 puts email exceptions in the reading pane — browse to hidden email → read it → click "Add to this session." This is discovery-then-decide when users want decide-then-use.
- **Real mental model**: "Give Claude all my work emails. Hide personal and financial." That's a bulk decision by domain/category, not per-email.
- **Incentive analysis**: If granting access to a single email requires navigating to it, reading it, and clicking a button, users will just set sensitivity to "Open" to avoid friction. That defeats the entire trust model.
- **Precedent**: Apple Photos "Selected Photos" shows a grid picker for bulk selection. They don't make you open each photo individually.

### Issue 2: Access controls are dispersed across 4 locations (P2)
- **Problem**: v2 scatters access configuration across: (a) Files sidebar persistent checkboxes, (b) Home tab scope review, (c) Email reading pane "Add to this session," (d) Email sidebar sensitivity dropdown.
- **Effect**: User must visit multiple surfaces to do the one thing the app exists for.
- **Krug**: "Don't make me think" also means "don't make me remember where things are."
- **Solution**: Session Scope Review should be the SINGLE surface for configuring everything — files AND emails. Persistent defaults stay in Files sidebar but are clearly secondary.

### Issue 3: The grant moment doesn't feel like the product (P2)
- **Problem**: v2's scope review is an expansion panel under the session card. Framed as a confirmation dialog, not the main event. Squeezed alongside stat pills and activity feeds.
- **Incentive analysis**: If the scope review is visually subordinate to stat pills, users treat it as a speed bump to click through.
- **Solution**: Scope review should take over the content area as a dedicated view or prominent sheet. Not an expansion panel.

---

## v3 Proposed Solutions

### Solution A: Centralized Tabbed Scope Review
A dedicated, bordered surface with three inner tabs: Files | Emails | Options.

**Files tab:**
- Source-level toggle rows with strong visual states (green background + left border = included, dimmed = excluded)
- "Include all / Exclude all" bulk action buttons
- Each row shows: icon, folder name, path, file count, size, toggle switch
- Live count updates in tab badge and footer

**Emails tab:**
- Sensitivity picker inline (Strict / Moderate / Open) — not buried in a sidebar
- Category chips: All, Work, Automated, Personal, Auto-hidden — for filtering the domain list
- Domain-level checkboxes: check/uncheck entire domains (@company.com, @github.com, etc.)
- Each domain shows: icon, domain name, category badge, email count
- Auto-hidden domains (banking, health, 2FA) are visible but disabled with reason badges
- Users see what's blocked and why, right in the selection flow

**Options tab:**
- Session notes mode (Off / Basic / Verbose)
- Inactivity timeout
- Domain preset

**Footer (always visible across all tabs):**
- Three live-updating numbers: files included, emails visible, emails auto-hidden
- Buttons: Cancel, Save as Defaults, Start Session →
- The red "auto-hidden" counter is the trust signal

**Agent switcher:**
- At top of scope review: Claude | Codex toggle
- Each agent gets independent configuration
- Pre-populated from Layer 1 persistent defaults for the selected agent

### Solution B: During-Session Access Bar
Once a session is running, a persistent bar on the Home tab shows:
- Live session status (agent, duration, active dot)
- Current access: per-source rows with status tags (included/not included) and Revoke buttons
- "Modify scope" button: reopens the Scope Review with current session state for live adjustments without restart
- Temporary email exceptions log with timestamps and Remove buttons
- Per-email exceptions still available as escape hatch from the Email reading pane

---

## All Access Grant Interaction Paths

### How a user grants FILE access:

| Path | Granularity | Scope | When | Where |
|------|------------|-------|------|-------|
| Set persistent default | Source folder | Permanent (all future sessions) | Before any session | Files tab → sidebar checkboxes |
| Toggle in Scope Review | Source folder | This session only | Before session starts | Home tab → Scope Review → Files tab |
| "Include all" bulk action | All source folders | This session only | Before session starts | Scope Review → Files tab → button |
| Add during session | Source folder | This session only | Mid-session | During-Session bar → "Add to session" |
| Revoke during session | Source folder | This session only | Mid-session | During-Session bar → "Revoke" |
| Modify scope mid-session | Source folder | This session only | Mid-session | During-Session bar → "Modify scope" → reopens Scope Review |

**Note**: There is NO individual file-level access control in v1. Access is always at the source folder level. The agent sees all files in an included folder, or none.

### How a user grants EMAIL access:

| Path | Granularity | Scope | When | Where |
|------|------------|-------|------|-------|
| Set sensitivity floor | Category-level (banking/health/2FA/all) | This session | Before session starts | Scope Review → Emails tab → sensitivity picker |
| Check/uncheck domain | Domain level (@company.com) | This session | Before session starts | Scope Review → Emails tab → domain checkboxes |
| Filter by category chip | View filter (Work/Auto/Personal/Hidden) | Display only (not access) | Before session starts | Scope Review → Emails tab → category chips |
| Add temporary exception | Individual email | This session only, auto-expires | Mid-session | Email reading pane → "Add to this session" |
| Remove exception | Individual email | This session only | Mid-session | During-Session bar → exceptions log → "Remove" |
| Modify scope mid-session | Domain level | This session | Mid-session | During-Session bar → "Modify scope" → Scope Review |

### How access is scoped by TIME:

| Duration | What it covers | Mechanism |
|----------|---------------|-----------|
| Permanent (cross-session) | Source folder defaults per agent | Layer 1: Files sidebar checkboxes |
| Session lifetime | All file and email access grants | Layer 2: Scope Review creates grant; session end destroys it |
| Session lifetime (exception) | Individual sensitive emails | Layer 3: "Add to this session" — auto-expires on session end |
| Session lifetime (timeout) | Everything in the session | Inactivity timeout (30m/1h/2h/4h/none) auto-ends the session |

### How access is scoped by AGENT:

| Mechanism | Per-agent? | Details |
|-----------|-----------|---------|
| Persistent defaults | Yes | Independent Claude/Codex checkboxes per source |
| Session Scope Review | Yes | Agent picker at top — one review = one agent |
| Active session grant | Yes | Each agent has its own materialized workspace |
| Email sensitivity | Per-session (inherits agent) | Set in Scope Review for the selected agent's session |
| Temporary exceptions | Per-session (inherits agent) | Exception is for the agent whose session it belongs to |
| Concurrent sessions | Yes | Both agents can have active sessions simultaneously with different scopes |

### How access is scoped GLOBALLY vs. per-AI:

| Scope | Examples | Notes |
|-------|----------|-------|
| Global to all AIs | Source folders exist in the sidebar regardless of agent. Email accounts are shared. Sensitivity categories (banking/health/2FA) apply universally. | Infrastructure is shared; access decisions are per-agent. |
| Per-AI | Which folders are included. Which email domains are checked. Sensitivity level (could differ). Session options. Active grant. Materialized workspace. | Every access decision is per-agent, per-session. |
| No global "share with all AIs" toggle | By design. Each agent session is configured independently. If you want both agents to see the same thing, you configure two separate sessions. | This is deliberate: different agents have different trust levels and use cases. |

---

## Resolved Design Decisions

1. **Checkboxes for persistent defaults** (not toggles) — NN/g: checkboxes for independent binary selections. Two per source (Claude + Codex).
2. **Mandatory scope review before grant** — Cooper's commensurate effort: access to user data should require deliberate confirmation.
3. **Sensitivity as a floor, not a filter** — Strict/Moderate/Open determines which domains are auto-hidden. You can't grant access to auto-hidden domains in the Scope Review; only via temporary exception.
4. **Temporary exceptions only in v1** — No permanent per-email overrides. Apple's "Allow Once" pattern. Prevents growing list of forgotten decisions.
5. **Domain-level email selection** (v3) — Users think in categories, not individual messages.
6. **One surface for all grant configuration** (v3) — Tabbed scope review replaces 4 scattered locations.
7. **Visual toggle states with color coding** (v3) — Green row = included, dimmed = excluded. Trust boundary is visible at a glance.
8. **Live footer counts** (v3) — Three numbers always visible: files included, emails visible, emails auto-hidden.

---

## Open Questions / Not Yet Decided

1. **Scope Review as expansion panel vs. sheet vs. full-content takeover?** — v2 used expansion panel (rejected as too subordinate). v3 prototype shows it as a bordered inline component. Could also be a modal sheet or a full content area replacement. Needs final decision.
2. **Can sensitivity differ between Claude and Codex sessions?** — Currently per-session, so technically yes. But is that confusing? Should there be a global sensitivity floor?
3. **Domain-level email selection: what about domains with mixed content?** — e.g., @gmail.com has both work and personal contacts. Do we need sub-domain or sender-level selection in a future version?
4. **"Save as Defaults" from Scope Review** — Does this save BOTH file toggles AND email domain selections? Or just file toggles? Email domain selections may not make sense as persistent defaults since email content changes.
5. **Presets** — How much do presets override? Just sources? Sources + sensitivity? Everything? Can users create custom presets?
6. **Individual file exclusion** — v1 has no per-file access control (all-or-nothing at folder level). Is this a v2 feature need? Could be done with glob patterns or .manifoldignore.
7. **Email access for Codex** — Is email access even relevant for a code-focused agent? Should the Emails tab in Scope Review be hidden/disabled when configuring Codex?

---

## File Inventory

| File | Purpose | Status |
|------|---------|--------|
| `design/LAYOUT-SPEC.md` | Authoritative spec for Claude Code to build SwiftUI views | v2 current, needs v3 access grant update |
| `design/manifold-wireframe.html` | Interactive clickable prototype, all 4 tabs | v2 current, needs v3 update |
| `design/permission-controls.html` | Access control pattern exploration (4 patterns) | v2 current, needs v3 update |
| `design/navigation-flows.mermaid` | Full navigation/state flow diagram | v2 current, needs v3 update |
| `design/access-grant-v3.html` | Interactive v3 prototype (scope review + during-session) | NEW, pending approval |
| `ManifoldKit/` | Backend core logic | Complete, preserved |
| `ManifoldMCP/` | MCP server (12+ tools) | Complete, preserved |
| `ManifoldApp/` | SwiftUI app shell | Being rebuilt from design specs |

---

## Key Data Structures

```swift
// Layer 1: Persistent defaults
struct SourceDefaultAccess {
    let sourceID: String
    let includeForClaude: Bool
    let includeForCodex: Bool
}

// Layer 2: Session scope review state
struct SessionReviewState {
    var targetApp: TargetApp              // .cowork or .codex
    var selectedSourceIDs: Set<String>
    var emailSensitivity: EmailSensitivity // .strict, .moderate, .open
    var selectedEmailDomains: Set<String>  // v3: domains user checked
    var temporaryEmailExceptions: Set<String>
    var noteMode: NoteCaptureMode         // .off, .basic, .verbose
    var timeout: TimeInterval
    var preset: DomainPreset?
}

// Email sensitivity categories
enum EmailSensitivity {
    case strict   // only explicitly allowed domains
    case moderate // hides banking, health, 2FA
    case open     // everything visible except deny-listed
}

// Agent identity
enum TargetApp {
    case cowork  // Claude
    case codex   // Codex
}
```

---

## Design Principles

1. **The grant IS the product.** Manifold doesn't manage files or read emails. Its only job is to control what AI agents can see. The scope review gets the most design attention, screen real estate, and interaction polish.

2. **Users think in categories, not individual items.** Domain-level email grouping. Source folder-level file grouping. Category chips. Bulk actions. Per-item selection exists as escape hatch only.

3. **The toggle should feel satisfying.** Green background + left border = included. Dimmed = excluded. Trust boundary is visible at a glance through color, not by reading labels.

4. **One surface, three tabs, zero scattering.** Everything about the grant happens in the Scope Review. During the session, "Modify scope" reopens the same surface.

5. **Show the boundary, not the count.** Three live numbers: files included, emails visible, emails auto-hidden. The red counter proves the filter is working. Numbers update in real time as you toggle.

6. **Show me the incentive and I'll show you the outcome.** If granting access is too frictional, users will set everything to Open. If it's too easy, users won't think about what they're sharing. The design must make the right choice the easy choice.
