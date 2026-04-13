# Manifold UI Rebuild — Claude Code Implementation Prompt

> **What this is**: A complete implementation brief for rebuilding Manifold's four main views (Overview, Files, Emails Rules, Emails Messages) to match the interactive prototype and design specs. Read this entire document before writing any code.
>
> **Reference files you MUST read first**:
> - `design/manifold-prototype.jsx` — The interactive React prototype. This is the visual source of truth for layout, hierarchy, data shape, and interaction patterns. Every view, sidebar, table column, button, and state described below is implemented there.
> - `design/DESIGN-STANDARDS.md` — Design tokens, component specs, typography scale, empty states, animation presets. These are already partially implemented in `ManifoldApp/ManifoldApp/Components/DesignTokens.swift`.
> - `design/VISUAL-FIX-DECISIONS.md` — The 31 individual fix decisions with Apple HIG/WWDC25 rationale. Read this to understand WHY each design choice was made.
> - `design/EMAIL-CONTROLS-SPEC.md` — Full spec for the email rules/shields system that replaces the flat Domains tab.

---

## Existing Codebase You're Working With

### Design Tokens (ALREADY IMPLEMENTED — use these, don't recreate)

File: `ManifoldApp/ManifoldApp/Components/DesignTokens.swift`

This file already contains:
- `Color.claudeBlue`, `Color.codexPurple`, `Color.statusActive/Paused/Warning/Danger`, `Color.agent(_ type:)`
- `Typ.sectionTitle` (.title3.weight(.semibold)), `Typ.heading` (.headline), `Typ.body` (.callout), `Typ.caption`, `Typ.mono`, `Typ.numericBody`, `Typ.numericCaption`
- `Opacity.rowTint` (0.04), `Opacity.badgeFill` (0.12), `Opacity.hoverHighlight` (0.06), `Opacity.disabled` (0.5), `Opacity.scrim` (0.3)
- Shadow extensions: `.cardElevation()`, `.cardHoverElevation()`, `.popoverElevation()`, `.toastElevation()`
- Animation presets: `Anim.stateChange` (.snappy), `Anim.structural` (.spring), `Anim.entrance`, `Anim.micro`, `Anim.effective()` (respects reduce motion)
- `String.shortenedPath` — replaces home directory with ~

### Existing Components (use and extend, don't duplicate)

In `ManifoldApp/ManifoldApp/Components/`:
- `Badge.swift`, `StatusBadge.swift`, `AgentBadge.swift` — Pill badges
- `ColorIndicator.swift` — Status dots
- `AgentFocusControl.swift` (in Views/) — Claude | Codex | Compare segmented control

### Key Models

In `ManifoldApp/ManifoldApp/Models/`:
- `ManifoldStore.swift` — Main app state, accessed via `@Environment(ManifoldStore.self)`
- `AppRuntimeClient.swift` — XPC communication with runtime
- `AgentConnectionState.swift` — Agent connection status
- `PolicyModel.swift` — Agent access policies
- `FileNode.swift` — File tree representation
- `EmailAccountModel.swift` — Email account state
- `EmailSelectionModel.swift` — Email selection/navigation state
- `EmailSearchModel.swift` — Email search state
- `DomainPreset.swift` — Domain configuration
- `ManifoldTypes.swift` — Shared type definitions

### Existing View Files (these are what you're rebuilding)

- `Views/MainView.swift` — App shell with tab navigation
- `Views/OverviewView.swift` — Overview tab
- `Views/AgentPolicyCard.swift` — Agent cards on Overview
- `Views/FilesView.swift` — Files tab main content
- `Views/FilesSidebar.swift` — Files sidebar
- `Views/SourcesTableView.swift` — Files source table
- `Views/DomainsTableView.swift` — Domains table (being replaced by Rules system)
- `Views/Email/EmailView.swift` — Email tab shell (3-pane)
- `Views/Email/Sidebar/` — Email sidebar components
- `Views/Email/MessageList/` — Message list components
- `Views/Email/ReadingPane/` — Reading pane components
- `Views/ActivityView.swift` — Activity/audit log view

---

## TASK 1: Overview Tab Rebuild

