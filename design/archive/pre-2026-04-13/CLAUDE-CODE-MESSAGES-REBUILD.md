# Emails Messages View — Full Rebuild to Synology Active Backup Style

> **Read before coding**: `design/manifold-prototype.jsx` — find the `EmailsMessagesTab` component and read every line. That is the visual source of truth.

## Design Intent

Amar's original direction: "for the emails please search synology active backup — for the mailbox view I don't want apple mail style but more the synology view — they can click onto each mail to see a preview — this is not their mail client — they are not likely to want to read tons of emails but focus on which emails are selected and be able to search and bulk select them"

**This is NOT a mail client. This is a governance browser.** The user is here to see which emails agents have access to, search for specific emails, select emails in bulk, and manage sharing — NOT to read their mail. The mental model is Synology Active Backup's email archive browser, not Apple Mail.

## The Five Key Differences from Apple Mail

1. **No three-pane layout.** There is no persistent reading pane column. The layout is: sidebar + full-width table. When the user clicks a row, a preview panel expands INLINE below that row (like Synology's click-to-expand pattern). Clicking again collapses it. This is NOT a NavigationSplitView detail column.

2. **Checkbox column.** Every row has a checkbox for multi-select. The table header has a select-all checkbox. Checkboxes are colored with the focused agent's color when selected.

3. **Bulk action bar.** When items are selected, a bulk action bar appears in the toolbar: "[X selected] [Share with Agent] [Export]". This enables governance operations on multiple emails at once.

4. **Agent-centric smart filters in sidebar.** The sidebar's MOST IMPORTANT section is "Agent Access" with: "Shared with Claude" (blue dot), "Shared with Codex" (purple dot), "Not Shared" (gray dot). These computed smart filters are the primary navigation — not IMAP folders. Traditional folders (Sent, Drafts, Trash) are secondary.

5. **Domain column in table.** The table has a "Domain" column showing `@domain.com` because governance is domain-scoped. You need to see at a glance which domain each email is from.

## Files to Modify/Create

**Rebuild these:**
- `Views/Email/EmailView.swift` — Change from three-pane NavigationSplitView to two-pane (sidebar + content)
- `Views/Email/Sidebar/EmailSidebar.swift` — New sidebar structure with Agent Access smart filters
- `Views/Email/MessageList/EmailMessageList.swift` — Full-width table with checkboxes and inline preview
- `Views/Email/MessageList/EmailMessageRow.swift` — Row with governance columns
- `Views/Email/MessageList/MessageFilterBar.swift` — Search + bulk actions + agent focus toolbar
- `Views/Email/MessageList/SelectionActionBar.swift` — Bulk action buttons

**Create new:**
- `Views/Email/MessageList/InlineMessagePreview.swift` — The click-to-expand preview below a row

**Can retire/repurpose:**
- `Views/Email/ReadingPane/EmailReadingPane.swift` — No longer a standalone column. Reuse rendering logic in InlineMessagePreview.

## Existing Design Tokens (already in `Components/DesignTokens.swift` — use these)

- `Color.claudeBlue`, `Color.codexPurple`, `Color.agent(_ type:)`
- `Typ.body` (.callout), `Typ.heading` (.headline), `Typ.caption`, `Typ.mono`, `Typ.numericCaption`
- `Opacity.rowTint` (0.04), `Opacity.badgeFill` (0.12)
- `Anim.stateChange` (.snappy), `Anim.structural` (.spring)
- Shadow/animation extensions all exist

## Existing Components (use these, don't recreate)

- `AgentFocusControl` — Claude | Codex | Compare segmented control (in Views/)
- `Badge`, `StatusBadge`, `AgentBadge` — Pill badges (in Components/)
- `ColorIndicator` — Status dots (in Components/)
- `TimeLabel` — Relative time display (in Components/)

## Existing Models (wire into these)

- `ManifoldStore` — Main app state via `@Environment(ManifoldStore.self)`
- `EmailSelectionModel` — Selection/navigation state
- `EmailSearchModel` — Search state
- `EmailAccountModel` — Account data
- `EmailMessageRecord` — Individual email record (check ManifoldTypes.swift for definition)

---

## Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ [Rules | Messages]  sub-nav                                      │
├──────────┬───────────────────────────────────────────────────────┤
│ SIDEBAR  │  TOOLBAR: [Search...............] [3 selected · Share │
│ 220pt    │           with Claude · Export]    [Claude|Codex|Cmp] │
│          │                                                       │
│ FAVORITES│  TABLE HEADER                                         │
│  All Mail│  ☐  From        Subject              Domain   Date  📎 Shared│
│  INBOX   │  ──────────────────────────────────────────────────── │
│          │  ☐  GitHub      PR #42 merged         github  10:23   ●│
│ AGENT    │  ☑  Linear      MAN-234 In Review     linear  9:45    ●│
│ ACCESS   │  ☐  Apple Dev   App approved           apple  Apr 10 📎  │
│  ● Claude│  ▼──────────────────────────────────────────────────  │
│  ● Codex │  │ Your app has been approved                       │ │
│  ○ Not   │  │ From: no_reply@email.apple.com · To: amar@me.com│ │
│  Shared  │  │                                                  │ │
│          │  │ Dear Developer, Manifold version 1.0 (build 42)  │ │
│ ACCOUNT  │  │ has been approved for distribution...             │ │
│ amar@... │  │                                                  │ │
│  Sent    │  │ 📎 1 attachment                                   │ │
│  Drafts  │  │                                                  │ │
│  Trash   │  │   [Shared with Claude]  [Open]  [✕]             │ │
│  Archive │  └──────────────────────────────────────────────────  │
│          │  ☐  Stripe      March invoice          stripe  Apr 1 📎│
│  [+]     │  ☐  Notion      Weekly digest          notion  Mar 27 │
│          │  FOOTER: 8 messages · 1 selected · Last synced 2m ago│
└──────────┴───────────────────────────────────────────────────────┘
```

---

## Sidebar (EmailSidebar.swift)

Use `List(selection:)` with `DisclosureGroup` sections. `.headerProminence(.increased)` for section headers.

### Section 1: Favorites (default expanded)
```swift
DisclosureGroup("Favorites", isExpanded: $favoritesExpanded) {
    SidebarRow(icon: "envelope", label: "All Mail", count: totalEmailCount)
    SidebarRow(icon: "tray", label: "INBOX", count: inboxCount)
}
.headerProminence(.increased)
```

### Section 2: Agent Access (default expanded) — THE PRIMARY NAVIGATION
```swift
DisclosureGroup("Agent Access", isExpanded: $agentAccessExpanded) {
    SidebarRow(dot: Color.claudeBlue, label: "Shared with Claude", count: sharedWithClaudeCount)
    SidebarRow(dot: Color.codexPurple, label: "Shared with Codex", count: sharedWithCodexCount)
    SidebarRow(dot: Color(.tertiaryLabelColor), label: "Not Shared", count: notSharedCount)
}
.headerProminence(.increased)
```

These are computed filters. Selecting "Shared with Claude" filters the table to emails where `sharedWith == .claude`.

### Section 3: Account folders (default expanded)
```swift
DisclosureGroup(store.emailAccounts.first?.address ?? "Account", isExpanded: $accountExpanded) {
    SidebarRow(icon: "paperplane", label: "Sent")
    SidebarRow(icon: "doc", label: "Drafts")
    SidebarRow(icon: "trash", label: "Trash")
    SidebarRow(icon: "archivebox", label: "Archive")
}
.headerProminence(.increased)
```

### Footer
```swift
// Bottom of sidebar — "+" button for adding accounts
Button(action: { showAddAccount = true }) {
    Image(systemName: "plus")
}
.help("Add Email Account…")
```

### Column width
```swift
.navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
```

---

## Message Table (EmailMessageList.swift)

**Use SwiftUI `Table` — NOT a List with HStacks.** Table gives you: sortable columns, proper column resizing, keyboard navigation, scroll edge effects, Liquid Glass header — all for free.

### Column definitions

```swift
Table(filteredMessages, selection: $selectedMessageIDs) {
    // Checkbox column
    TableColumn("") { message in
        Button(action: { toggleSelection(message.id) }) {
            Image(systemName: selectedIDs.contains(message.id) 
                ? "checkmark.square.fill" : "square")
                .foregroundStyle(selectedIDs.contains(message.id) 
                    ? Color.agent(focusedAgent) : .tertiary)
        }
        .buttonStyle(.plain)
    }
    .width(36)
    
    // From
    TableColumn("From") { message in
        Text(message.senderDisplayName)
            .font(Typ.body).fontWeight(.medium)
            .lineLimit(1)
    }
    
    // Subject
    TableColumn("Subject") { message in
        Text(message.subject)
            .font(Typ.body)
            .lineLimit(1)
    }
    
    // Domain — visible because governance is domain-scoped
    TableColumn("Domain") { message in
        Text("@\(message.senderDomain)")
            .font(Typ.mono)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
    .width(100)
    
    // Date
    TableColumn("Date") { message in
        TimeLabel(date: message.date)
            .font(Typ.numericCaption)
    }
    .width(80)
    
    // Attachment indicator
    TableColumn("") { message in
        if message.hasAttachments {
            Image(systemName: "paperclip")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    .width(40)
    
    // Shared with agent — the governance column
    TableColumn("Shared") { message in
        if let agent = message.sharedWithAgent {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.agent(agent))
                    .frame(width: 8, height: 8)
                Text(agent.displayName)
                    .font(Typ.caption)
                    .foregroundStyle(Color.agent(agent))
            }
        } else {
            Text("—")
                .font(Typ.caption)
                .foregroundStyle(.tertiary)
        }
    }
    .width(70)
}
```

### Row behavior

- **Click a row** → sets `previewingMessageID` to that row's ID. If already previewing that row, sets to nil (collapse).
- **Row background**: 
  - If previewing: `Color.accentColor.opacity(0.06)`  
  - If shared with focused agent: agent color at `Opacity.rowTint` (0.04)
  - Otherwise: default
- **Checkbox click** → toggles selection independently of preview (use `.onTapGesture` on the checkbox, stop propagation)
- **Select-all checkbox** in the header toggles all visible (filtered) messages

### Inline Preview (InlineMessagePreview.swift)

When `previewingMessageID == message.id`, render a preview panel BELOW that table row. This is the Synology pattern — not a separate column.

```swift
struct InlineMessagePreview: View {
    let message: EmailMessageRecord
    let focusedAgent: TargetApp
    let onClose: () -> Void
    let onOpen: () -> Void        // NSWorkspace.shared.open(emlURL)
    let onShare: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: subject + action buttons
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.subject)
                        .font(Typ.heading)
                    Text("From: \(message.senderAddress) · To: \(message.recipientAddress) · \(message.formattedDate)")
                        .font(Typ.caption)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    // Share status or share button
                    if let agent = message.sharedWithAgent {
                        AgentBadge(agent: agent, label: "Shared with \(agent.displayName)")
                    } else {
                        Button("Share with \(focusedAgent.displayName)") { onShare() }
                            .buttonStyle(.bordered)
                            .tint(Color.agent(focusedAgent))
                    }
                    
                    // Open in mail app
                    Button(action: onOpen) {
                        Label("Open", systemImage: "envelope")
                    }
                    .buttonStyle(.bordered)
                    .help("Open in default email app")
                    
                    // Close
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            
            // Body preview
            ScrollView {
                Text(message.bodyPreview)
                    .font(Typ.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            
            // Attachment bar (if any)
            if message.hasAttachments {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.tertiary)
                    Text("^[\(message.attachmentCount) attachment](inflect: true)")
                        .font(Typ.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.init(top: 16, leading: 48, bottom: 16, trailing: 20))
        .background(Color.accentColor.opacity(0.03))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
```

The Open button calls `NSWorkspace.shared.open(message.emlFileURL)` to open the .eml in the user's default mail app.

---

## Toolbar (MessageFilterBar.swift)

Single toolbar bar with three zones:

### Left: Search
```swift
// Use .searchable on the NavigationSplitView or a custom search field
TextField("Search by sender, subject, domain…", text: $searchText)
    .textFieldStyle(.roundedBorder)
    .frame(maxWidth: 320)
```

Search filters across: `senderName`, `senderAddress`, `subject`, `senderDomain`.

### Center: Bulk Actions (only when items selected)
```swift
if !selectedIDs.isEmpty {
    HStack(spacing: 8) {
        Text("^[\(selectedIDs.count) selected](inflect: true)")
            .font(Typ.caption)
            .fontWeight(.medium)
        
        Button(action: shareSelectedWithAgent) {
            Label("Share with \(focusedAgent.displayName)", systemImage: "shield")
        }
        .buttonStyle(.bordered)
        .tint(Color.agent(focusedAgent))
        
        Button(action: exportSelected) {
            Label("Export", systemImage: "arrow.down.circle")
        }
        .buttonStyle(.bordered)
    }
}
```

### Right: Agent Focus
```swift
AgentFocusControl(selection: $focusedAgent)
```

---

## Footer

```swift
HStack {
    Text("^[\(filteredMessages.count) message](inflect: true)")
        .font(Typ.caption)
    if !selectedIDs.isEmpty {
        Text("· \(selectedIDs.count) selected")
            .font(Typ.caption)
    }
    Spacer()
    Text("Last synced: 2 min ago")
        .font(Typ.caption)
        .foregroundStyle(.tertiary)
}
.padding(.horizontal, 12)
.padding(.vertical, 6)
```

---

## Empty States

Use `ContentUnavailableView` — differentiate search-empty from folder-empty:

```swift
// Search returned no results
ContentUnavailableView {
    Label("No results for \"\(searchText)\"", systemImage: "envelope")
} description: {
    Text("Try a different search term or clear filters.")
}

// Folder/filter is empty  
ContentUnavailableView {
    Label("No messages", systemImage: "envelope")
} description: {
    Text("This mailbox is empty.")
}
```

---

## EmailView.swift Changes

The parent `EmailView.swift` needs to change from a three-pane `NavigationSplitView` to a two-pane layout when showing Messages:

```swift
// When emailSubView == .messages:
NavigationSplitView {
    EmailSidebar(selection: $sidebarSelection)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
} detail: {
    // Full-width table with inline preview — NO third column
    EmailMessageList(
        sidebarFilter: sidebarSelection,
        focusedAgent: focusedAgent
    )
}
.navigationSplitViewStyle(.balanced)
```

**DO NOT** wrap this in a three-column NavigationSplitView with a reading pane column. The detail is the full-width table. Preview happens inline within the table.

---

## What to Explicitly Remove

1. **The persistent reading pane column** — no third `NavigationSplitView` column for messages
2. **The traditional Apple Mail three-pane layout** — sidebar + list + reading pane pattern is gone
3. **Any "reading pane empty state"** like "Select a message to read it" — there is no reading pane. Preview is inline.
4. **Message list without checkboxes** — every row must have a checkbox
5. **Navigation that focuses on IMAP folders** — Agent Access smart filters are the primary navigation, IMAP folders are secondary

## What to Keep

1. **The sidebar structure** — it exists, just restructured with Agent Access as primary
2. **Reading pane rendering logic** — reuse `EmailHeaderView`, `PlainTextEmailView`, `HTMLEmailView`, `AttachmentBar` components inside `InlineMessagePreview`
3. **Search functionality** — keep `EmailSearchModel`, just wire it into the new toolbar
4. **Selection model** — keep `EmailSelectionModel`, extend it for checkbox multi-select

---

## Verification

After implementing, run:

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache xcodebuild -project Manifold.xcodeproj -scheme Manifold -configuration Debug -derivedDataPath /tmp/manifold-derived-data build CODE_SIGNING_ALLOWED=NO
```

Must succeed with zero errors.
