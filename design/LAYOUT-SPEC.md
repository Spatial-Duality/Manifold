# Manifold UI Layout Specification v2

> **Purpose**: Authoritative reference for Claude Code when building Manifold's SwiftUI interface. Maps every backend feature to a specific UI location. Incorporates design review findings and research from Apple HIG, About Face (Cooper), Don't Make Me Think (Krug), NN/g guidelines, and Designing Interfaces (Tidwell).
>
> **Design language**: macOS 26 Liquid Glass. SF Pro + SF Mono. System semantic colors. Base-4 spacing (4/8/12/16/24/32). This spec covers LAYOUT and INTERACTION MODEL — where things go, how they behave, and why.
>
> **Core design principle**: Manifold's UI must make the trust boundary — what the AI agent can access — the primary organizing concept, not a secondary detail.

---

## App Shell Structure

Layout inspired by the Claude desktop app. Right sidebar is **collapsed by default** and only appears when the user explicitly inspects a file.

```
┌─────────────────────────────────────────────────────────┐
│ TOP BAR                                                 │
│ [M Manifold]    [Home | Files | Emails | History]    [🔍 Search ⌘K] [● Claude] │
├────────────┬────────────────────────────────────────────┤
│            │                                            │
│  LEFT      │      MAIN CONTENT                         │
│  SIDEBAR   │      (tab-specific)                       │
│  (context- │                                            │
│  sensitive │                              ┌────────────┐│
│  per tab)  │                              │ RIGHT      ││
│            │                              │ SIDEBAR    ││
│            │                              │ (collapsed ││
│            │                              │ by default)││
├────────────┤                              └────────────┘│
│ [AG] Amar  │                                            │
│ ⚙ Settings │                                            │
└────────────┴────────────────────────────────────────────┘
```

### Top Bar
- **Left**: App icon + "Manifold" label
- **Center**: Segmented control with 4 tabs: **Home**, **Files**, **Emails**, **History**
  - This is the PRIMARY navigation
- **Right**: Search bar (⌘K trigger), connection status dot(s), connected agent name(s)
  - Search opens Command Palette overlay
  - Connection status shows BOTH agents if both connected (blue dot + "Claude", purple dot + "Codex")
  - If concurrent sessions exist, show both with their status

### Left Sidebar (240pt wide)
- Context-sensitive per active tab
- Profile/settings footer always visible at bottom
- Scrollable content area

### Main Content
- Full remaining width (or splits into sub-panes for Emails/History)
- Tab-specific layout

### Right Sidebar (300pt wide, collapsed by default)
- **Only appears** when user clicks a file row in Files, a file event in History, or a file in the activity feed
- Close via ✕ button or Escape key
- Contextual to what was clicked: file details, version history, diff, or email metadata
- **Never open by default on any tab**

### Profile/Settings Footer (bottom of left sidebar, always visible)
- User avatar (initials), display name
- "Settings" subtitle text
- Gear icon → opens Settings window

---

## Interaction Model: Access Control

### Three-Layer Trust Model

Manifold uses a three-layer access control model:

1. **Persistent defaults** (Files sidebar) — "Include by default for new sessions"
2. **Session scope review** (Home tab, mandatory before grant creation) — "Accessible this session"
3. **Temporary session exceptions** (Emails only, v1) — "Added to this session"

This mirrors Apple's privacy pattern: app-level defaults (Settings → Privacy), scoped permission prompts (Selected Photos / Allow Once), and temporary access that expires.

### Important: Concurrent Sessions

Claude (Cowork) and Codex can each have their own active session simultaneously, with separate materialized workspaces. The same source can appear in both sessions. If both agents modify the same file, each has its own copy — the PromoteEngine handles conflict resolution at session end. The UI must surface this clearly when it occurs.

---

## Tab 1: HOME