**Files to modify**: `OverviewView.swift`, `AgentPolicyCard.swift`
**Prototype reference**: `OverviewTab` and `AgentCard` components in manifold-prototype.jsx

### What to build

The Overview tab is a two-column agent dashboard. No sidebar — the entire content area shows two agent cards side by side.

#### Agent Cards (rebuild AgentPolicyCard.swift)

Each card has:
1. **Left border**: 4pt in agent color (`Color.claudeBlue` or `Color.codexPurple`) using `.overlay(alignment: .leading)` with a `RoundedRectangle`
2. **Background**: Agent color at `Opacity.rowTint` (0.04)
3. **Shadow**: `.cardElevation()`
4. **Card header**: Agent name (Typ.heading) + status badge ("Active" green or "Paused" orange) using the existing `StatusBadge` component
5. **Sources section**: "Sources" label + count. List the actual source folder names with a colored dot (green = shared, gray = not shared). Example: "● web-app  ● api-server  ○ design-assets". Use the real data from ManifoldStore.
6. **Domains section**: "Domains" label + count. Show top domains with access dots, same pattern as sources.
7. **Activity section**: "Recent Activity" label. Show the 3 most recent audit entries for this agent — file accessed, email read, etc. Each entry: icon + description + relative timestamp. Use `TimeLabel` component.
8. **Per-agent control**: "Pause Access" / "Resume Access" text button at the bottom of each card. NOT a toggle. Text changes based on state. Uses `Anim.stateChange` for transition.

#### Card Footer (shared across both cards)

Below both cards, spanning full width:
- "Start Tracked Work Block" button — prominent style when no work block active
- When a work block IS active: live status bar showing duration + change count + "End Work Block" button
- Use existing `WorkBlockBannerView` patterns but adapt to this footer position

#### Layout

```
┌─────────────────────────────────────────────────┐
│ [Toolbar: status dot + "Claude + Codex active"] │
├───────────────────────┬─────────────────────────┤
│   Claude Card         │    Codex Card           │
│   ┌─ Sources (3)      │    ┌─ Sources (2)       │
│   │  ● web-app        │    │  ● web-app          │
│   │  ● api-server     │    │  ○ api-server       │
│   │  ○ design-assets  │    │  ● docs             │
│   ├─ Domains (5)      │    ├─ Domains (2)       │
│   │  ● github.com     │    │  ● figma.com        │
│   │  ● linear.app     │    │  ○ notion.so        │
│   ├─ Recent Activity  │    ├─ Recent Activity   │
│   │  Read auth.ts 2m  │    │  Read theme.css 5m  │
│   │  Opened PR #42 1h │    │  Indexed palette 2h │
│   ├─────────────────  │    ├─────────────────   │
│   │ [Pause Access]    │    │ [Resume Access]    │
│   └───────────────────│    └─────────────────────│
├─────────────────────────────────────────────────┤
│         [Start Tracked Work Block]              │
└─────────────────────────────────────────────────┘
```

Use `HStack(spacing: 16)` for the two cards. Each card is a `VStack` inside a `RoundedRectangle` with `.cardElevation()`. Cards should use `.frame(maxWidth: .infinity)` to split evenly.

### Key SwiftUI patterns

- Agent color left border: `.overlay(alignment: .leading) { Rectangle().fill(agentColor).frame(width: 4) }`
- Background tint: `.background(agentColor.opacity(Opacity.rowTint))`
- Status subtitle in toolbar: derive from `store.agentConnectionState` — show "Claude + Codex active" or "Claude active · Codex paused" etc.
- Remove the global toggle from toolbar (fix 1.5). Per-agent controls are now on the cards.
- Remove the "Agent" label from the segmented control (fix 1.7). Add `.accessibilityLabel("Agent focus")`.

---

## TASK 2: Files Tab Rebuild

**Files to modify**: `FilesView.swift`, `FilesSidebar.swift`, `SourcesTableView.swift`
**Prototype reference**: `FilesTab` component in manifold-prototype.jsx

### What to build

The Files tab has a sidebar + main content area. The sidebar now has a **Dashboard** as the default view.

#### Files Sidebar (FilesSidebar.swift)

