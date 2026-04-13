# Manifold Visual Critique — Screenshot-by-Screenshot

> **Method**: Each screenshot examined pixel-by-pixel against Apple Design Award winners (Pixelmator Pro, Things 3, Bear, Fantastical, Play) and Apple HIG for macOS 26. Every issue gets three concrete fix options ranked by impact.
>
> **Research basis**: 2025 ADA winners, Apple HIG sidebars/layout/split-views documentation, WWDC25 "Get to know the new design system" session, Pixelmator Pro native framework analysis (Tower Blog), Things 3 typography/spacing blog posts, Bear's Liquid Glass redesign, Fantastical's menu bar + main window design.
>
> **What award-winning Mac apps share**: content dominates the window, chrome is ambient, every pixel serves a purpose, dense information uses precise typography and alignment, empty space is intentional not accidental, status is communicated without decoration, animation is structural not ornamental, and the app disappears — you see your data, not the app.

---

## SCREENSHOT 1: OVERVIEW TAB

The first screen a user sees. This is where Manifold makes or breaks its first impression.

---

### Issue 1.1: Massive dead space below the cards

**What's wrong**: The two agent cards and the CTA occupy roughly the top 35% of the window. The remaining 65% is blank white. This communicates "we ran out of things to show you." Pixelmator Pro fills its canvas. Things 3's overview has zero wasted space. Bear's note list goes edge-to-edge. No ADA winner has a primary view that's 65% empty.

**Why it matters**: Dead space on the primary landing screen says "this app is thin." Users unconsciously interpret it as "there isn't much here." The incentive structure: if the first screen looks empty, the user's mental model of the product shrinks to match.

**Fix A — Vertical expansion**: Make the agent cards taller and richer. Show the 3 most recent activity events inline per agent (last file accessed, last email read, timestamp). Show the actual folder names with access status. The cards become the dashboard — no separate Activity view needed for a quick glance. Cards fill 60%+ of the viewport.

**Fix B — Full-height card layout**: Switch from horizontal card pair to a full-width stacked layout where each agent gets a proper section with a summary row, a mini source list (top 5 folders with status dots), and a mini domain list (top 5 email domains). This is the Fantastical approach — the overview IS the data, compressed.

**Fix C — Adaptive density**: Use the available space dynamically. When the window is tall, show more detail per card (activity feed, source breakdown, work block history). When short, compress to the current summary. This is what Xcode's navigator does — it fills whatever space you give it. Implement with `GeometryReader` or `ViewThatFits`.

---

### Issue 1.2: Agent cards have no visual weight or hierarchy

**What's wrong**: The cards are thin-bordered rectangles with small gray text. No background differentiation, no shadow, no color identity. The gray dot next to "Claude" and "Codex" is nearly invisible. The cards look like wireframe placeholders, not finished UI. Compare to Fantastical's event cards (colored left border, subtle shadow, clear status) or Things 3's project cards (clean type hierarchy, precise spacing).

**Why it matters**: Cards are the primary data surface on this screen. If they don't command attention, the user's eye has nowhere to land. The information hierarchy is flat — everything reads at the same visual weight.

**Fix A — Agent color identity**: Give each card a left border (4pt) in the agent color (Claude blue, Codex purple). Add `Shadow.card` (0.08 opacity, radius 3, y: 1). Background: very subtle agent color tint at 2-3% opacity. The dot becomes a filled 10pt circle in the agent color. This is the Fantastical calendar-color pattern — instant visual identity.

**Fix B — Header bar treatment**: Give each card a colored header strip (32pt tall) with the agent name in white on the agent color, and an "Active"/"Paused" badge. Below: the summary stats in a clean grid. Below that: action buttons. This creates vertical rhythm: identity → data → actions. The eye flows naturally.

**Fix C — Card as mini-dashboard**: Abandon the minimal card and treat each as a dense info panel. Agent name + status badge at top. A 2×2 grid: Sources (count + coverage), Emails (domains + sensitivity), Last Activity (timestamp + description), Access Level (summary). This is the System Information approach — dense but organized.

---

### Issue 1.3: "20 sessions" subtitle is legacy language

**What's wrong**: The window title area shows "Manifold" with "20 sessions" as a subtitle. The v4.1 model eliminated session language. This is either stale data or stale copy. Either way, it undermines the product model.

**Why it matters**: The first thing a user reads contradicts the product's conceptual model. If "sessions" appears in the UI, users will think in terms of sessions. Show me the label and I'll tell you the mental model.