### Left Sidebar Content
```
SECTION: Session
  [Dashboard]              ← active by default
  [▶ Start Session]        ← opens Session Scope Review

DIVIDER

SECTION: Sources
  [📁 ~/Projects/web-app]    [● green = in active session]
  [📁 ~/Documents/specs]     [● green]
  [📁 ~/Desktop/assets]      [● gray = idle]
  [+ Add Folder…]

DIVIDER

SECTION: Quick Actions
  [Storage]       [2.4 GB badge]
  [MCP Status]    [● green dot]
```

### Main Content
Scrollable vertical stack:

1. **Session Card** — shows one of four states:
   - **Empty state**: No sources → "Add a folder to get started" + CTA
   - **Ready to start**: Summary of defaults + "Start Session" button → opens Session Scope Review
   - **Active session(s)**: One card per active session. Each shows: agent badge (blue=Claude, purple=Codex), live stats (reads/writes/searches), elapsed time, source count, "Review Changes" + "End Session" buttons. If both agents have active sessions, show TWO cards stacked.
   - **Session recap**: After end — files applied/conflicted/skipped/new, session notes

2. **Stats Row** — horizontal pill buttons navigating to tabs

3. **Recent Activity Card** — last 5 audit entries with "See all →"

4. **Last Session Recap Card** — agent badge, time range, outcome counts, session notes

### Session Scope Review (expansion panel or sheet)

**This is the trust boundary.** Opens when user clicks "Start Session". Must be completed before any grant is created.

```
┌─────────────────────────────────────────────────────┐
│ REVIEW SESSION SCOPE                                │
│ Confirm what the agent can access before starting   │
│                                                     │
│ Agent: [Claude ◉ | ○ Codex]                         │
│                                                     │
│ ─── FILES & FOLDERS ──────────────────────────────  │
│ ☑ web-app          182 files · 1.1 GB               │
│ ☑ specs             43 files · 89 MB                │
│ ☐ assets            22 files · 156 MB               │
│                                                     │
│ ─── EMAIL ACCESS ─────────────────────────────────  │
│ Sensitivity: [Moderate ▼]                           │
│ 1,089 visible · 158 auto-hidden · 14 shared        │
│                                                     │
│ ─── SESSION OPTIONS ──────────────────────────────  │
│ Session notes:       [Basic ▼]                      │
│ Inactivity timeout:  [1 hour ▼]                     │
│ Preset:              [General ▼]                    │
│                                                     │
│ ─────────────────────────────────────────────────── │
│ 225 files (1.2 GB) + 1,089 emails accessible       │
│                                                     │
│         [Cancel]  [Save as Defaults]  [Start →]     │
└─────────────────────────────────────────────────────┘
```

**Behavior:**
- Agent picker at top: segmented control, exclusive selection (one session = one agent)
- Source checklist: pre-populated from persistent defaults for selected agent
- Editing does NOT mutate persistent defaults unless user explicitly clicks "Save as Defaults"
- Email section shows sensitivity level, visible/hidden/shared counts
- Session options: note capture mode (off/basic/verbose), timeout, domain preset
- Footer shows exact scope summary: file count, total size, email count
- "Start Session →" creates the grant and materializes the workspace

---

## Tab 2: FILES

### Left Sidebar Content
```
SECTION: Sources
  [All Files]            [247 badge]

DIVIDER

  [📁 web-app]           [182 badge]  ← expandable file tree
    └ src/
    └ components/
    └ package.json
  [📁 specs]              [43 badge]
  [📁 assets]             [22 badge]

DIVIDER

SECTION: Default Access for New Sessions
  ┌───────────────────────────────────────────┐
  │              ● Claude    ● Codex          │
  │ web-app      [☑]         [☑]             │
  │ specs        [☑]         [☐]             │
  │ assets       [☐]         [☐]             │
  └───────────────────────────────────────────┘

DIVIDER

SECTION: Versions
  [Recently Modified]    [12 badge]
  [Conflicts]            [2 badge, red]
  [AI-Touched Files]     [8 badge]

DIVIDER

  [+ Add Folder…]
```

**Default Access Controls — Design Decision (approved)**:

Two independent checkboxes per source — one for Claude (blue), one for Codex (purple). These are PERSISTENT DEFAULTS, not live permissions.