Structure:
```
OVERVIEW
  [Activity icon] Dashboard        ← NEW: default selection

BROWSE
  [FileText icon] All Files  (count)
  [Folder icon]   All Sources

SOURCES (5)
  [Folder icon] web-app       247
  [Folder icon] api-server     89
  [Folder icon] docs           34
  [Folder icon] design-assets 156
  [Folder icon] IBM_Plex_Sans  ...
  [+ icon] Add Folder…

VERSIONS
  [Clock icon] Recently Modified
  [Eye icon]   AI-Touched Files
```

Use `.headerProminence(.increased)` for section headers ("Overview", "Browse", "Sources", "Versions"). Show item counts in `Typ.numericCaption`. Source folder icons colored with agent color if shared, `.secondary` if not.

#### Files Dashboard (NEW VIEW — create FilesDashboardView.swift)

This is shown when "Dashboard" is selected in the sidebar. It mirrors the email rules dashboard pattern.

Contents:
1. **Header**: "Files Dashboard" (Typ.sectionTitle) + summary line: "5 sources · 23 files tracked · 4 sources shared with agents"
2. **Per-agent stats cards** (same card pattern as Email Rules dashboard):
   - Claude card: left border in ClaudeBlue, shows files shared count, not-shared count, percentage bar
   - Codex card: left border in CodexPurple, same pattern
   - Use `HStack(spacing: 12)` for the two cards
3. **Sources panel + File Types panel** side by side (`HStack`):
   - Sources: bordered list showing each source folder with green dot (shared) or gray dot (not shared), file count, clickable to drill in
   - File Types: bordered list showing top file extensions with colored pip (from `fileIcon` colors), count, mini bar chart
4. **Recently Modified table**: 5 most recently modified files. Columns: File (name with colored extension pip), Source, Modified, Shared (agent dot). Clickable source to navigate.
5. **Footer callout**: "X files not shared with any agent" + "Browse all files →" link

#### Source Table (when "All Sources" selected)

Rebuild `SourcesTableView.swift` using native SwiftUI `Table`:

```swift
Table(sources, selection: $selectedSource) {
    TableColumn("Name") { source in
        Label(source.name, systemImage: "folder")
    }
    TableColumn("Path") { source in
        Text(source.path.shortenedPath)
            .font(Typ.mono)
    }
    TableColumn("Files", value: \.itemCount) { source in
        // Lazy count with "…" placeholder, animate with .contentTransition(.numericText())
    }
    TableColumn(agentName) { source in
        // Agent-colored checkbox (fix 2.3)
        // In Compare mode: split into two columns
    }
}
```

- Row click navigates into that source (shows files)
- Remove all placeholder/empty rows below data (fix 2.1)
- Summary footer below table: "5 sources · 247 files total · Click a source to browse files"

#### File Table (when a source or "All Files" selected)

Also use SwiftUI `Table`:

```swift
Table(files) {
    TableColumn("Name") { file in
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(file.extensionColor)
                .frame(width: 4, height: 14)
            Text(file.name)
        }
    }
    TableColumn("Path") { ... }  // Typ.mono, .truncationMode(.middle)
    // "Source" column only in All Files view
    TableColumn("Size") { ... }  // right-aligned, Typ.numericCaption
    TableColumn("Modified") { ... }  // right-aligned, Typ.numericCaption
    TableColumn("Shared") { ... }  // agent color dot
}
```

- Agent-colored row tinting at `Opacity.rowTint` for shared files (fix 3.6 pattern)
- Search bar in toolbar filters files
- Footer: file count + "shared with agents" count

---

## TASK 3: Emails — Rules Tab (NEW — replaces Domains)

**Files to create**: `Views/Email/Rules/EmailRulesView.swift`, `Views/Email/Rules/RulesDashboardView.swift`, `Views/Email/Rules/ShieldDetailView.swift`, `Views/Email/Rules/DomainRulesView.swift`, `Views/Email/Rules/ContactRulesView.swift`, `Views/Email/Rules/KeywordRulesView.swift`, `Views/Email/Rules/DefaultPolicyView.swift`
**Files to modify**: `Views/Email/EmailView.swift` (change sub-nav from Domains/Messages to Rules/Messages)
**Files to retire**: `Views/DomainsTableView.swift` (functionality absorbed into DomainRulesView)
**Prototype reference**: `EmailsRulesTab` component in manifold-prototype.jsx
**Spec reference**: `design/EMAIL-CONTROLS-SPEC.md`