**Fix A — Remove entirely**: Show "Manifold" alone in the title bar. No subtitle needed. Pixelmator Pro shows the document name, Bear shows nothing, Things 3 shows the current list. For a non-document app, the app name alone is correct.

**Fix B — Truthful status subtitle**: Replace with the actual runtime state: "Connected" or "2 agents connected" or "Claude + Codex active". This makes the title bar useful — it answers "is this thing working?" at a glance.

**Fix C — Connection indicator in toolbar**: Remove the subtitle, add a small green/orange/red dot next to the title or in the toolbar that shows runtime connection status. This is the Xcode "build status" pattern — always visible, never distracting.

---

### Issue 1.4: "Start Tracked Work Block" CTA is orphaned

**What's wrong**: The blue CTA sits centered below the cards with a descriptive subtitle ("Monitor and review all AI file changes in real time"). It's floating in space with no visual connection to anything above it. The button uses the default blue system tint which doesn't relate to either agent's identity.

**Why it matters**: A CTA without context feels arbitrary. The user asks "why would I do this now?" There's no visual path from the agent cards to this action.

**Fix A — Integrate into the card footer**: Instead of a standalone CTA, add a "Start Tracked Work Block" row at the bottom of each agent card (or a shared footer spanning both cards). This connects the action to the data. The button appears after the agent summaries, creating a natural "review → act" flow.

**Fix B — Conditional prominence**: Only show the CTA prominently when it's contextually useful (e.g., both agents are connected and have sources). When not useful, dim it to a text link. When a work block IS active, replace with the banner. This is the Things 3 approach — actions appear when relevant.

**Fix C — Section with context**: Create a "Tracked Work" section below the cards with its own heading, a brief explanation for first-time users, and the CTA. After a work block runs, this section shows the last block summary. This gives the CTA a permanent home instead of floating.

---

### Issue 1.5: The toggle in the top-right toolbar is ambiguous

**What's wrong**: There's a blue toggle switch in the toolbar. No label, no tooltip visible. It's unclear what it controls — is it a master on/off? Pause all? Enable tracking? A toggle without visible state description is an anxiety-inducing control in a security app.

**Why it matters**: For a trust app, every control must be self-explanatory. An unlabeled toggle that might control AI access to your files is exactly the kind of thing that makes users nervous. The second-order effect: users who don't understand a control will avoid touching it, which means they'll never discover what it does.

**Fix A — Replace with labeled button**: Replace the toggle with an explicit "Pause All Access" button (red tint) or "Access Active" status chip (green). Buttons have inherent directionality — you know what clicking them will do. Status chips tell you the current state.

**Fix B — Toggle with permanent label**: If keeping the toggle, add a permanent label: "Access" or show "Active" / "Paused" text next to it. The toggle handle color should change (green → red). This is the minimum viable clarity.

**Fix C — Move to agent cards**: Remove the global toggle from the toolbar entirely. Put pause/resume controls on each agent card individually. This matches the v4.1 model (per-agent control) and eliminates the ambiguous global control. The toolbar gets cleaner.

---

### Issue 1.6: Tab bar ("Overview | Files | Emails") is visually disconnected

**What's wrong**: The segmented control sits in the center of the toolbar with the Liquid Glass treatment, which is fine structurally. But it's the only navigation element — there's no breadcrumb, no indication of depth, no sense of "you are here" beyond the selected segment. The tabs also don't hint at what's inside them (no counts, no status).

**Why it matters**: Award-winning apps make navigation contextual. Fantastical's tab bar shows event counts. Things 3's sidebar shows task counts. Bear's sidebar shows note counts. Naked tab labels with no metadata feel static.

**Fix A — Badge counts on tabs**: Add subtle count badges: "Files (5)" for 5 sources, "Emails (776)" for total messages or domains. Use `Type.numericCaption`. This makes tabs informational, not just navigational.

**Fix B — Status dot on tabs**: Instead of counts, add a small colored dot on tabs that need attention — orange dot on Files if an agent's access changed, blue dot on Emails if new domains appeared. This is the iOS notification badge pattern adapted for macOS.

