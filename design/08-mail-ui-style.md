# Manifold UI — Stage 8: Mail UI style

## The question

Should the Mail surface look more like **Synology Active Backup** (dense selection / operator-posture tool) or **Apple Mail** (three-pane reading-first mail client)?

## Short answer

**Active Backup style wins decisively.** Every book on the list that applies points the same direction. The only things worth borrowing from Apple Mail are *mail-aware row content* (subject-first strings, thread collapse, sender identity) — not its posture, reading pane, or chrome. Your original instinct was right; the reading list strengthens it.

---

## Why the question is not really about aesthetics

The register of a UI signals the task. If the Mail tab looks like a mail client, users will read, triage, maybe try to reply. If it looks like a selection operator, users will curate what an agent can see. These are different jobs, and Manifold's job is the second one.

The question *"which reference?"* is really the question *"what is the user doing on this surface?"* Get that right and the style follows.

The user on this surface is:
- **Selecting** messages or threads, singly or in bulk
- **Evaluating** whether a selection is over- or under-reaching, via a running count and live preview of agent-visible result
- **Authoring or adjusting rules** that shape the selection
- **Never** reading messages for comprehension, replying, composing, organizing, or triaging for their own inbox

Every item on that list is backup/operator work. Nothing on it is mail-client work.

---

## The books audit

**Cooper — *About Face*.** Postures. Apple Mail is *sovereign reading-first*; Active Backup is *transient operator*. Manifold's Mail surface is invoked from within the Ledger window (itself transient). Its job is set-a-state-and-leave. Active Backup's posture matches; Apple Mail's doesn't.

**Norman — *The Design of Everyday Things*.** The UI is a signifier. A three-pane reading layout signifies *"read here."* A dense table-with-checkboxes signifies *"select here."* The design must signify the job. Norman backs Active Backup.

**Raskin — *The Humane Interface*.** Modelessness. Apple Mail has a reading mode (focused reader, different chrome). Manifold's Mail has no reading mode — there's nothing to read for. Adding a reading pane creates a mode the product doesn't need. Active Backup has no reading mode.

**Tufte — *Envisioning Information*, *Beautiful Evidence*.** Data-ink ratio. For selection across thousands of messages, density is earned. Active Backup's dense tables beat Apple Mail's big reading pane. Tufte also requires *legibility inside density* — which means Manifold's Mail needs subject-visible, sender-visible rows, not filename-style strings. This is where mail-native row content enters.

**Few — *Information Dashboard Design*, *Now You See It*.** At-a-glance metrics. Active Backup's *"X of Y items selected, Z GB"* meter is the pattern. Apple Mail has no comparable primitive because selection isn't its job. Few backs the operator register.

**Bertin — *Semiology of Graphics*.** Position is the strongest visual encoding. Active Backup's left-rail hierarchy (sources → computers → drives → folders) uses position for grouping. Manifold's Mail needs the same — a sender rail uses position to group all of Jane's messages together. Apple Mail flattens this into a date-ordered list, wasting the encoding.

**Ware — *Information Visualization*, *Visual Thinking for Design*.** Pre-attentive cues. Checkboxes, state pills, count meters — pre-attentive for scan. Apple Mail's read/unread dots and reply icons are pre-attentive for a *different* job. Wrong primitives.

**Tidwell — *Designing Interfaces*.** Pattern: *List-with-multi-select + filters + running total*. Active Backup is a canonical implementation. Manifold's Mail is a variant of the same pattern. Apple Mail implements *Master-Detail-Reader* — also canonical, but for a different job.

**Jarrett & Gaffney — *Forms That Work*.** Selection is a form. A form has inputs, validation, a running summary, and a commit action. Active Backup's selection UI is a long, live, autosaved form. Apple Mail isn't a form at all; it's a reader.

**Bret Victor — "Magic Ink."** Information software vs. tool. Apple Mail is both information software (read) and tool (compose). Manifold's Mail is pure tool — it manipulates a state (access policy). Victor's "tools are for doing; information software is for thinking" implies tool-register chrome. Active Backup.

**Ink & Switch — *Local-first software*, *Capstone*.** User-owned state, first-class history. Active Backup's "your backup policy is a persistent, reviewable thing you own" frame is closer than Apple Mail's "your messages are things you browse."