### Data Models Needed

Create or extend models for the rules engine:

```swift
// In Models/ — new file: EmailRulesModel.swift

struct EmailShield: Identifiable {
    let id: String           // "security", "financial", "medical", "legal", "personal"
    let name: String
    let description: String
    var isEnabled: Bool
    let domains: [String]     // monitored domains
    let patterns: [String]    // subject/body keyword patterns
    var blockedCount: Int
    var recentMatches: [ShieldMatch]
}

struct ShieldMatch: Identifiable {
    let id: UUID
    let subject: String
    let from: String
    let date: Date
    let agentBlocked: TargetApp
}

struct DomainRule: Identifiable {
    let id: UUID
    let domain: String
    var action: RuleAction     // .allow or .block
    let category: String       // "Work", "Automated", "Personal", "Financial"
    var agents: [TargetApp]
    let emailCount: Int
    var shieldOverlap: String? // shield name if also covered by a shield
}

struct ContactRule: Identifiable {
    let id: UUID
    let name: String
    let email: String
    var action: RuleAction
    let overridesDescription: String
    var agents: [TargetApp]
}

struct KeywordRule: Identifiable {
    let id: UUID
    let pattern: String
    let matchLocation: KeywordMatchLocation  // .subject, .subjectAndBody, .anywhere
    var action: RuleAction
    var matchedCount: Int
    var agents: [TargetApp]
    var isRegex: Bool
}

enum RuleAction: String, CaseIterable {
    case allow, block
}

enum KeywordMatchLocation: String, CaseIterable {
    case subject = "Subject"
    case subjectAndBody = "Subject + Body"
    case anywhere = "Anywhere"
}

enum AgentDefaultPolicy: String, CaseIterable {
    case allowUnlessBlocked = "Allow unless blocked"
    case blockUnlessAllowed = "Block unless allowed"
}
```

### EmailRulesView.swift (the main container)

This is a `NavigationSplitView` with sidebar + detail:

#### Rules Sidebar

```
OVERVIEW
  [Activity icon] Dashboard

SHIELDS (3 active)
  [Shield icon green] Security & 2FA    23
  [Shield icon green] Financial          14
  [Shield icon green] Medical             3
  [Shield icon gray]  Legal             off
  [Shield icon gray]  Personal          off

RULES
  [Globe icon]  Domains    12
  [Mail icon]   Contacts    3
  [Search icon] Keywords    2

POLICY
  [Settings icon] Defaults
```

- Shield sidebar items show green Shield icon when enabled, gray when disabled
- Trailing text: blocked count when active, "off" when disabled
- Bottom of sidebar: small text "Priority: Contact → Keyword → Domain → Shield → Default"
- Use `List(selection:)` for sidebar navigation

#### Rules Dashboard (RulesDashboardView.swift)

When Dashboard is selected:

1. **Header**: "Protection Dashboard" + summary: "3 shields active · 12 domain rules · 3 contact overrides · 2 keyword patterns"
2. **Per-agent stats cards** (same card pattern as Files dashboard):
   - Claude: accessible count, blocked count, percentage bar in ClaudeBlue
   - Codex: accessible count, blocked count, percentage bar in CodexPurple
3. **Active Shields summary**: Horizontal row of shield chips. Each chip: Shield icon + name + "· X blocked". Green border/background when active, gray when inactive. Chips are clickable to navigate to shield detail.
4. **Recent Shield Activity table**: Table showing last 6 emails blocked by any shield. Columns: Subject, From, Shield (which shield caught it), Date.

#### Shield Detail (ShieldDetailView.swift)

When a shield is selected:

1. **Header**: Shield icon + name + Active/Disabled toggle button (green when active, gray when disabled)
2. **Description**: The shield's description paragraph
3. **Agent Access section**: Shows per-agent status. Each agent row: colored dot + name + "Blocked"/"No shield" badge
4. **Detection Patterns section** (collapsible):
   - "Monitored domains" — list of domain pills (gray background, monospace)
   - "Subject & body patterns" — list of keyword pills (orange-tinted background, monospace, quoted)