**Fix C — Keep clean, improve elsewhere**: Leave tabs minimal (they're fine structurally) and instead improve the content areas so heavily that the tabs don't need to carry extra information. This is the Pixelmator Pro approach — navigation is simple, content is rich.

---

### Issue 1.7: "Ag ent" label text wrapping / clipping

**What's wrong**: On both the Files and Emails screenshots, the "Agent" label next to the Claude|Codex|Compare segmented control is broken across two lines as "Ag / en / t" — the text is clearly clipping or wrapping in too small a space. This is a layout bug that's visible in every content tab.

**Why it matters**: Broken text in the toolbar is an immediate credibility destroyer. It says "nobody tested this at this window width." This single bug does more damage to perceived quality than 10 missing features.

**Fix A — Remove the "Agent" label entirely**: The Claude|Codex|Compare segmented control is self-explanatory. The label adds nothing. Kill it. The segmented control speaks for itself.

**Fix B — Use a compact label**: If a label is needed for accessibility, use `.accessibilityLabel("Agent focus")` without a visible label. Or show "Focus:" in `Type.caption` with proper minimum width constraints.

**Fix C — Fix the layout constraint**: Set `minWidth` on the label or use `.fixedSize()` to prevent wrapping. But honestly, Fix A is the right answer — the label shouldn't exist.

---

## SCREENSHOT 2: FILES TAB

The core data surface. This is where Manifold proves it can handle information density.

---

### Issue 2.1: Empty table rows (gray placeholder stripes)

**What's wrong**: Below the 5 source rows, there are approximately 10 gray striped placeholder rows extending to the bottom of the table. These aren't real data — they're visual noise. No ADA-winning app shows fake rows. Xcode's file navigator stops at the last file. Finder's list view stops at the last item. These stripes say "we drew a table and forgot to clip it."

**Why it matters**: Placeholder rows actively mislead. A user scanning quickly might think there are 15 sources, not 5. The stripes also make the real data harder to distinguish from the background. The incentive: if the table looks full, there's less urgency to add more sources; if it looks correctly sparse, the user understands the scope.

**Fix A — Remove all placeholder rows**: End the table at the last real row. Below: either clean empty space with the footer summary, or a soft prompt to "Add more folders to expand monitoring." This is the standard macOS Table/List behavior.

**Fix B — Subtle empty state below data**: After the last row, show a single subtle line: "5 sources · 0 files scanned · Add Folder…" as a footer. This converts dead space into useful summary + action.

**Fix C — Expand the table to fill with a proper empty row**: If the table must fill the space (as in some macOS split views), use a single "No more sources" row at the bottom in secondary text, not repeating stripes.

---

### Issue 2.2: "Items" column shows "—" for every row

**What's wrong**: Every source row shows "—" in the Items column. Either the data isn't being loaded, or the enumeration hasn't run. Either way, an entire column of dashes is wasted space that communicates "we planned to show something here but can't."

**Why it matters**: A column that shows no data is worse than a missing column. It draws attention to absent functionality. Users see five dashes and think "is this broken?"

**Fix A — Show real counts or loading state**: If enumeration is pending, show a small spinner or "Scanning…" text per row. If enumeration hasn't run, show "—" only temporarily, then populate. If it can't count, remove the column.

**Fix B — Lazy count with placeholder**: Show "…" as a placeholder, trigger background enumeration, replace with real count when available. Use `.contentTransition(.numericText())` for the transition. This is the Finder approach — it shows "Calculating…" then the real size.

**Fix C — Remove the column if consistently empty**: If Items can't be populated in the current state, hide the column until it can be. A column of dashes is worse than no column. Show it when data exists.

---

### Issue 2.3: "Access" column checkboxes lack context

**What's wrong**: The rightmost column shows blue checkboxes. They're all checked. There's no column header label visible ("Access" is cut off or missing). The checkboxes don't indicate WHICH agent has access — the Claude|Codex|Compare segmented control above is supposed to filter this, but the visual connection is weak.

**Why it matters**: For a trust app, the access column is the most important column in the table. It should be the clearest, most unambiguous element. Right now it's a column of blue checkmarks with no visible header, no agent color association, and no distinction between "Claude has access" and "Codex has access."

**Fix A — Agent-colored checkboxes**: When focused on Claude, the checkboxes should be Claude blue. When Codex, Codex purple. In Compare mode, show two columns (Claude | Codex) with different colors. The checkbox color IS the answer to "who has access."

**Fix B — Replace checkboxes with status text**: Instead of a checkbox, show "Granted" in green text with a small dot, or "No Access" in gray. Text is unambiguous. The Finder's Get Info permission display uses text, not checkboxes.

**Fix C — Add agent icon to column header**: Even keeping checkboxes, the column header should show "Claude Access" (or the agent badge) when filtered to Claude. This ties the column to the segmented control above.

---

### Issue 2.4: Sidebar source list has no visual differentiation

**What's wrong**: The sidebar shows 5 source names, an "Add Folder..." button, two Versions entries, and "View Activity" — all in the same visual weight. There's no hierarchy between sources and actions, no grouping, no section headers with proper weight, no counts. The blue folder icons are the same shade regardless of access status.

**Why it matters**: Sidebars in award-winning apps are information-dense but hierarchically clear. Bear's sidebar has bold folder names, gray counts, and clear section breaks. Finder's sidebar has distinct sections (Favorites, Locations, Tags) with headers. This sidebar is a flat list.

**Fix A — Section headers with weight**: Use `.headerProminence(.increased)` for "Sources" and "Versions" headers. Add item counts: "Sources (5)", "Recently Modified (12)". Use `Type.caption` in `.secondary` for counts. Add visual separators between sections.

**Fix B — Agent-colored dots on sources**: Each source gets a dot in the focused agent's color if that agent has access. Gray dot if no access. This creates a scannable "access map" in the sidebar without opening each source.

**Fix C — Source metadata on second line**: Show each source name with a second line in `Type.caption` showing the path and item count: "IBM_Plex_Sans" / "~/Downloads · 47 files". This is the Mail.app sidebar pattern — name + metadata.

---

### Issue 2.5: Toolbar "Agent" label is word-wrapping (same as 1.7)

**What's wrong**: "Ag / en / t" is visually broken, appearing as wrapped/clipped text next to the segmented control. This appears identically in Screenshot 2.

(Fixes same as Issue 1.7 — remove the label.)

---

### Issue 2.6: "Activity" title in the content header area

**What's wrong**: The content area header shows "Activity" with "20 sessions" below it, to the left of the segmented tab bar. This is confusing — we're on the Files tab, looking at the Sources table, but the header says "Activity." The title doesn't match the content. (This may be a global header that should change per tab.)

**Why it matters**: If the header says "Activity" but I'm looking at a files table, the information architecture feels broken. The user doesn't know what view they're in.

**Fix A — Dynamic title per tab**: Overview → "Overview", Files → "Sources" (or the selected source name), Emails → "Domains" or "Messages" depending on sidebar selection. The title should always describe what you're looking at.

**Fix B — Remove the content-area title**: Let the tab bar be the sole navigation indicator. The content speaks for itself. Pixelmator Pro doesn't title its canvas. Bear doesn't title its note list.

**Fix C — Use title for context breadcrumb**: Show "Files → Sources" or "Files → IBM_Plex_Sans" as a breadcrumb when drilling into a source. The title becomes a navigation aid, not a static label.

---

### Issue 2.7: Table lacks visual rhythm and density control

**What's wrong**: The source rows are widely spaced with large padding. The Name and Path columns dominate but the path text is small and hard to scan. There's no alternating row color, no hover state visible, no row dividers between entries. The table feels like a spreadsheet that forgot its grid.

**Why it matters**: Data tables in polished apps have precise rhythm. Finder's list view has tight, consistent row heights with clear dividers. Xcode's file navigator uses minimal padding with precise font sizing. The current table wastes vertical space while making the data harder to scan.

**Fix A — Tighten row height and add dividers**: Reduce row padding to 6pt vertical (from what appears to be 12+). Add `.listRowSeparator(.visible)` or thin 1px dividers between rows. Right-align Items column. This is the Mail.app message list density — tight but readable.

**Fix B — Use native `Table` component**: If not already using SwiftUI `Table`, switch to it. Native `Table` gives you: click-to-sort column headers, proper column resizing, hover highlighting, selection, and accessibility for free. This is by far the highest-ROI change for this view.

**Fix C — Conditional density**: Offer two modes via a density control: "Comfortable" (current spacing) and "Compact" (tighter). Default to Compact for 5+ sources. This is the Mail.app density toggle pattern.

---

## SCREENSHOT 3: EMAILS — DOMAINS VIEW

The domains governance surface. Shows which email domains each agent can access.

---

### Issue 3.1: Domain list is an undifferentiated wall of text

**What's wrong**: The domains list shows ~20 domains in identical formatting. Each row shows "@domain" and "X emails" in the same typeface and weight. There's a "Work" section header at the top, but every domain below it looks identical. No icons, no categories beyond "Work", no visual grouping, no access indicators, no color. It's a phone-book-style listing.

**Why it matters**: This is the email trust surface — the user needs to understand at a glance which domains are important, which are risky, which have AI access. A flat list makes every domain equal, which is the opposite of useful. @email.apple.com (805 emails) should look different from @e.nfl.com (1 email).

**Fix A — Visual weight by volume**: Scale the visual treatment by email count. Domains with 100+ emails get `Type.body` weight. Domains with <10 get `Type.caption` weight. The email count becomes a right-aligned `Type.numericCaption` badge. This creates a natural "importance heat map" through typography alone.

**Fix B — Category grouping with icons**: Group domains into visible categories (Work, Automated/Transactional, Personal, Financial, Government) with SF Symbol icons and section headers. Each section is collapsible. @hmpo.gov.uk goes under Government (building.columns icon), @creditcard.virginmoney.com goes under Financial (banknote icon). This is the Mail.app smart mailbox approach.

**Fix C — Domain cards instead of rows**: For the most important domains (>50 emails), show small summary cards: domain name, email count, last email date, agent access badge. For less important domains, show compact rows. This creates a two-tier visual hierarchy: featured domains + everything else.

---

### Issue 3.2: Access toggle column is gray/invisible

**What's wrong**: The rightmost column appears to have gray unchecked toggle circles for every domain. They're barely visible — the gray circles on white background have almost no contrast. It's unclear whether this means "no access" or "access not configured" or "toggle is disabled."

**Why it matters**: This is the ACCESS CONTROL column in an ACCESS CONTROL app. It should be the most visually prominent element in the row. Instead it's the most invisible. The user has to squint to see whether AI can read their emails from each domain.

**Fix A — Colored access indicator**: Replace gray circles with clear states: filled agent-color circle = access granted, empty circle with red slash = denied, orange circle = restricted by sensitivity. The state must be readable at arm's length.

**Fix B — Text labels instead of toggles**: Show "Allowed" (green) or "Blocked" (gray/red) as text. No ambiguity. Add the agent name: "Claude: Allowed" in the agent's color. This eliminates all guesswork.

**Fix C — Inline toggle with color change**: Keep the toggle but make it dramatically more visible: ON = filled agent color, OFF = clear gray with visible border. The toggle should be large enough to click easily (at least 24pt wide) and change color with `Anim.stateChange`.

---

### Issue 3.3: "Sensitivity" picker is truncated

**What's wrong**: The Sensitivity picker in the toolbar shows "Mo..." — clearly truncated from "Moderate" or similar. The picker is too narrow for its content.

**Why it matters**: A truncated control in the toolbar looks broken. The user can't read the current sensitivity level without clicking the picker. For a security control, the current state must always be fully visible.

**Fix A — Wider picker with full text**: Set `.frame(width: 180)` or wider on the picker. Show the full word: "Moderate", "Strict", "Permissive". If space is limited, use abbreviations that aren't truncated: "Mod", "Strict", "Perm".

**Fix B — Segmented control instead of picker**: Replace the dropdown picker with a segmented control showing all options: "Permissive | Moderate | Strict". Always visible, no truncation, current state always clear. This is better UX for 3-4 fixed options.

**Fix C — Move to sidebar or section header**: Move sensitivity out of the toolbar into a dedicated row above the domain list: "Sensitivity: Moderate ▾" with a dropdown. This gives it more space and creates a logical reading order: set sensitivity → see filtered domains.

---

### Issue 3.4: "1 emails" grammar error

**What's wrong**: Multiple rows show "1 emails" instead of "1 email". Basic pluralization bug.

**Why it matters**: Grammar errors in the UI signal carelessness. For a security/trust app, every detail matters. If the developer didn't notice "1 emails," what else did they miss?

**Fix A — Proper pluralization**: Use `"\(count) \(count == 1 ? "email" : "emails")"`. Or better: `Text("^[\(count) email](inflect: true)")` using SwiftUI's automatic grammar agreement.

**Fix B — Numeric + noun separation**: Show just the number with a column header "Emails" — then each row shows "1", "5", "53" etc. The column header provides the noun. This also allows right-alignment of numerics.

**Fix C — Remove count from row, add to section**: Show counts only on section headers: "Work — 923 emails across 20 domains." Individual rows don't need counts if the list can be sorted by volume.

---

### Issue 3.5: Sidebar is sparse and lacks email-specific navigation

**What's wrong**: The email sidebar shows "All Domains", "Messages", one account, and "View Activity". That's 4 items. Bear's sidebar has folders, tags, search. Mail.app's sidebar has favorites, smart mailboxes, accounts, folders. This sidebar doesn't help the user navigate their email.

**Why it matters**: A sidebar with 4 items is a sidebar that shouldn't exist. Either fill it with useful navigation or collapse it. Currently it wastes 200pt of horizontal space to show almost nothing.

**Fix A — Expand with smart mailboxes**: Show the email-specific sidebar from Screenshot 4 (Favorites, Smart Mailboxes, IMAP folders) in this view too. When "All Domains" is selected, show the domains table. When a folder is selected, show messages. The sidebar should be consistent across email sub-views.

**Fix B — Add domain categories to sidebar**: Show domain categories (Work, Automated, Personal, etc.) as sidebar items below "All Domains". Selecting a category filters the domains table. This gives the sidebar a purpose.

**Fix C — Remove sidebar on Domains view**: If the sidebar can't earn its space, hide it when showing the domains table. Show it only when viewing messages (where the folder tree matters). Use a toolbar button to switch between Domains and Messages views.

---

### Issue 3.6: No visual connection between agent segmented control and domain data

**What's wrong**: The Claude|Codex|Compare control sits in the toolbar. The domains below don't change color or show any visual indication of which agent is focused. In Claude mode, every domain should feel "Claude-colored." In Compare mode, you'd expect two access columns.

**Why it matters**: The agent focus is the primary filter for the entire view. If switching from Claude to Codex changes nothing visually (other than the selected segment), the user questions whether the switch did anything.

**Fix A — Agent-tinted header bar**: When Claude is selected, the toolbar area gets a very subtle Claude blue tint (2% opacity). When Codex, purple. This ambient cue reinforces which agent you're managing without any text changes.

**Fix B — Access column header shows agent name**: The access column header changes: "Claude" (blue) or "Codex" (purple) or "Claude | Codex" in Compare. The column header IS the agent indicator.

**Fix C — Row tinting for granted domains**: Domains that the focused agent can access get a subtle row tint in the agent's color (4% opacity). Domains without access have no tint. This creates an instant visual map: colored rows = agent can see these.

---

## SCREENSHOT 4: EMAILS — MESSAGES VIEW

The email browser. Three-pane split: sidebar, message list, reading pane.

---

### Issue 4.1: The sidebar is too narrow and content is truncating

**What's wrong**: The sidebar shows IMAP folder tree but almost everything is truncated: "All..." (16,...), "Sent Me...", "Deleted...", "Shared..." (0), "New Sma...", "amar.gandhi..." The sidebar is so narrow that folder names, smart mailbox names, and the account email are all clipped.

**Why it matters**: A sidebar where you can't read the items defeats the purpose of a sidebar. The user has to guess what "Sent Me..." means. Every truncated label is a micro-frustration that accumulates.

**Fix A — Increase minimum sidebar width**: Set `min: 220` (or even 240) on the sidebar. "Sent Messages", "Deleted Items", "Smart Mailboxes" should all fit without truncation at the default width. Allow user resize wider.

**Fix B — Use abbreviated labels**: "Sent" instead of "Sent Messages", "Trash" instead of "Deleted Items", "Smart" instead of "Smart Mailboxes". Shorter labels that don't truncate are better than long labels that do. Mail.app uses "Sent", not "Sent Messages."

**Fix C — Two-tier sidebar**: Show the account email on a full-width row above the folder tree, not as a sidebar item competing for the same width. This lets the folder names have the full sidebar width. The account acts as a section header, not a list item.

---

### Issue 4.2: Message list pane is empty but doesn't explain why

**What's wrong**: The middle pane shows "Unviewed · 0 messages" at the top, then a sort control, then "No Emails / This mailbox is empty or still syncing." The empty state uses `ContentUnavailableView` with a generic envelope icon.

**Why it matters**: "Empty or still syncing" is hedge-language. The app doesn't know its own state. Is it syncing? Then show a progress indicator. Is it empty? Then say so definitively. The "or" communicates uncertainty, which is the opposite of trust.

**Fix A — Distinguish syncing from empty**: If syncing: show `ProgressView("Syncing Unviewed messages…")` with the account name and estimated progress. If truly empty: show "No unviewed messages" with a warmer tone: "All caught up. Messages you haven't read will appear here."

**Fix B — Show sync status explicitly**: Add a small status line below the mailbox name: "Last synced: 2 min ago" or "Syncing… 42%". This removes all ambiguity. The empty state then says definitively "No messages" (no hedging).

**Fix C — Proactive navigation**: If the selected mailbox is empty, suggest navigating to one that isn't: "No unviewed messages. Try [All Mail (776)] or [INBOX]." Give the user somewhere to go instead of a dead end.

---

### Issue 4.3: Reading pane empty state is cold

**What's wrong**: The right pane shows "No Email Selected / Select an email to read it." Generic envelope icon. Standard `ContentUnavailableView`. This is functional but emotionally flat.

**Why it matters**: The reading pane is the largest area on screen. When empty, it's the dominant visual element. A cold, generic empty state makes the entire app feel sterile.

**Fix A — Warm copy with keyboard hint**: "Select a message to read it here. Use ↑↓ to navigate, Space to scroll." This is helpful AND warm — it teaches the user something.

**Fix B — Show account summary instead**: When no message is selected, show a brief account summary: "amar.gandhi@me.com · 776 messages · Last synced 2 min ago." The reading pane becomes temporarily useful instead of dead.

**Fix C — Minimal but refined**: Keep the envelope icon but make it smaller (32pt, not 48pt), use `Type.secondary` for the text, and add a very subtle background color (quaternary) to distinguish the empty reading pane from the message list. The refinement says "we designed this state."

---

### Issue 4.4: Double search icons in the toolbar

**What's wrong**: The toolbar on the far right shows two magnifying glass icons. One appears to be the standard search button, the other might be an email-specific search. Having two identical-looking search icons adjacent to each other is confusing.

**Why it matters**: Two of the same icon = one of them is wrong. The user doesn't know which to click. If they do different things, they need different icons or labels. If they do the same thing, one should be removed.

**Fix A — Remove one**: Determine which search is correct for this context and remove the other. One search icon, always.

**Fix B — Differentiate visually**: If both are needed (e.g., global search vs. message search), make them visually distinct: one could be `magnifyingglass` (global) and the other `text.magnifyingglass` (content search). Or label one.

**Fix C — Replace one with filter**: If one is really a filter function, change its icon to `line.3.horizontal.decrease` (the standard macOS filter icon). Different function = different icon.

---

### Issue 4.5: Folder tree has no visual hierarchy

**What's wrong**: The folder tree shows Favorites, Smart Mailboxes, and IMAP folders at similar visual weight. "All..." with the blue 776 badge, "Unviewed" with an eye icon, "INBOX" with an inbox icon — these are all structurally different things (smart filter, favorite, IMAP folder) but they look the same.

**Why it matters**: A folder tree without visual hierarchy makes it hard to build a mental model. The user needs to understand: these are favorites (pinned shortcuts), these are smart filters (computed), these are real IMAP folders. Without hierarchy, the tree is a flat list of words.

**Fix A — Section headers with prominence**: Use `.headerProminence(.increased)` for "Favorites", "Smart Mailboxes", and the account name. Add spacing between sections (12pt). Account name in `Type.heading`. Section headers in `Type.caption` with `.foregroundStyle(.secondary)`.

**Fix B — Visual grouping through indentation and icons**: Favorites: pinned icon style, no indentation. Smart Mailboxes: computed/gear icon, indented. IMAP folders: standard folder icons, indented under account. The indentation creates visual grouping without needing explicit headers.

**Fix C — Collapsible sections with disclosure triangles**: Make each section (Favorites, Smart Mailboxes, Account) a proper `DisclosureGroup` that can collapse. The user can hide what they don't need. This is the Mail.app sidebar pattern exactly.

---

### Issue 4.6: "Add Acco..." button is truncated

**What's wrong**: "Add Account..." is truncated to "Add Acco..." at the bottom of the sidebar. Another casualty of the too-narrow sidebar.

**Why it matters**: Same as 4.1 — truncated text looks broken. This particular truncation is on an action button, making it even worse.

**Fix A — Fix sidebar width (see 4.1)**: Wider sidebar fixes this automatically.

**Fix B — Icon-only button**: Replace "Add Account..." with a "+" icon button at the bottom of the sidebar, like Mail.app's sidebar footer. Tooltip on hover: "Add Email Account…"

**Fix C — Move to Settings**: "Add Account" is a one-time setup action. It doesn't need to live in the sidebar permanently. Move it to Settings → Mail, where it already exists. In the sidebar, show a subtle "Manage accounts" link only when no accounts are configured.

---

### Issue 4.7: Three-pane layout proportions are off

**What's wrong**: The sidebar takes ~20% of width, the message list ~30%, and the reading pane ~50%. But the message list is empty and the reading pane is showing a generic empty state. The proportions feel arbitrary — neither the message list nor the reading pane is using its space well.

**Why it matters**: In a three-pane layout, proportions should serve the content. Mail.app and Mimestream give the reading pane ~55%, the message list ~25%, and the sidebar ~20%. But they also have content in those panes. When two panes are empty, the layout looks broken regardless of proportions.

**Fix A — Default to two-pane until a message is selected**: Show sidebar + full-width message list when no message is selected. Reveal the reading pane only when a message is clicked. This is the Mail.app behavior in "classic" layout — the split happens on demand.

**Fix B — Use NavigationSplitView.balanced**: Let the system manage proportions. Set reasonable `min` and `ideal` widths: sidebar min 200/ideal 220, message list min 250/ideal 300, reading pane min 350/ideal remainder. Let the user drag dividers.

**Fix C — Responsive layout based on window width**: Below 1000pt width, collapse to two-pane (sidebar + content). Below 800pt, single-pane with navigation. This prevents the "three empty panes" look at narrow widths.

---

## CROSS-CUTTING ISSUES (visible across multiple screenshots)

---

### Issue X.1: No app icon in the Dock

**What's wrong**: (Not visible in screenshots, but confirmed from audit.) The Dock shows a generic SwiftUI app icon, not a custom Manifold icon.

**Fix A/B/C**: See A-02 in POLISH-BACKLOG.md. This is the single highest-impact visual change.

---

### Issue X.2: Window has no sense of brand or identity

**What's wrong**: Across all four screenshots, there's nothing that says "this is Manifold." No brand color, no distinctive visual element, no personality. It looks like a tutorial project. Compare to Fantastical (red calendar accent), Bear (softer corners and signature sidebar), Things 3 (checkbox aesthetic and blue accents), Pixelmator Pro (dark canvas with monochrome tools).

**Fix A — Agent colors as ambient identity**: Claude blue and Codex purple become the app's visual identity. Subtle tints, colored dots, agent badges, card borders — the agent colors are always present. The app's identity IS the agent relationship.

**Fix B — Distinctive sidebar treatment**: Give the sidebar a slightly warm background tint or a subtle gradient that's uniquely Manifold. Bear uses a "boxed" sidebar. Things 3 uses a light gray. Manifold could use the standard Liquid Glass but with a very subtle brand-color tint.

**Fix C — Typography as personality**: Choose one distinctive typographic treatment — for example, use SF Pro Rounded for headings (warm, approachable) and SF Pro for body (sharp, professional). This creates a recognizable feel without any color work.

---

### Issue X.3: Inconsistent information density across tabs

**What's wrong**: Overview is 35% utilized (sparse). Files is 60% utilized (moderate). Emails/Domains is 80% utilized (dense). Emails/Messages is 20% utilized (mostly empty). The app lurches between "nothing here" and "wall of data" with no consistent density philosophy.

**Fix A — Establish a target density**: Pick a density: "comfortable utility" (like Things 3) or "dense professional" (like Xcode/Mail.app). Apply it uniformly. Every view should feel like it was designed by the same person at the same time.

**Fix B — Content-aware density**: Views with little data (Overview, Versions) use larger type and more spacing. Views with lots of data (Domains, Messages) use tighter spacing and smaller type. But the transition between views should feel natural, not jarring.

**Fix C — Minimum content guarantee**: Every view should show at least 3 meaningful pieces of information without scrolling. If the view can't fill its space with primary content, add secondary context (activity feed, summary stats, recent changes) until the minimum is met.

---

### Issue X.4: No loading, error, or connection state visible anywhere

**What's wrong**: Across all four screenshots, there's no indication of runtime status, connection health, sync progress, or potential errors. The app appears to be connected (it has data), but the user has no way to verify this from any screen.

**Fix A — Persistent status indicator**: A small colored dot in the toolbar (green = connected, orange = partial, red = disconnected) that expands on hover to show per-agent connection status. Always visible on every tab.

**Fix B — Connection state in agent cards**: Each agent card on the Overview shows "Connected" or "Disconnected" with a timestamp. The card border changes color: green border = connected, gray border = disconnected, orange = degraded.

**Fix C — Status bar footer**: A thin status bar at the bottom of the window (like Xcode) showing: "Claude: Connected · Codex: Connected · Last sync: 2 min ago · 5 sources · 776 emails". Dense, always visible, always truthful.