Design rationale:
- **NN/g Checkbox Guidelines**: Checkboxes are for independent, non-exclusive selections. Each agent's access is an independent binary question.
- **Don't Make Me Think (Krug)**: The meaning is obvious at a glance — blue checked = Claude gets this by default, purple checked = Codex gets this by default. Both unchecked = not included in any session.
- **Apple HIG**: No third "Off" control needed. Both unchecked IS off. Don't add a control for a state that's already represented by the absence of selection.
- **About Face (Cooper)**: Match the user's mental model. Users think "I usually share web-app with Claude" — the checkbox says exactly that.

Behavior:
- Changing these updates persistent preference data only
- They do NOT create or modify an active grant
- They pre-populate the Session Scope Review checklist
- A source can be default-on for both Claude and Codex simultaneously
- Label the section "Default access for new sessions" to make the scope explicit
- If sidebar width is tight, collapse the source path metadata — never collapse the per-agent checkboxes

### Main Content — File Table
```
TOOLBAR: [Source ▼] [Sort ▼] [Filter files…] [247 files]

TABLE HEADER: [icon] Name | Source | Size | Modified | Vers. | AI
TABLE ROWS:
  [⬡] Header.tsx       web-app    4.2 KB   2m ago    3 ✨   ✓
  [⬡] auth.ts          web-app    2.1 KB   3m ago    1      ✓
  ...

CONTENT SEARCH BAR (toggleable):
  [Search inside files…] [Search] [Clear]
  → Results as horizontal scrollable cards with matching lines
```

- File icons colored by language (Swift=orange, TS=blue, Python=blue, JS=yellow)
- "✨" sparkle on version count = AI has touched this file
- "✓" in AI column = currently accessible in active session (not just default)
- Click any row → opens Right Sidebar with file details
- Right-click → context menu: Open, Reveal in Finder, Quick Look, View History, Copy Path

### Right Sidebar (shown on file click, collapsed by default)
```
FILE DETAILS
  Header.tsx
  web-app/src/components/

  ┌──────┐ ┌──────┐
  │ Size │ │ Type │
  │4.2 KB│ │ TSX  │
  └──────┘ └──────┘

VERSION HISTORY
  [✏ Modified by Claude]     2m ago
  [✏ Modified by Claude]     Yesterday 3:15 PM
  [B Baseline]               Yesterday 2:14 PM

DIFF PREVIEW
  ┌─────────────────────────────────┐
  │ - export function Header() {    │
  │ + export function Header(props) │
  │   return (                      │
  │ +   <nav className="header">    │
  └─────────────────────────────────┘

ACTIONS
  [Restore] [Reveal] [Quick Look]
```

---

## Tab 3: EMAILS

Read-only archive viewer. No read/unread tracking. This is a backup browser, not an email client.

### Left Sidebar Content
```
SECTION: Accounts
  [📬 All Mail]           [1,247 badge]

  [📧 work@company.com]
    └ Inbox               [342]
    └ Sent
    └ Archive
    └ Drafts

  [📧 personal@gmail.com]
    └ Inbox               [905]
    └ Sent

DIVIDER

SECTION: Smart Mailboxes
  [📎 Has Attachments]
  [🏷 Flagged]
  [📅 This Week]
  [+] ← create new smart mailbox (rule editor sheet)

DIVIDER

SECTION: Session Email Access
  ┌─────────────────────────────┐
  │ Sensitivity  [Moderate ▼]   │
  │ 1,089 visible this session  │
  │ 158 auto-hidden             │
  │ 0 temporary exceptions      │
  └─────────────────────────────┘

DIVIDER

  [+ Add Account…]
```

### Main Content — Two-Pane Email Layout

