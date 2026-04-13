# Manifold v4 Design Critique

> A deep, honest review of the v4 wireframe and spec through the lens of the design literature that actually matters: Apple HIG, Don't Make Me Think (Krug), About Face (Cooper), Designing Interfaces (Tidwell), Refactoring UI (Wathan & Schoger), Edward Tufte's information design principles, Dieter Rams' 10 principles, and LoveFrom's philosophy of care-as-signal.

---

## First Impression (the 2-second test)

Open the wireframe. What do you see first?

The Overview tab lands you on two agent cards. Your eye goes to **"Claude (Cowork)" + "connected"** — correct, that's the subject. Then the policy grid (files/emails boxes). Then the activity feed. The segmented nav at the top is immediately legible: Overview, Files, Emails.

**What works**: The trust question ("What can this AI see?") is answerable in under 3 seconds. The agent card is a single glanceable unit. This is the right starting point.

**What doesn't**: The emotional register is neutral-to-bureaucratic. Every surface looks the same — white cards on gray, 13px text, gray borders. There's no visual moment that says "this is a trust boundary, and you are in control." Compare Apple's Screen Time, which uses bold color blocks and large type to communicate "this is your relationship with your devices." Or Apple's Privacy Report in Safari, which uses gradient headers and clear iconography. Manifold's Overview feels like a settings panel, not a command center.

**Diagnosis**: The wireframe prioritizes *information completeness* over *emotional clarity*. It shows everything, but it doesn't *feel* like anything. Rams' first principle: "Good design is innovative." The form needs to communicate the product's reason for being.

---

## Structural Critique

### The 3-tab model is correct — but the tabs are doing too many jobs

Overview, Files, Emails is the right information architecture. It maps to the product's actual structure: trust overview, file data, email data. This follows Cooper's principle of matching the user's mental model.

But within each tab, there's a hidden mode-switching problem. Files has Sources mode and Files mode. Emails has Domains mode and Messages mode. These are accessed via a tiny segmented toggle at the top of the sidebar.

**The problem**: This is what Krug calls "hidden controls hiding essential functions." The Sources table is *the most important surface in the entire app* — it's where you grant and revoke file access. But it's one click behind a toggle that defaults to itself. When the user switches to Files mode to browse, they lose the Sources table entirely. There's no breadcrumb, no way to see both at once.

**What Apple does**: Look at Finder. Finder doesn't ask you to choose between "volumes view" and "files view." The sidebar shows volumes *and* the file tree simultaneously. The sidebar is the navigation; the main area is the content.

**Recommendation**: Don't make Sources mode and Files mode exclusive. The sidebar already lists sources — when you click a source in the sidebar, the main area should show that source's files. When you're not clicking any source, the main area should show the Sources overview table. The view toggle should be removed. The sidebar IS the mode switch.

This same logic applies to Emails: clicking "All Mail" in the sidebar should show the Domains table. Clicking a specific account or mailbox should show Messages for that context. No toggle needed.

### The sidebar has an identity crisis

Across the three tabs, the sidebar serves wildly different purposes:

- **Overview sidebar**: Agent list + quick actions + system stats (launcher/dashboard pattern)
- **Files sidebar**: View mode toggle + source list + version filters + activity link (navigation + filter hybrid)
- **Emails sidebar**: View mode toggle + account tree + sensitivity pickers + smart mailboxes + add account (navigation + settings + filter)

The Emails sidebar in particular is doing 5 unrelated jobs. Cooper calls this "featuritis of the interface chrome." Tidwell would say the sidebar has no single *organizing principle* — it's a junk drawer of controls that happened to be left over after the main content was designed.

**What Apple does**: Look at Mail.app's sidebar. It does one thing: navigation. Mailboxes, smart mailboxes, accounts — all navigation targets. Settings live in Preferences. Filters live in the toolbar/search. The sidebar never contains settings controls (like sensitivity dropdowns).

**Recommendation**: The sensitivity pickers do not belong in the sidebar. They are access controls. They should live either:
1. In the Domains table header (next to the agent column headers — "Claude: Moderate ▼"), or
2. In the Overview agent card's Email section, where they're contextualized by agent

The sidebar should be pure navigation: accounts, mailboxes, smart mailboxes. Nothing else.

### The Overview agent cards are too dense

Each agent card contains: header with pause button, 2-column policy grid (files + emails), work block status row, activity feed (3 items), and an actions row. That's 6 distinct information zones in a single card.