5. **Recent Matches table**: Emails caught by this shield. Columns: Subject, From, Date
6. **Footer CTA**: "Shield missing something? Add a keyword rule →" — links to Keywords view

#### Domain Rules (DomainRulesView.swift)

Rebuilt from `DomainsTableView.swift`:

1. **Toolbar**: "Domain Rules" title + rule count + "Add Domain" button
2. **SwiftUI Table**:
   - Column "Domain": `@domain.com` with typography weight by email volume (fix 3.1). Show Shield icon if `shieldOverlap` exists.
   - Column "Category": Work/Automated/Personal/Financial in caption text
   - Column "Emails": right-aligned count
   - Column "Rule": Allow/Block pill badge (green/red)
   - Column "Agents": agent dots (blue for Claude, purple for Codex) or "All agents" text
3. Row background: green tint (0.03 opacity) for allow rows, no tint for block

#### Contact Rules (ContactRulesView.swift)

1. **Toolbar**: "Contact Rules" title + count + "Add Contact" button
2. **Explanatory text**: "Contact rules override domain rules and shields for specific senders. Use them when you need an exception."
3. **Table**: Name, Email (mono), Rule (Allow/Block badge), Overrides (description), Agents (dots)

#### Keyword Rules (KeywordRulesView.swift)

1. **Toolbar**: "Keyword Rules" title + count + "Add Pattern" button
2. **Explanatory text**: "Keyword rules catch emails containing specific text patterns, regardless of sender or domain."
3. **Table**: Pattern (monospace, quoted), Match In, Rule (badge), Matched (count), Agents. Show "REGEX" badge on regex patterns.

#### Default Policy (DefaultPolicyView.swift)

1. **Header**: "Default Policy" + explanation paragraph
2. **Per-agent cards**: Each agent gets a card with left color border. Inside: segmented control with two options:
   - "Allow unless blocked" — "Agent sees all emails except those caught by shields and rules"
   - "Block unless allowed" — "Agent sees nothing unless a rule explicitly allows it"
3. **Warning banner**: If any agent is set to "Block unless allowed", show orange warning: "⚠ [Agent] won't see any emails unless you add allow rules above. This is high-security mode."
4. **Footer**: Explanation of evaluation order: "When an email arrives, Manifold checks Contact rules first (most specific), then Keywords, then Domains, then Shields. If none match, this default applies."

### Wiring into EmailView.swift

Change the sub-nav from `["Domains", "Messages"]` to `["Rules", "Messages"]`. When "Rules" is selected, show `EmailRulesView()`. When "Messages" is selected, show the existing message list view.

---

## TASK 4: Emails — Messages Tab FULL REBUILD (Synology Active Backup style)

**Files to rebuild**: `Views/Email/MessageList/EmailMessageList.swift`, `Views/Email/MessageList/EmailMessageRow.swift`, `Views/Email/MessageList/MessageFilterBar.swift`, `Views/Email/MessageList/SelectionActionBar.swift`, `Views/Email/Sidebar/EmailSidebar.swift`, `Views/Email/ReadingPane/EmailReadingPane.swift`
**Prototype reference**: `EmailsMessagesTab` component in manifold-prototype.jsx — read the ENTIRE component carefully
**Design intent reference**: Amar's original direction: "for the emails please search synology active backup — for the mailbox view I don't want apple mail style but more the synology view — they can click onto each mail to see a preview — this is not their mail client — they are not likely to want to read tons of emails but focus on which emails are selected and be able to search and bulk select them"

### CRITICAL DESIGN INTENT

**This is NOT a mail client.** This is a governance browser. The user is here to see which emails agents have access to, search for specific emails, select emails in bulk, and manage sharing — NOT to read their mail. Think Synology Active Backup for email, not Apple Mail.