```
┌──────────────────────┬──────────────────────────────────┐
│ MESSAGE LIST (360pt) │ READING PANE (remaining width)   │
│                      │                                   │
│ [Search emails…]     │ Subject: Re: API design review    │
│ [All|Attach|Flag|Wk] │ From: Alex Chen                  │
│                      │ To: amar@company.com              │
│ ┌──────────────────┐ │ Date: Apr 10, 2026               │
│ │ Alex Chen    10:42│ │                                   │
│ │ Re: API design…  │ │ [Add to this session] ← if hidden │
│ │ Hey, I looked…   │ │ ─────────────────────────────     │
│ ├──────────────────┤ │                                   │
│ │ Bank of America  │ │ Email body (read-only HTML/text)  │
│ │ 🚫 Banking       │ │                                   │
│ ├──────────────────┤ │ 📎 auth-review-notes.pdf (245KB) │
│ │ GitHub           │ │                                   │
│ │ 🚫 2FA           │ │                                   │
│ └──────────────────┘ │                                   │
└──────────────────────┴──────────────────────────────────┘
```

**Message List Pane** (360pt):
- Search input + filter chips: All, Attachments, Flagged, This Week, Session Exceptions
- Each email row: From, Subject, Preview, Date
- Auto-hidden emails show reason badge inline: 🚫 Banking, 🚫 2FA, 🚫 Health
- No read/unread indicators