Tufte would call this "chartjunk" — not because any individual element is wrong, but because the density prevents any element from having visual weight. When everything is equally dense, nothing is emphasized.

**What to cut**:
- The ✓/✗ source list in the Files section duplicates what's in the Files tab. The overview card doesn't need to show every source — it needs a summary. "2 of 3 sources · 225 files" is sufficient. Click to go to Files tab.
- The "No active work block" row takes up space to say nothing. Show work block status ONLY when a work block is active. When idle, that space doesn't exist. This follows Tufte's "smallest effective difference" — don't render a zero state that communicates absence of information.
- The activity feed showing 3 events is useful but visually fights with the policy grid for attention. Consider: show activity only for the *focused* agent (the one the cursor last interacted with), or show it in a shared section below both cards, not duplicated inside each one.

**What the card should be**: A glanceable badge — think Apple Watch complications. Name, connection state, one-line file access summary, one-line email access summary, pause button. That's it. Everything else is reached by clicking through to Files or Emails tabs, or expanding for detail.

---

## The Core Interaction: Checking and Unchecking

This is the most important interaction in the product. The entire app exists so that the user can check a box next to "web-app" under "Claude" and feel confident about what that means. Let me evaluate it through Cooper's "commensurate effort" principle: the effort to perform an action should be proportional to the consequence.

### What's good

The Intentionality Rule (broadening = sheet, narrowing = inline) is excellent design. It's the correct asymmetry. Apple's own permission system works this way — granting Location access requires a modal dialog; toggling it off in Settings is a switch flip. The v4 spec understands this.

The per-agent checkbox columns in the Sources and Domains tables are the right primitive. Two columns, always visible, always reflecting persistent state. This makes the trust boundary visible in the data itself, not in a separate control surface. Tufte would approve — the data and the control are the same object.

### What's concerning

**Problem 1: Checkbox visual weight is too small for the action's consequence.** A 16×16 checkbox is the standard affordance for "toggle this setting." But checking a source checkbox means "this AI agent can now read all 182 files in this folder." That's a significant trust decision being communicated through the smallest possible visual element.

Compare Apple's "Selected Photos" picker in Privacy settings. When you grant photo access, you see the actual photos in a grid — not a checkbox next to "Photos: 12,847". The visual weight matches the consequence. Manifold can't show file previews in a table row, but it can do more than a checkbox.

**Recommendation**: When a checkbox is checked, the row should react — not just the checkbox. Consider a subtle background color tint on the row (blue for Claude, purple for Codex, blended for both). The row becomes "claimed" by the agent. When unchecked, the row returns to neutral. This gives the action visual consequence beyond the checkbox state change.

**Problem 2: The toast for granting access is backwards.** Currently, granting access shows a toast with no undo ("Claude can now access web-app"). Revoking access shows a toast with undo. But the higher-consequence action (granting) is the one that should be easier to reverse from the toast. Revoking is already the safe action — undo on revocation is less critical.