The key differences from a mail client:
1. **No three-pane layout.** There is no persistent reading pane. Instead: sidebar + table. When the user clicks a row, a preview panel expands INLINE below that row (like Synology's click-to-expand). Not a separate column.
2. **Checkbox column.** Every row has a checkbox for multi-select. The header row has a select-all checkbox.
3. **Bulk action bar.** When items are selected, a bulk action bar appears in the toolbar: "X selected · [Share with Agent] [Export]"
4. **Agent-centric smart filters.** The sidebar has "Agent Access" section with: "Shared with Claude", "Shared with Codex", "Not Shared". These are the PRIMARY navigation — not traditional IMAP folders.
5. **Table columns focus on governance data.** Columns: Checkbox, From, Subject, Domain, Date, Attachment icon, Shared (agent dot). Domain is a visible column because governance is domain-scoped.

### Layout Structure

```
┌──────────────────────────────────────────────────────────────────┐
│ [Rules | Messages]  sub-nav                                      │
├──────────┬───────────────────────────────────────────────────────┤
│ SIDEBAR  │  TOOLBAR: [Search...............] [3 selected · Share │
│          │           with Claude · Export]    [Claude|Codex|Cmp] │
│ FAVORITES│  ─────────────────────────────────────────────────────│
│  All Mail│  ☐  From        Subject              Domain   Date  📎│
│  INBOX   │  ─────────────────────────────────────────────────────│
│          │  ☐  GitHub      PR #42 merged         github  10:23  │
│ AGENT    │  ☑  Linear      MAN-234 In Review     linear  9:45   │
│ ACCESS   │  ☐  Apple Dev   App approved           apple  Apr 10 📎│
│  ● Shared│  ▼─────────────────────────────────────────────────── │
│    Claude│  │ Preview: Your app has been approved...            │ │
│  ● Shared│  │ From: no_reply@email.apple.com · To: amar@...    │ │
│    Codex │  │ [Shared with Claude]  [Open]  [✕]                │ │
│  ○ Not   │  │ Dear Developer, Manifold version 1.0...          │ │
│    Shared│  └──────────────────────────────────────────────────── │
│          │  ☐  Stripe      March invoice          stripe  Apr 1 📎│
│ ACCOUNT  │  ☐  Notion      Weekly digest          notion  Mar 27 │
│ amar@... │  ─────────────────────────────────────────────────────│
│  Sent    │  8 messages · 1 selected · Last synced: 2 min ago    │
│  Drafts  │                                                       │
│  Trash   │                                                       │
│  Archive │                                                       │
│  [+]     │                                                       │
└──────────┴───────────────────────────────────────────────────────┘
```

### Sidebar (EmailSidebar.swift rebuild)

Use `DisclosureGroup` sections (fix 4.5) with `.headerProminence(.increased)`:

**Section 1: Favorites** (collapsible, default expanded)
- All Mail — with total count
- INBOX — with unread count

**Section 2: Agent Access** (collapsible, default expanded) — THIS IS THE KEY SECTION
- "Shared with Claude" — blue StatusDot + count
- "Shared with Codex" — purple StatusDot + count
- "Not Shared" — gray StatusDot + count

These are computed smart filters. Selecting one filters the table to show only emails matching that sharing status. This is the primary way users navigate the Messages view.

**Section 3: Account (amar.gandhi@me.com)** (collapsible, default expanded)
- Sent, Drafts, Trash, Archive — standard IMAP folders with folder icons

**Footer**: "+" icon button with tooltip "Add Email Account…" (fix 4.6)

Column width: `.navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)` (fix 4.1)

### Message Table (EmailMessageList.swift rebuild)

**DO NOT use a three-pane NavigationSplitView.** Use a two-pane layout: sidebar + content. The content is a full-width table with inline preview expansion.

Use SwiftUI `Table` with these columns:

```swift
Table(messages, selection: $selectedMessageIDs) {
    TableColumn("") { message in   // Checkbox column, 36pt wide
        CheckboxToggle(isOn: selectedIDs.contains(message.id), agentColor: agentColor)
    }.width(36)
    
    TableColumn("From") { message in
        Text(message.senderName)
            .font(Typ.body).fontWeight(.medium)
            .lineLimit(1)
    }
    
    TableColumn("Subject") { message in
        Text(message.subject)
            .font(Typ.body)
            .lineLimit(1)
    }
    
    TableColumn("Domain") { message in
        Text("@\(message.domain)")
            .font(Typ.mono)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }.width(100)
    
    TableColumn("Date") { message in
        Text(message.relativeDate)
            .font(Typ.numericCaption)
            .foregroundStyle(.secondary)
    }.width(80)
    
    TableColumn("") { message in   // Attachment icon, 60pt
        if message.hasAttachment {
            Image(systemName: "paperclip")
                .foregroundStyle(.tertiary)
        }
    }.width(60)
    
    TableColumn("Shared") { message in   // Agent dot, 70pt
        if let agent = message.sharedWith {
            HStack(spacing: 4) {
                Circle().fill(Color.agent(agent)).frame(width: 8, height: 8)
                Text(agent.displayName)
                    .font(Typ.caption)
                    .foregroundStyle(Color.agent(agent))
            }
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }.width(70)
}
```

**Row behavior:**
- Click a row → toggle inline preview panel below that row (NOT a separate reading pane)
- Row background: agent tint (`Opacity.rowTint`) if email is shared with focused agent
- Previewing row: blue tint (`Color.accentColor.opacity(0.06)`)
- Agent-colored checkboxes when selected

**Inline Preview Panel (click-to-expand below row):**

When a message row is clicked, a preview panel expands below that row (animated with `Anim.structural`). The panel contains:

1. **Header row**: Subject (Typ.heading) + metadata line ("From: address · To: address · date")
2. **Action buttons** (right side of header): 
   - If shared: agent badge showing "Shared with Claude/Codex"
   - If NOT shared: "Share with [Agent]" button in agent color
   - "Open" button — bordered, neutral style, Mail icon + "Open" text. Action: `NSWorkspace.shared.open(emlFileURL)` to open in default mail app
   - "✕" close button
3. **Body preview**: message body text in `Typ.body`, `.foregroundStyle(.secondary)`, max height ~160pt with scroll, `whiteSpace: pre-wrap` equivalent
4. **Attachment bar** (if has attachments): paperclip icon + "1 attachment" label in a subtle gray chip

The preview background is `Color.accentColor.opacity(0.03)` with a bottom border.

### Toolbar (MessageFilterBar.swift rebuild)

The toolbar is a single bar containing:

1. **Search field** (left): `.searchable` or custom search field. Placeholder: "Search by sender, subject, domain…". Searches across from, fromName, subject, and domain fields. Clear button (✕) when text present.

2. **Bulk action bar** (center, only visible when items selected):
   - "X selected" count label
   - "Share with [Agent]" button — agent-colored border and tint
   - "Export" button — neutral bordered style
   
3. **Agent focus control** (right): The existing `AgentFocusControl` (Claude | Codex | Compare)

### Footer

Single-line footer at bottom of message table:
- Left: "X messages" (with proper pluralization) + "· Y selected" if selection active
- Right: "Last synced: 2 min ago" timestamp

### Empty States

Two distinct empty states (fix 4.2):

**Search empty**: When search text returns no results:
- Mail icon (32pt, .secondary)
- "No results for '[search text]'"
- "Try a different search term or clear filters."

**Folder empty**: When a folder/filter has no messages:
- Mail icon (32pt, .secondary)  
- "No messages"
- "This mailbox is empty."

Use `ContentUnavailableView` for both.

### What to Remove

- **Remove the persistent reading pane column.** There is no third column. The preview is INLINE below the clicked row.
- **Remove the traditional Mail.app three-pane layout** from EmailView.swift. The Messages view is now: sidebar + full-width table with inline preview.
- **Keep the reading pane components** (`EmailReadingPane.swift`, `EmailHeaderView.swift`, etc.) but repurpose them for the inline preview panel, or create a new `InlineMessagePreview.swift` component that reuses the rendering logic.

---

## TASK 5: App Shell / Toolbar Updates

**Files to modify**: `Views/MainView.swift`, `AppToolbar` or toolbar content

### Truthful Status Subtitle (fix 1.3)

In the toolbar, replace any legacy "X sessions" text with a live status derived from agent connection state:
- Both active: "Claude + Codex active"
- One active, one paused: "Claude active · Codex paused"
- Both paused: "All agents paused"
- Connecting: "Connecting…"
- Disconnected: "Disconnected"

### Persistent Status Dot (fix X.4)

Add a small filled circle (10pt) in the toolbar:
- Green (`Color.statusActive`) when both agents connected
- Orange (`Color.statusWarning`) when partially connected/paused
- Red (`Color.statusDanger`) when disconnected

Paired with text label in `Typ.caption`: "Connected" / "1 agent paused" / "Disconnected"

### Remove Global Toggle (fix 1.5)

Remove any global pause/resume toggle from the toolbar. Per-agent controls are now on the Overview cards.

### Remove "Agent" Label (fix 1.7)

The `AgentFocusControl` (Claude | Codex | Compare segmented control) should NOT have an external "Agent" label. The segments are self-describing. Add `.accessibilityLabel("Agent focus")`.

---

## Cross-Cutting Requirements

### Use Native SwiftUI Table Everywhere (fix 2.7)

Every data table (sources, files, domains, contacts, keywords, messages, recent activity) should use SwiftUI `Table` component. This gives you: sortable columns, proper column resizing, row hover, selection, keyboard navigation, accessibility, scroll edge effects, and Liquid Glass integration — all for free.

### Agent-Colored Row Tinting (fixes 3.6, consistent across app)

Any table row showing agent access should tint the row background with the focused agent's color at `Opacity.rowTint` (0.04). Switching agents animates the tint with `Anim.stateChange`.

### Typography Weight by Volume (fix 3.1)

In domain/file tables with counts, scale visual weight by count:
- 100+ items: `Typ.body` with `.fontWeight(.medium)`
- 10-99 items: `Typ.body` with `.foregroundStyle(.secondary)`
- <10 items: `Typ.caption`

### Empty States (fix 4.2, DESIGN-STANDARDS §7)

Every view must have a proper empty state using `ContentUnavailableView`:
- Distinguish between: not configured, syncing/loading, and truly empty
- Include a single clear action button
- Never hedge ("empty or still syncing")

### Proper Pluralization (fix 3.4)

Use SwiftUI's automatic grammar agreement everywhere:
```swift
Text("^[\(count) email](inflect: true)")
Text("^[\(count) file](inflect: true)")
Text("^[\(count) source](inflect: true)")
```

### NavigationSplitView Column Widths (fix 4.7)

All NavigationSplitViews should set explicit column widths:
```swift
.navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
```

### Animations

- Every `withAnimation` uses named presets from `Anim` enum
- Every animation checks `accessibilityReduceMotion` via `Anim.effective()`
- Numeric count changes use `.contentTransition(.numericText())`

---

## Verification

After implementing each task, run:

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache xcodebuild -project Manifold.xcodeproj -scheme Manifold -configuration Debug -derivedDataPath /tmp/manifold-derived-data build CODE_SIGNING_ALLOWED=NO
```

This must succeed with zero errors. Warnings are acceptable during development but should be addressed before completion.

For model/runtime changes, also run:
```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache swift build
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache swift test
```

---

## Implementation Order

1. **Task 5 first** (App Shell / Toolbar) — small scope, affects every tab, establishes the truthful status pattern
2. **Task 1** (Overview Tab) — the landing page, establishes the agent card pattern used elsewhere
3. **Task 2** (Files Tab) — introduces the Dashboard pattern and native Table usage
4. **Task 3** (Email Rules) — the largest task, creates new views and models. Do sub-tasks in order: models → EmailRulesView shell → Dashboard → Shield Detail → Domain/Contact/Keyword → Default Policy
5. **Task 4** (Messages Open button) — smallest task, finish last

Run `xcodebuild` after each task completes. Don't move to the next task until the current one builds.

---

## What NOT to Do

- Don't create new design token files — `DesignTokens.swift` already has everything
- Don't break the XPC boundary — new features go through `AppRuntimeClient`, not into runtime internals
- Don't push expensive work onto `@MainActor` — file enumeration, email scanning, shield matching should be async
- Don't fake connection state — derive UI from real runtime responses
- Don't add Liquid Glass manually — use NavigationSplitView, Table, and standard toolbar APIs; the framework applies glass automatically
- Don't use `.easeInOut` or custom spring definitions — use the `Anim` presets
- Don't remove existing functionality while rebuilding — the email message list, reading pane, sidebar folders, etc. all stay. You're adding the Rules system alongside Messages, not replacing Messages