**Weinschenk — *100 Things*.** Cognitive ergonomics. If the UI resembles Mail, users will scan for unread counts, try to open messages, be confused by the missing reading pane. The UI must visually signal "this is not a mail client." Weinschenk backs the operator register.

**Podmajersky, Yifrah, Nicely Said — microcopy.** Copy register differs. *"Include this thread in what Claude sees for this session"* ≠ *"Reply to Jane."* The chrome has to match the copy register.

**Apple HIG.** The interesting tension. HIG says *"use native idioms."* Mail is the native idiom for email on macOS. But HIG is context-sensitive: use the native idiom *for the task*. The native idiom for *selection-with-state* is Finder's multi-select + sidebar, Photos' library grid with selection mode, or System Settings' privacy & security scope pane — none of which are Apple Mail's three-pane reader. HIG, read carefully, supports the Active Backup side.

**The excluded-from-list check — *Hooked*.** Apple Mail's chrome is partly optimized for time-in-app (reading, triaging, replying). A trust product must not inherit engagement chrome. Confirms: don't mimic Mail.

---

## What Active Backup gets right that Manifold's Mail should inherit

1. **Left rail as source hierarchy** — in Manifold: accounts → folders/labels → senders (computed pivot), with counts per node.
2. **Dense center table with multi-state checkboxes** — per-message (or per-thread) row with a tri-state check: *included (default) · included (session) · not included · excluded by rule*. State encoded in both checkbox shape and a small pill on the row.
3. **Running count banner** — always visible: *"3 threads (12 messages) in session · 2 KB metadata visible to Claude."* Few's at-a-glance test.
4. **Rule-editing adjacent to selection** — like Active Backup's filters, live blast-radius preview.
5. **Quiet operator chrome** — toolbar with filters, search, date range; no reading pane; no compose button.
6. **Autosave with visible indicator** — no "save selection" button. The state is the selection.

## What to borrow from Apple Mail (mail-native row content only)

1. **Subject line as the primary string** in a row — not filename or ID. Weighted heavier than sender.
2. **Thread collapse** — one row per conversation by default, expandable. A thread is usually one include/exclude decision; collapsing makes the list navigable at mail volume.
3. **Sender identity cue** — an avatar disc (initials fallback), color-derived-from-email, for pre-attentive chunking. Not full-resolution avatars; a 16pt disc.
4. **Date presented in mail convention** — "Today 4:12 PM" / "Yesterday" / "Mar 10" depending on age, fixed-width right-aligned column.
5. **One-line preview on selection** — not a reading pane. When a thread is selected, the inspector shows subject + first line of latest message, one row tall, for disambiguation. No "open" action.
6. **Conversation participants visible** — when a thread has multiple senders, show *"Jane, Mark + 2 others"* rather than just the most-recent sender.