**Recommendation**: Flip it. Granting access (when it's inline, not the first-grant sheet) should show a toast WITH undo: "Claude can now access web-app · Undo". Revoking access should show a brief confirmation toast WITHOUT undo, or with a less prominent undo. The undo should track the risk, not the direction.

Actually, on further thought, both should have undo — but the revocation undo matters less because the action itself is safe. The key insight is: don't treat undo as a safety mechanism for dangerous actions. Undo is a comfort mechanism for any action. The Review Access sheet is the safety mechanism for dangerous actions.

**Problem 3: The "Future" column in the Domains table is the most important information and the hardest to parse.** The Domains table has an "Archived" column (count) and a "Future" column ("Included" / "Excluded" / "Hidden"). This is the honesty mechanism — telling the user that checking this domain means future emails too, not just the 247 they see now.

But "Included" and "Excluded" are passive, bureaucratic labels. They don't communicate what they mean. "Included" in what? Included where? A user scanning this table for the first time has to stop and think about what "Future: Included" means. Krug's first law: "Don't make me think."

**Recommendation**: Replace the label. Instead of "Included" / "Excluded", use "Future mail: On" / "Future mail: Off" with a small toggle, or simply merge the concept: the checkbox already communicates "this domain's emails are accessible." The "Archived" count shows the snapshot. Add a small icon or text note: "＋ future" next to checked domains. Kill the separate column. You're using two columns to communicate one concept (is this domain active or not) when the checkbox already does it.

---

## Information Design Failures

### The Domains table has too many columns

8 columns: Icon, Domain, Category, Archived, Future, Claude, Codex, Note. On a typical 13" MacBook, this creates a cramped grid where every cell is fighting for horizontal space.

Tufte's principle of data-ink ratio: every drop of ink on the page should communicate data. The "Icon" column (emoji per domain) is decorative — it doesn't help decision-making. The "Category" column (Work, Automated, Personal, Hidden) is useful for sorting but doesn't need a dedicated column — it could be a colored tag on the domain name, or a grouping header.

**Recommendation**: Reduce to 5 columns: Domain (with category as colored dot/tag), Count (merge Archived into this), Claude ☑, Codex ☑, and a status indicator (✓ active / ○ excluded / 🚫 hidden). Group rows by category using section headers. This is how Finder groups files by Kind — the grouping provides the categorical information without a dedicated column.

### The "Hidden by sensitivity" separator is good but the implementation is crude

The current wireframe shows a gray row with "HIDDEN BY SENSITIVITY" text acting as a section separator. This is the right idea but the wrong execution. It looks like a broken table row. In SwiftUI, this should be a proper `Section` header with the standard HIG treatment — left-aligned label, subtle background, sitting above the hidden rows.

The hidden rows themselves have `opacity: 0.55` and show 🚫 symbols in place of checkboxes. This is correct behavior but the 🚫 emoji is visually noisy. A simple disabled checkbox (grayed out) communicates "not available" more quietly. The Note column ("banking", "health", "2FA") is the useful information — make sure it's readable despite the reduced opacity.

### Empty states are missing entirely

The wireframe shows a fully populated state. But what does the app look like when:
- No sources have been added? (First launch)
- No email accounts are connected?
- An agent is connected but has zero access?
- No work blocks have ever been created?

Krug and Cooper both emphasize that empty states are the most important states to design because they're the user's first encounter with each surface. An empty Sources table should say something like:

> "Add a folder to get started. Claude and Codex will only see files in folders you choose."

An empty agent card should communicate:

> "Claude is connected but can't access any files or emails yet. Review Access to get started."

The wireframe needs these states designed. They communicate the product's value proposition more than any populated state does.

---

## Emotional Design & LoveFrom Lens

Jony Ive's design philosophy, now expressed through LoveFrom, can be summarized in one sentence: **The care you put into the invisible details signals to the user that the product is worthy of their trust.** This is especially relevant for Manifold because the product literally asks for trust — trust that it will correctly mediate between the user's data and AI agents.

### Where the design shows care

**The Intentionality Rule** is an act of care. The app could just let you check boxes freely. Instead, it pauses at the first consequential moment and asks you to review. This is the app saying "I take this seriously." That's a LoveFrom moment — the friction is the feature.

**The "Accessible because web-app is shared with Claude" line in the Inspector** is another act of care. It explains *why* this file is visible, not just *that* it is. This is transparent design. The user can trace the chain of causality.

**The per-agent sensitivity controls** are honest. They don't hide behind a single global setting. Each agent has its own trust boundary. This respects the fact that you might trust Claude with moderate email access but keep Codex on strict.

### Where the design lacks care

**The typography is monotonous.** Everything is 11-13px SF Pro in medium/semibold weights. There's no typographic hierarchy that tells you what to read first. A LoveFrom product would use type scale to create drama — a 20px agent name, 13px metadata, 11px timestamps. The size differences should be more pronounced. Currently, the agent card header ("Claude (Cowork)") is 15px and the section titles are 11px. That's a 4px difference. It's not enough to create visual hierarchy — Refactoring UI recommends at least a 1.5× ratio between hierarchy levels (so if body is 13px, headers should be ≥20px).

**The color palette is purely functional.** Blue = Claude, Purple = Codex, Green = good, Red = bad. These are safety colors, not brand colors. The app has no visual personality. Compare Apple's Weather app — it uses the color of the sky itself to communicate the data. Manifold could use subtle gradients or tints in the agent cards that change based on state: a calm blue wash when Claude is connected and active, a muted gray when disconnected, a warm amber when a work block is running. The color should be *felt*, not just *read*.

**The Pause button doesn't feel like an emergency control.** It's styled as a secondary button with a small label. But this is the "big red button" — the one you hit when an AI agent is doing something wrong and you need it to stop immediately. It should feel urgent. Not aggressive by default, but it should look different from every other button. Consider: no border, just the word "Pause" in the agent's color, positioned at the far right with adequate breathing room. On hover, it turns red. On click, it becomes "Resume" in green. The visual weight should match the action's gravity.

**There's no animation language described.** A LoveFrom product doesn't just transition between states — it *moves* between them in a way that communicates physics and intent. The wireframe has one animation (`sheetIn` for the Review Access sheet). But what about: checkbox state changes, toast appearance/dismissal, tab switching, inspector opening, sidebar content transitioning between tabs? SwiftUI has excellent spring animation support. A 0.25s spring transition on every state change would make the app feel alive. The spec should define animation curves and durations for each class of transition.

---

## The Review Access Sheet

This is the highest-stakes surface in the app. Let me evaluate it in detail.

### What's good

The "What's Changing" diff section at the top is excellent. It immediately answers: "What am I approving?" before showing the full list. This is the key insight — don't make the user diff the state mentally. Show them the delta.

The agent switcher in the header is correctly positioned — it scopes the entire sheet to one agent at a time.

The footer summary ("225 files · 1,089 emails visible · 158 hidden") is always visible and gives a running total. This is good feedback design.

### What needs work

**The sheet is too flat.** Every section (What's Changing, Files, Emails, Advanced) has equal visual weight. The "What's Changing" section should be the most prominent — it's the thing you're actually deciding on. Consider giving it a tinted background (light green for additions, light red for removals) to distinguish it from the full list below.

**The Advanced disclosure is labeled "Session notes, timeout, preset."** This is a v2 holdover. In a standing access model, "session notes" doesn't make sense. This label should say "Work block options" and only appear when the user is starting a work block. For a regular access review, there's nothing "advanced" to show.

**The primary button says "Allow Access →" but there's no secondary CTA for "Start Work Block →."** The spec says both should be present: "Allow Access" and "Start Work Block" as an alternative. The wireframe only shows one button. This matters because the user's intent may be ambiguous — are they granting standing access or starting a tracked block? Both CTAs should be visible, with "Allow Access" as primary and "Start Work Block" as secondary.

**The sheet doesn't show what will NOT change.** If the user already has 2 sources granted and is adding a third, the "What's Changing" section should show "+ Adding assets" but the Files section should also show the existing grants with a visual indicator (e.g., lighter text, a "current" label) so the user understands the full picture, not just the delta. Currently, the sheet shows everything as checkboxes, making it unclear what's new vs. existing.

---

## Specific Bugs and Inconsistencies

1. **Files mode CSS bug**: `style="display:none;flex:1;display:none;flex-direction:column"` — the `display` property is set twice. The second value overwrites the first when toggled to visible, but this is fragile and confusing.

2. **Domain table grid columns don't account for the Note column width.** The grid is `24px 1fr 90px 70px 70px 60px 60px 80px`. The domain name gets `1fr` but `@bankofamerica.com` is long. On narrow windows, this will clip. Consider making the grid responsive or allowing the domain column to wrap.

3. **The hidden domains separator uses `grid-column: 2/-1`** but it's inside a grid row with 8 columns. This will render correctly but it's semantically wrong — it should be a separate element outside the grid, or a full-width row.

4. **The toast undo link color is `var(--accent-bg)` (light blue on dark background)**. This is readable but looks washed out. Use white or a bright blue (#5ba3f5) for better contrast.

5. **The Overview sidebar duplicates agent connection info** that's already in the top bar. The top bar shows "● Claude · ● Codex". The sidebar shows the same dots with "connected" badges. This is not harmful but it's redundant real estate. Consider: sidebar shows agents with their access summary, not their connection state (which is already globally visible in the top bar).

---

## Priority Recommendations

### 1. Remove the Sources/Files and Domains/Messages view toggles
Let the sidebar be the mode switch. Clicking a source in the sidebar shows its files. Clicking "All Sources" or having nothing selected shows the Sources overview table. Same for Emails. This eliminates a layer of indirection and follows Finder's pattern. **This is the single highest-impact change.**

### 2. Simplify the Overview agent cards
Cut them to: agent name + connection + pause, one-line files summary, one-line emails summary, work block status (only when active), single "Review Access" button. Move activity out of the card and into the Activity drawer. The card should be a badge, not a dashboard. **This reduces cognitive load on the most-visited screen.**

### 3. Add visual consequence to checkbox interactions
When a source is checked for an agent, tint the row. When unchecked, return to neutral. The checkbox state change should be visible at the row level, not just the 16×16 checkbox. **This makes the trust boundary viscerally visible, not just informationally visible.**

### 4. Design all empty states
First launch, no sources, no emails, no access granted, no work blocks — each needs a designed state that communicates value and guides the user forward. **These are the states real users encounter first.**

### 5. Kill the "Future" column — merge the concept
The Archived/Future dual-column model is informationally honest but UX-hostile. Replace with: email count per domain, plus a small "＋ future" indicator on active domains. The checkbox already communicates the policy; the count communicates the scope. **Two columns become zero columns, and clarity improves.**

### 6. Move sensitivity out of the sidebar and into the Domains table header
Sensitivity is an access control, not a navigation element. It should live with the data it governs. Place it above the agent checkbox columns: "Claude: Moderate ▼ | Codex: Strict ▼" as table-header dropdowns. **This follows the "access controls live where the data lives" principle from your own spec.**

### 7. Specify the animation language
Define transition curves and durations for: tab switches (0.2s ease), sidebar content changes (0.15s crossfade), checkbox state changes (0.1s spring), inspector open/close (0.25s spring), sheet present/dismiss (0.3s spring), toast appear/dismiss (0.2s ease-in, 0.15s ease-out). **A macOS app without animation feels broken.** SwiftUI's `.animation(.spring(duration: 0.25))` makes this trivial.

---

## What the v2 → v4 Transition Got Right

It's worth pausing to name what's genuinely good, because the structural decisions in v4 are stronger than most first-pass redesigns I've seen:

**Standing access replaces session ceremony.** This aligns with how the target agents actually work. It removes fake friction (starting a session) and replaces it with real friction (the first-grant review sheet). Cooper calls this "designing for intermediates" — the daily user doesn't need a ceremony, but the consequential moment gets the deliberation it deserves.

**The Intentionality Rule is the product's taste.** Most access-control UIs treat grant and revoke symmetrically. Manifold doesn't. It recognizes that granting is dangerous and revoking is safe, and it applies proportional friction. This is a design principle, not just a feature, and it should be stated prominently in the app itself (perhaps in the onboarding flow: "Granting access is deliberate. Removing it is instant.").

**Files and Emails as ownership surfaces.** The critique of v2 was that these tabs felt like data browsers. In v4, they're access control surfaces with agent checkbox columns. The data and the control are unified. This is the right call — you don't go to a separate "permissions" screen to change what Claude sees. You go to Files and check the box.

**Work blocks as opt-in.** Not every interaction with an AI needs snapshot/rollback. Making this opt-in instead of the default mode reduces daily friction to near-zero while preserving the safety net for high-stakes work. This is the kind of decision that shows deep product thinking about actual user behavior.

---

## Books Referenced in This Critique

- **Don't Make Me Think** (Steve Krug) — Principle: if users have to stop and think about how something works, the design has failed. Applied to: view toggle confusion, "Future" column labeling, empty states.
- **About Face** (Alan Cooper) — Principles: commensurate effort, designing for intermediates, mental model matching. Applied to: the Intentionality Rule evaluation, sidebar identity crisis.
- **Designing Interfaces** (Jenifer Tidwell) — Patterns: navigation patterns, mode-switching, progressive disclosure. Applied to: sidebar-as-mode-switch, view toggles.
- **Refactoring UI** (Adam Wathan & Steve Schoger) — Principles: typography scale ratios, visual hierarchy through size, color-as-information. Applied to: typography monotony, row tinting recommendation.
- **The Visual Display of Quantitative Information** (Edward Tufte) — Principles: data-ink ratio, smallest effective difference, chartjunk. Applied to: Domains table column count, Overview card density, "No active work block" zero-state.
- **Dieter Rams: 10 Principles of Good Design** — "Good design is as little design as possible." Applied to: simplifying the Overview cards, removing redundant columns, killing view toggles.
- **Apple HIG (macOS)** — Patterns: NavigationSplitView, sidebar navigation, sheet presentation, segmented controls, animation curves. Applied to: sidebar role, sheet design, animation language.
- **LoveFrom / Jony Ive** — Philosophy: care as signal, the invisible details communicate trustworthiness. Applied to: the emotional register evaluation, Pause button weight, animation language, the "why" explanation in the Inspector.