**Reading Pane**:
- Header: Subject (large), From, To, Date
- For auto-hidden emails: show WHY it's hidden (domain category) + "Add to this session" button
- For visible emails: no extra controls needed (they're already accessible)
- Email body (read-only HTML or plain text)
- Attachment list
- "read-only" tag

**Email Access Model (approved v1)**:
- Sensitivity level (strict/moderate/open) is the hard floor — set in Session Scope Review
- Sensitivity-blocked emails can be added as **temporary session exceptions** only
- Action label: "Add to this session" — never just "Share" or "Shared"
- Temporary exceptions appear in:
  - The sidebar "Session Email Access" section (count)
  - The Session Scope Review (if still open)
  - The session's History detail pane
- Exceptions expire automatically when the session ends or times out
- No permanent per-email overrides in v1

**Why temporary-only (v1)**:
- Apple's "Allow Once" pattern: scoped, explicit, self-cleaning
- Permanent overrides create a growing list of forgotten decisions
- Keeps the trust model explainable: "Moderate hides banking/health/2FA, you can add specific emails for this session only"

---

## Tab 4: HISTORY

### Left Sidebar Content
```
SECTION: View
  [Sessions]       ← default
  [Timeline]
  [By File]

DIVIDER

SECTION: Filter
  [All Actions]
  [Reads]
  [Writes]
  [Tool Calls]
  [Connections]
  [Restores]

DIVIDER

SECTION: Agents
  [● Cowork (Claude)]    ← blue
  [● Codex]              ← purple

DIVIDER

SECTION: Export
  [Copy Summary]
  [Export Markdown]
```

### Main Content — Two-Pane (list + detail)

```
┌──────────────────────┬──────────────────────────────────┐
│ SESSION LIST (360pt) │ SESSION DETAIL (remaining width) │
│                      │                                   │
│ ┌──────────────────┐ │ Cowork (Claude) — Active          │
│ │● Cowork ● Active │ │ Started today at 2:14 PM          │
│ │  Today 2:14–now  │ │                                   │
│ │  24r 8w 3s       │ │ ─── SCOPE ────────────────────── │
│ ├──────────────────┤ │ Sources: web-app, specs            │
│ │● Cowork          │ │ Email: Moderate (1,089 visible)    │
│ │  Y'day 2:14–3:42 │ │ Note mode: Basic                  │
│ │  47r 12w 6s      │ │ Timeout: 1 hour                   │
│ ├──────────────────┤ │                                   │
│ │● Codex           │ │ ─── STATS ────────────────────── │
│ │  Apr 8 10–11:15  │ │ ┌─────┐ ┌─────┐ ┌─────┐        │
│ │  31r 5w 2s       │ │ │ 24  │ │  8  │ │  3  │        │
│ └──────────────────┘ │ │Reads│ │Write│ │Srch │        │
│                      │ └─────┘ └─────┘ └─────┘        │
│                      │                                   │
│                      │ ─── SESSION NOTES ─────────────  │
│                      │ [Start] Working on auth refactor  │
│                      │ [Check] Completed token refresh   │
│                      │ [End] Auth endpoints updated...   │
│                      │                                   │
│                      │ ─── RUNTIME ───────────────────  │
│                      │ Agent: Claude via Cowork           │
│                      │ Connected: 2:14 PM                │
│                      │ Duration: 1h 28m (active)         │
│                      │ MCP connection ID: abc123          │
│                      │                                   │
│                      │ ─── EVENT LOG ─────────────────  │
│                      │ [✏] Modified Header.tsx    2m ago │
│                      │ [👁] Read auth.ts          3m ago │
│                      │ [🔧] search_files(…)      4m ago │
│                      │ [📧] Read email: Re: API…  6m ago │
│                      │                                   │
│                      │ ─── TEMPORARY EXCEPTIONS ──────  │
│                      │ 📧 alex@team.com: API review      │
│                      │   Added at 2:31 PM                │
└──────────────────────┴──────────────────────────────────┘
```

**Session Detail Pane (enhanced — addresses P2)**:

1. **Scope section**: Which sources were included, email sensitivity level, note mode, timeout. This is the actual grant scope, not defaults.
2. **Stats cards**: Read/Write/Search counts
3. **Session Notes**: Cards for each note kind (start, checkpoint, end). Shows the note content with timestamps.
4. **Runtime metadata**: Agent name, connection time, duration, MCP connection ID. This is the "why/how" context that differentiates Manifold from plain file browsing.
5. **Event Log**: Chronological audit trail with colored action icons
6. **Temporary email exceptions**: Which emails were manually added to this session, with timestamps

**Promotion Results (for ended sessions)**:
- Applied: ✅ count + file list (expandable)
- Conflicts: ⚠️ count + file list with reasons
- Skipped: count
- New files: 🆕 count + file list
- Deleted: 🗑 count + file list (flagged, originals preserved)

---

## Overlays & Modals

### Command Palette (⌘K)
- Glass-background modal overlay, centered, ~480×360pt
- Search field, filtered command list with icons and shortcuts
- Arrow key navigation, Enter to execute, Escape to close

### Onboarding Wizard (first launch, 6 steps)
1. Welcome + feature overview
2. Claude Desktop detection
3. MCP server installation
4. Add first source folder
5. Email account setup (optional)
6. Completion summary

### Email Account Setup (sheet, 6 steps)
1. Email address with auto-detection
2. Provider instructions
3. Credentials (password or OAuth)
4. Advanced IMAP (unknown providers)
5. Connection progress
6. Success or error diagnosis

### Settings Window (separate window, 5 tabs)
- General: Launch at Login, Notifications
- Connection: MCP status, Install/Reinstall, agent configs
- Email Backup: Accounts, sync controls, storage
- Storage: Size, maintenance, cleanup
- About: Version, bundle ID

---

## Feature → Location Map

| Feature | Tab | Panel | Element |
|---------|-----|-------|---------|
| **Session lifecycle** | | | |
| Start session | Home | Main → Scope Review | "Start Session" → mandatory review panel |
| End session | Home | Main | "End Session" button on active session card |
| Session scope review | Home | Main (expansion/sheet) | Agent picker + source checklist + email + options |
| Domain preset selection | Home | Scope Review | Preset dropdown in session options |
| Session note mode | Home | Scope Review | Note mode dropdown (off/basic/verbose) |
| Inactivity timeout | Home | Scope Review | Timeout dropdown |
| **Source management** | | | |
| Source folder list | Home + Files | Sidebar | Source items with status dots |
| Add source folder | Home + Files | Sidebar | "+ Add Folder…" |
| Pause/resume source | Files | Sidebar | Source context menu |
| Remove source | Files | Sidebar | Source context menu (with confirmation) |
| **Access control** | | | |
| Per-source default access (Claude) | Files | Sidebar | Independent checkbox, blue |
| Per-source default access (Codex) | Files | Sidebar | Independent checkbox, purple |
| Session-scoped source selection | Home | Scope Review | Source checklist (editable, from defaults) |
| Save as defaults | Home | Scope Review | Explicit "Save as Defaults" button |
| **File operations** | | | |
| File browsing | Files | Main | File table with toolbar |
| File filtering/sorting | Files | Main | Toolbar dropdowns + search |
| Content search (inside files) | Files | Main | Toggleable search bar |
| File version history | Files | Right sidebar | Version timeline (collapsed by default) |
| Diff preview | Files | Right sidebar | Syntax-highlighted diff block |
| File restore | Files | Right sidebar | Restore button |
| File context menu | Files | Main | Right-click: Open, Reveal, Quick Look, History, Copy Path |
| Archive browsing (zip) | Files | Right sidebar | When zip selected: contents list + extract |
| **Email** | | | |
| Email browsing | Emails | Main | Message list + reading pane |
| Email account tree | Emails | Sidebar | Expandable account/mailbox tree |
| Smart mailboxes | Emails | Sidebar | List + "+" for rule editor |
| Email sensitivity level | Emails | Sidebar + Scope Review | Dropdown (strict/moderate/open) |
| Temporary email exception | Emails | Main (reading pane) | "Add to this session" button |
| Session exception count | Emails | Sidebar | Count in Session Email Access section |
| Email search | Emails | Main | Search input + filter chips |
| Email attachments | Emails | Main (reading pane) | Attachment list |
| Auto-hidden email reason | Emails | Main (message list) | Reason badge: Banking, 2FA, Health |
| **History & audit** | | | |
| Session history | History | Main (left pane) | Session list with agent badges |
| Session scope display | History | Main (detail pane) | Scope section showing actual grant |
| Session notes display | History | Main (detail pane) | Note cards (start/checkpoint/end) |
| Runtime metadata | History | Main (detail pane) | Agent, duration, connection ID |
| Event timeline | History | Main (detail pane) | Chronological event log |
| Promotion results | History | Main (detail pane) | Applied/conflict/skipped/new/deleted counts |
| Temporary exceptions log | History | Main (detail pane) | Which emails were added to session |
| Action type filtering | History | Sidebar | Filter list |
| Agent filtering | History | Sidebar | Agent checkbox list |
| Export session summary | History | Sidebar | Copy Summary / Export Markdown |
| File version browser | History | Main (By File mode) | File list → version timeline |
| **System** | | | |
| Connection status | Top bar | Right | Status dot(s) + agent name(s) |
| Command palette | Overlay | — | ⌘K modal |
| MCP installation | Settings | Connection tab | Install button |
| Email account setup | Settings + Onboarding | — | Setup wizard |
| Storage management | Settings | Storage tab | Maintenance buttons |
| User profile | Sidebar footer | — | Avatar + name + gear |

---

## Keyboard Shortcuts

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘K | Open command palette | Global |
| ⌘1 | Switch to Home tab | Global |
| ⌘2 | Switch to Files tab | Global |
| ⌘3 | Switch to Emails tab | Global |
| ⌘4 | Switch to History tab | Global |
| ⌘⇧S | Start session (opens scope review) | Global |
| ⌘⇧E | End session | Global |
| ⌘⇧A | Add source folder | Global |
| Escape | Close right sidebar / command palette / scope review | Global |
| j/k or ↑/↓ | Navigate email list | Emails tab |
| Enter | Select/execute | Command palette, lists |
| ⌘, | Open Settings | Global |

---

## State Machines

### Session State
```
no_sources → (add source) → ready_to_start
ready_to_start → (click Start) → scope_review
scope_review → (click Start →) → computing_preview
scope_review → (click Cancel) → ready_to_start
computing_preview → (success) → active
computing_preview → (error) → scope_review [show error]
active → (click End) → promoting
promoting → (complete) → recap
recap → (dismiss) → ready_to_start
active → (timeout) → recap
```

### Source State
```
idle [gray dot] → (included in active session) → active [green dot]
active → (session ends) → idle
idle → (user pauses) → paused [dimmed, context menu]
paused → (user resumes) → idle
any → (user removes) → removed [hidden from sidebar]
```

### Connection State
```
disconnected [gray dot, "No agents"]
  → (agentConnected: "Claude") → connected_claude [blue dot, "Claude"]
  → (agentConnected: "Codex") → connected_codex [purple dot, "Codex"]
connected_claude + connected_codex → both_connected [blue dot + purple dot]
connected → (agentDisconnected) → disconnected (per agent)
connected → (accessDenied) → connected [show error banner]
```

---

## Implementation Notes

### New Data Requirement: Persistent Source Defaults
Store per-source default include flags by target app as preference data, separate from grants:
```swift
struct SourceDefaultAccess {
    let sourceID: String
    let includeForClaude: Bool  // default inclusion for Cowork/Claude sessions
    let includeForCodex: Bool   // default inclusion for Codex sessions
}
```
This is preference data, not grant data. Grants remain the sole source of truth for actual active access.

### Session Review State Model
```swift
struct SessionReviewState {
    var targetApp: TargetApp        // .cowork or .codex
    var selectedSourceIDs: Set<String>
    var emailSensitivity: EmailSensitivity
    var temporaryEmailExceptions: Set<String>  // email IDs added for this session
    var noteMode: NoteCaptureMode   // .off, .basic, .verbose
    var timeout: TimeInterval
    var preset: DomainPreset?
}
```

### UI Copy Distinctions
Use consistent terminology throughout:
- "Default access" or "Include by default" — persistent preferences
- "Accessible this session" — active grant scope
- "Add to this session" — temporary email exception
- Never "Shared" or "Hidden" without scope qualifier

### SwiftUI Structure
```swift
@main struct ManifoldApp: App {
    @State var store = ManifoldStore()
    var body: some Scene {
        WindowGroup {
            MainView().environment(store)
        }
        .defaultSize(width: 960, height: 640)
        .commands { /* shortcuts */ }
        Settings { SettingsView().environment(store) }
        MenuBarExtra("Manifold", systemImage: "m.circle.fill") {
            MenuBarView().environment(store)
        }
    }
}
```

### Key Patterns
- `@Observable` macro (NOT ObservableObject)
- Custom `HStack` layout for 3-column shell (left sidebar + content + right sidebar)
- `.glassEffect()` for Liquid Glass on macOS 26
- `@Environment` for dependency injection
- Raw SQLite (existing ManifoldKit) for persistence
- `async/await` for async operations
- `DisclosureGroup` for sidebar trees
- `Table` for file list (sortable columns)

---

## Design References

### Wireframes & Prototypes
- `design/manifold-wireframe.html` — Interactive layout prototype (4 tabs)
- `design/permission-controls.html` — Access control pattern exploration
- `design/navigation-flows.mermaid` — Navigation flow diagram

### Research Sources Applied
- Apple Human Interface Guidelines (developer.apple.com/design/human-interface-guidelines)
- Apple "Requesting access to protected resources" pattern
- Apple "Selected Photos" / "Allow Once" privacy patterns
- About Face: The Essentials of Interaction Design (Cooper, Reimann, Cronin, Noessel)
- Don't Make Me Think (Krug)
- Designing Interfaces (Tidwell)
- NN/g Toggle Switch Guidelines
- NN/g Checkbox Guidelines
- NN/g Permission Request Design
- macOS System Settings → Privacy → Files & Folders precedent
- Finder → Get Info → Sharing & Permissions precedent

### Backend Code (preserved)
- `ManifoldKit/` — Core logic
- `ManifoldMCP/` — MCP server
- `ManifoldCLI/` — CLI

### UI Code (to be rebuilt from this spec)
- `ManifoldApp/ManifoldApp/Models/` — State management (keep, refactor)
- `ManifoldApp/ManifoldApp/Views/` — Rebuild
- `ManifoldApp/ManifoldApp/Components/` — Rebuild (keep Spacing tokens)