**What explicitly not to borrow from Apple Mail:**
- Three-pane layout with reading pane.
- Reply / forward / flag / archive affordances.
- Unread-count badges (agents don't have "unread"; the concept doesn't apply).
- Rich reading typography inside the list.
- Signature / compose / draft surfaces.
- Mailbox-as-view metaphor (we're doing access, not reading).

---

## The resulting surface, sketched

```
┌─ Manifold — Mail ────────────────────────────────────────────────────────┐
│ [Default] [Session: Jane follow-up · 1h 42m] [All messages]            │
├─────────────┬───────────────────────────────────────┬───────────────────┤
│ Accounts    │ Search: jane@acme.com            [x] │ Inspector         │
│  • Work ●   │ Date: Last 30 days ▼                  │                   │
│  • Personal │ ─────────────────────────────────────  │ ┌───────────────┐ │
│             │ [✓]  Jane Doe  Board deck v2       ⋯ │ │ Jane · 3 msgs │ │
│ Top senders │      Today 4:12 PM · 3 messages      │ │ Board deck v2 │ │
│  • Jane 47  │ [✓]  Jane Doe  Re: pricing pages   ⋯ │ │               │ │
│  • Mark 28  │      Yesterday · 2 messages          │ │ First line:   │ │
│  • Eng 19   │ [ ]  Jane, Mark + 2  Re: launch    ⋯ │ │ "Sharing the  │ │
│  • …        │      Mar 10 · 5 messages             │ │  revised deck"│ │
│             │ [✓]  Jane Doe  Quick q on specs    ⋯ │ │               │ │
│ Folders     │      Mar 8                           │ │ State:        │ │
│  • Inbox    │ [ ]  Jane Doe  Intro                 │ │  Session only │ │
│  • Sent     │      Feb 28                          │ │               │ │
│  • Archive  │                                      │ │ [ Remove ]    │ │
│             │                                      │ └───────────────┘ │
├─────────────┴───────────────────────────────────────┴───────────────────┤
│ 3 threads (7 messages) in session · subjects + first line visible to   │
│ Claude · 4 threads excluded by rule (from @legal.com)                  │
└──────────────────────────────────────────────────────────────────────────┘
```

Dense. Operator register. No reading pane. Checkbox-per-row. Running count at the bottom. Inspector shows *enough to disambiguate*, not enough to read. This is Active Backup ergonomics with mail-native row content.

---

## Counter-considered: the hybrid

Plausible hybrid: Active Backup skeleton but with a collapsible reading pane for "quick preview to verify before including." I considered it and rejected it.

Reasons:
- A reading pane, even collapsed, invites reading. Users will open it, read messages, lose time. Raskin on modes: adding an optional mode is still adding a mode.
- The verification need is real but small — it's *"is this really the message I meant?"* — which a subject line + first-line preview in the inspector handles in 20% of the chrome of a reading pane.
- Engineering cost: a reading pane requires body rendering, HTML sanitization, inline image policy, link handling. Active Backup-style inspector is just text.
- Trust signaling: the product should be legibly *not a mail client*. Any reading pane, however collapsed, muddles that message.

The inspector-with-first-line pattern is the best compromise — enough for disambiguation, not enough to invite reading.

---

## Second-order reasons this matters

1. **Incentive alignment.** Manifold should not encourage users to spend time in it. A trust product wins when users forget it's running and trust it is. Operator chrome matches that; mail-client chrome invites dwell.

2. **Category clarity.** If the UI looks like Mail, users and reviewers will ask *"why doesn't it reply? why no unread counts? why no drafts?"* — legitimate questions that would cost Manifold credibility. Operator chrome preempts those questions by not promising mail-client features.

3. **Engineering scope.** Apple Mail's UX is the product of 20+ years of engineering on a sovereign app. Approximating it badly is the worst of both worlds. Active Backup's UX is achievable in weeks with a Table + List + filter bar.

4. **Accessibility and keyboard.** An operator table with checkboxes has cleaner keyboard paths than a three-pane reader with focus-shifting. Spacebar toggles selection, arrows navigate, ⌘A selects all in view. Not novel; that's exactly Active Backup.

---

## Net

Active Backup style for the skeleton and posture. Apple Mail style only for the mail-native details that make rows identifiable (subject, sender disc, thread collapse, date convention, participants). No reading pane; inspector shows subject + first line only. The surface is legibly a *selection tool*, not a mail client — and every book on the reading list that applies agrees.

## What to update

- **04/05-visual-spec** — the Mail surface mockup to produce in Stage 9 should follow this style guide.
- **Stage 3 §D2 / Stage 7** — reference this doc as the specification for Mail chrome register.
- **Strings catalog** — mail microcopy in operator register (*"Include thread," "Exclude from session," "In session only"* — not *"Read," "Open," "Mark."*).
- **HIG adherence note** — document that Manifold's Mail uses Finder/System Settings-style multi-select + sidebar as its native-idiom anchor, not Mail.app.

---

## The honest summary

You had the right instinct before the reading. The books didn't change the answer; they compounded the confidence. Mail is a *selection surface for a trust product*, not a client for reading your own correspondence. Every design cue — density, posture, chrome, copy, keyboard, engineering scope — points at Active Backup. Borrow mail-native row content for legibility. Reject mail-client chrome for category clarity.

Stage 9, if wanted: build the Mail surface HTML mockup in the visual spec, following this style guide end-to-end.
