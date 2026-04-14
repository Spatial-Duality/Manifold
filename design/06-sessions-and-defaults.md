# Manifold UI — Stage 6: Default access + Session access

Amar's Stage 5 review corrected two things.

1. The Mail.app share extension is a **v2 convenience**, not the primary path. The open-source app must answer every meaningful access flow in-app, without depending on platform-specific extensions.
2. The real primitive I missed is a **two-tier access model**: a persistent **Default** baseline, and a transient **Session** overlay on top of it. The user can add or remove items (single or bulk), set a duration, and optionally base the session on the default or start blank.

This is materially better than anything in Stages 1–5. It fixes gaps in the approval flow, the tracked-work concept, the Activity view, and the microcopy. This doc names the primitives, reviews the idea against the reading list, specifies the flows, and rewalks the "last few emails from Jane" scenario under the new model.

---

## The two primitives

### Default (persistent)

The durable baseline of what agents can see. Survives restarts, user logout, and agent reconnects. Edited in the Access view. Represented by a single sentence in the menu bar: *"You've shared 4 folders and 1 mailbox with Claude by default."*

### Session (transient)

A **named, time-bounded overlay** on top of the default. Can add items the default doesn't include (expanding scope for a specific task) or remove items the default does include (contracting scope for sensitive work). Agents see the **union of default + additions, minus subtractions**, only while the session is live.

**Lifecycle.**
- Named at start (*"Jane follow-up"*, *"Writing sprint"*, *"Board prep"*). Name is load-bearing — it appears in the menu bar, in every Activity row during the session, and in every approval card.
- Time-bounded: 30m / 1h / 2h / 4h / until I sign out. Default offered: **2h**. Hard cap: 8h.
- Auto-expires on timer, on machine sleep > 10m, on explicit Finish.
- Can be saved as a reusable **preset**: *"Save this session as a preset…"* → next time it's a one-click start.

**Session start options — three.**
1. **Start from default** — baseline + additions. The common case.
2. **Start blank** — nothing shared, add what you need. The conservative case.
3. **Start from default minus…** — baseline with subtractions. Privacy-focused case ("I'm on a call, reduce what Claude sees").

**All three exist because the right default depends on the task.** Forcing one choice is a Thaler-Sunstein mistake — see audit below.

**Writes in a session.** A session can have **tracking on** (every write snapshotted + revertable — the current Stage 3 "work block" concept) or **tracking off**. Tracked sessions are the default for any session that grants write access. Read-only sessions can skip tracking overhead.

**This renames and absorbs two concepts I had in earlier stages:**
- "Work block" → a session with tracking on + writes allowed.
- "Transient sharing" → a session with specific additions.

The primitive was hidden inside two different feature names. It should be one primitive, *Session*, with modifiers.

---

## Book audit — does this model hold up?

The user asked to review this against the books. Honest audit; each line is the test the book applies and whether the model passes.

**Raskin — *The Humane Interface*.** Modes are harmful when hidden. A session is an *explicit, named, time-bounded* mode the user invoked, and its boundary is always visible (menu bar chip, session name on every agent action, countdown). That is the exception Raskin allows — a *quasimode* the user holds in their mind because the UI holds it for them. **Passes.**

**Norman — *The Design of Everyday Things*.** Requires a clean conceptual model. The default/session split maps to a metaphor users already have: *the stuff on my desk* (default) vs *what I pulled out for today* (session). Nothing new to learn. **Passes strongly** — this is the kind of mental-model win Norman is about.

**Cooper — *About Face*.** Postures. Default is *daemonic* (runs in the background, always available). Session is *transient* (pull up, work, close). The split gives each posture a surface of its own instead of cramming both into one UI. **Passes; strengthens the Stage 2 posture call.**

**Thaler & Sunstein — *Nudge*.** Defaults carry moral weight. Which session-start option is the default is a real design decision:
- *Start from default* is convenient but leaks baseline into more contexts.
- *Start blank* is conservative but costs a click per item the user always uses.
- *Start from default minus…* is for the informed user scoping down.

Recommendation: **"Start from default" is the selected option, but "Start blank" is a sibling button of equal visual weight, not hidden in a menu.** Both are one click from the session-start sheet. This is the Thaler-Sunstein pattern: make the choice visible rather than nudging hard. **Passes with this explicit rule.**

**Whitten & Tygar — "Why Johnny Can't Encrypt."** Users satisfice on permission dialogs. The session model *reduces the dialog surface area* by letting users front-load a batch of access choices at session start, rather than one-by-one as the agent asks. Plus the session has a visible expiration, so there's no "I approved this months ago and forgot." **Passes.**

**Cranor & Garfinkel — *Security and Usability*.** The research literature here is clear: time-bounded, user-invoked, batch-authorized access beats either *always on* or *case-by-case modal*. The two-tier model is exactly that pattern. **Passes.**

**Alexander — *A Pattern Language* / *Notes on the Synthesis of Form*.** Name the primitive. *Session* was the primitive the product wanted and didn't have. Work-block was a special case; transient-share was a special case; they're the same thing. **Passes — this is the kind of synthesis Alexander's method produces.**

**Ink & Switch — *Local-first software*, *Capstone*.** History as first-class, user ownership of state, composability. Named sessions that can be saved as presets, recalled, and whose audit trails persist forever are a Capstone-shaped primitive. **Passes; actively endorses this.**

**Bret Victor — "Magic Ink" / "Inventing on Principle."** Every abstraction should be a handle. A session is a *thing* — a chip in the menu bar, a row in the Activity sidebar rail, a filter on the Activity table. Clickable, editable, extendable, revocable. **Passes.**

**Tufte — *Beautiful Evidence* / *Envisioning Information*.** Sessions give the Activity view a natural grouping for small multiples and sparklines. Every session is a unit of evidence. **Passes; improves the ledger surface.**

**Tidwell — *Designing Interfaces*.** The pattern here is *Configurable Preset + Overlay*. Well-understood, used in dev tools (e.g., tmux layouts, Chrome profiles, IDE workspaces). **Passes; inherits existing user fluency.**

**Jarrett & Gaffney — *Forms That Work*.** Starting a session is a form. Short one: name (auto-suggested), duration (one click), base (three radio options), tracking (default on if writing). Total: ~15 seconds to start a session. **Passes.**

**Few — *Information Dashboard Design*.** The menu bar panel needs a single load-bearing sentence. A session chip fits: *"Session: Jane follow-up — 1h 42m left."* Peripheral-vision legible. **Passes.**

**Weinschenk — *100 Things Every Designer Needs to Know*.** Cognitive load. A session is extra state, so it costs load. Mitigations: auto-suggested name, countdown always visible, auto-expire, named presets for recurring cases. The cost is real but bounded; the alternative (scattered work-block / transient-share / approval-modal concepts) costs more. **Passes with the mitigations.**

**Hooked — (deliberately excluded from the list).** Am I inadvertently building a habit loop? No. Sessions expire. There's no reward for opening them repeatedly. They're invoked for a task and dissolve. **Passes the ethical-product test.**

**Yifrah / Podmajersky / Nicely Said — microcopy.** Session naming is a place language matters. *"Start a session"* is good English; *"Start transient scope overlay"* is what an engineer would write. Tone for sessions: calm, task-oriented, user-as-subject. *"You started Jane follow-up at 2:04. 5 extra messages shared with Claude. Ends in 1h 42m."* **Passes with attention.**

**Net — the two-tier model survives every book on the list that applies.** It makes several of them happier (Alexander, Ink & Switch, Tufte, Cooper, Norman). It requires explicit care on one dimension (Thaler-Sunstein — don't hide the blank-start option). The Hooked check matters more than it looks: sessions must expire.

---

## Where this changes the Stage 3 surfaces

Nearly everywhere. Summarized:

**Menu bar panel.** Gains a **session chip** at the top when a session is live, pushing the header sentence down by one row. Chip shows session name, remaining time, and a Finish button. Starting a session is a prominent affordance when no session is live.

**Access view.** Gains a view toggle: **Default · Session**. Default tab shows the persistent baseline (what Stage 5 showed). Session tab — visible only when a session is live — shows additions/subtractions against default, in a diff-shaped view. Editing the default never affects a live session; editing a session doesn't touch the default. Clean separation.

**Activity view.** Every event is now labeled with the session that enclosed it (or *"default"* if no session was active). A new filter chip: **Session**, which groups by session and shows session boundaries as visible dividers with sparklines (Tufte's small multiples come for free).

**Requests view.** Incoming approval requests can be answered with three modifiers instead of two:
- **Not this time** (focused default)
- **Allow once** (this specific event only — implicit session-of-one)
- **Add to current session** (for the duration of the live session only)
- **Add to default** (persistent — was Stage 3's "Allow and add to scope")

The extra option disappears when no session is live; *"Add to current session"* becomes unavailable rather than confusing.

**Rules view.** Unchanged at the top level, but gains a **Session rules** tab: default rules that apply whenever a new session starts blank (so *"never `.env`"* still applies even in a blank session).

---

## The "last few emails from Jane" scenario, rewalked

Under the two-tier model, entirely in-app, no Mail.app extension.

| Step | Action | Screen | Time |
|---|---|---|---|
| 1 | Click menu bar icon | Menu bar panel | ~1s |
| 2 | Click **Start session…** | Session-start sheet (short form) | ~1s |
| 3 | Accept auto-suggested name *"Jane follow-up"* (or type); leave duration at 2h; pick base = **Start from default** | Same sheet | ~3s |
| 4 | Click **Start & add items…** | Access view, Session tab, empty additions | ~1s |
| 5 | In the Mailboxes inspector pane, click **Add messages…** | Message picker modeless panel — mailbox-aware, search, per-message checkboxes | ~1s |
| 6 | Type `jane@acme.com` in search | Panel filters to Jane | ~2s |
| 7 | Check the 5 most recent rows | Live count updates: *"5 messages added to session"* | ~3s |
| 8 | Close panel (Esc or click away) | Session is live; menu bar chip appears | ~1s |

**8 steps, ~13 seconds, 3 screens** (menu bar panel → session-start sheet → Access/session/message-picker). All in-app.

Compare Stage 5 flows:
- Via Manifold app, rule workaround: ~12s, 5 screens, bait-and-switch on intent
- Via Manifold app, proposed Messages tab (no sessions): ~10s, 5 screens, but this was durable-only and polluted the default
- Via Mail.app share extension: ~4s, but v2, not open-source, platform-specific

The session-based flow is slightly longer than the share-extension idea (13s vs 4s) but it **matches the user's intent** (this is a transient working slice with an expiration), it's **in-app** (no platform extension needed), and the time cost is front-loaded to session start, not repeated per-item.

**The killer property** is that once the session is live, adding more items is cheap — click mailbox, check more messages, items join the session. Removing items is direct: uncheck. The friction is spent at the right moment (deciding to start a session) rather than repeated per action.

---

## Session start sheet — form design

Short, per Jarrett & Gaffney. Five fields, only three require user input.

```
┌─ Start a session ────────────────────────────────────────┐
│                                                          │
│  Name                                                    │
│  ┌──────────────────────────────────────────────┐        │
│  │ Jane follow-up                               │        │
│  └──────────────────────────────────────────────┘        │
│  Used in menu bar, Activity, and approvals.             │
│                                                          │
│  Duration                                                │
│  ( ) 30m   (•) 2h   ( ) 4h   ( ) Until I sign out        │
│                                                          │
│  Start with                                              │
│  (•) Your default access (4 folders, 1 mailbox)         │
│  ( ) Nothing — start blank                               │
│  ( ) Default minus…                                      │
│                                                          │
│  Agents                                                  │
│  [✓] Claude       [ ] Codex                              │
│                                                          │
│  [✓] Track writes (snapshot + revert)                   │
│                                                          │
│                                                          │
│              [ Cancel ]    [ Start session ]             │
└──────────────────────────────────────────────────────────┘
```

**Keyboard path:** ⌘N from menu bar → sheet opens → Return accepts defaults. A seasoned user starts a default-cloned 2h session in 2 seconds.

---

## Why this is better than what Stage 3 had

Four concrete gains:

1. **One primitive replaces three muddled ones.** Work-block, transient-share, and one-time-approval all become *Session* with modifiers. Users learn one concept; the codebase has one lifecycle.

2. **Approval flow becomes coherent.** *"Allow for this session only"* is a first-class answer that didn't exist before, and it's the honest answer to most *"just this once"* user intent.

3. **The Activity view becomes more legible.** Sessions are natural units of evidence. Every row has a session label. Sparklines per session come for free. Tufte finally wins this surface.

4. **Defaults stay sacred.** Per Principle 3, the baseline should be small and deliberate. Sessions let users expand for tasks without polluting the baseline with ad-hoc additions that accumulate into "why does Claude have access to 47 folders?"

---

## Mail.app share extension — correctly repositioned

**v2, not v1.** Reasons now clear:
- The in-app session flow handles the primary case in ~13 seconds end-to-end.
- The share extension is a *convenience* that shaves ~9 seconds for users already in Mail.app.
- Open-source version must work without it.
- Building it requires an AppKit Share extension target, which is macOS-specific surface area that doesn't earn its complexity until the core flow is proven.

**What to do now:** ship the session model. Ship the in-app flow. Ship with a stub in the README: *"A Mail.app share extension is on the roadmap. Until then, the in-app session flow handles this in under 15 seconds."*

That's the honest positioning.

---

## What I was wrong about in Stages 3–5

Three things, said plainly.

1. **I treated the Mail extension as primary.** It isn't. It's a keystroke optimization on a flow that needs to exist in-app first. An open-source project can't ship with its fastest path locked behind platform surfaces. Your correction is right.

2. **I treated "transient sharing" as a feature when it's a primitive.** Renaming it to *Session* and giving it the same status as *Default* unlocks coherence across approvals, tracked writes, Activity grouping, and microcopy. My earlier docs were three separate half-designs; this is one design.

3. **I was flirting with session-as-mode without earning it.** Raskin's ghost was flagging me. The two-tier model passes Raskin's own exception (named, visible, user-invoked, bounded) — but only because Default is always visible and Session is always labeled. That discipline is now explicit.

---

## What ships

Concretely, the delta against Stage 5:

1. Session primitive in the model layer (`PolicyModel` extension)
2. Session-start sheet
3. Session chip in menu bar panel + Access view + Activity view
4. Access view view-toggle: **Default · Session**
5. Message picker panel (mailbox inspector)
6. Folder/file picker panel (folder inspector) — same pattern for files
7. Approval card gains the *"Add to current session"* option when a session is live
8. Session presets (save/load named sessions) — could be a v1.1 follow-on
9. Microcopy pass: session naming conventions, session-labeled status sentences

Mail.app share extension explicitly deferred to v2.

Stage 7, if wanted: update HTML visual spec to show session chip, session-start sheet, and Access/Session tab.

---

## Addendum — every session is reloadable

**The rule.** When a session ends (timer, manual finish, or auto-expire), its configuration persists. Any past session can be **reloaded** — a new live session spins up with the same name, same additions/subtractions, same agents, same tracking setting. Only duration is re-asked.

This collapses a distinction I was drawing between *presets* and *history*. They're the same thing: every session is implicitly a preset. The user doesn't have to remember to *save as preset*. If they used it once and want it again, it's there.

**Where reload lives.**

1. **Menu bar panel, when no session is live.** A row under "Start session…" — *"Recent: Jane follow-up · Writing sprint · Board prep."* One-click resume.
2. **Session-start sheet.** Instead of filling the form blank, pick from a list of recent sessions and edit before starting.
3. **Activity view.** Every session row has a *Resume* action in its context menu. The fastest path if you were looking at the session's history and want it again.
4. **Dedicated Sessions list.** Accessible from Access view sidebar or a ⌘-shortcut — full history, searchable, with columns for last-used, times-used, duration, additions count. Users who run the same few sessions repeatedly pin them here.

**Naming and collisions.** Reloading *Jane follow-up* starts a new session also called *Jane follow-up*. The old and new are distinct entities in the Activity audit trail (separate timestamps, separate IDs). No numeric suffixes in the UI — that's engineering noise. The Activity view distinguishes them by start time.

**Handling drift between reload-time and original-time.**

Reload is almost never a pure replay. Between original and reload:
- The user's default may have changed.
- Files in the session's additions may have been moved or deleted.
- Agents may have been added or removed.
- Global rules may have changed what's allowed.

The honest behavior: **apply additions/subtractions against the *current* default, and show a diff preview before starting.** The session-start sheet, when reloading, shows:

```
┌─ Resume: Jane follow-up ─────────────────────────────────┐
│                                                          │
│  Original session: Apr 10, 2h · 5 messages added         │
│                                                          │
│  What's different now                                    │
│  • 4 of 5 original messages still exist                  │
│  • 1 message no longer in mailbox (deleted)              │
│  • Default now includes 2 extra folders (since Apr 10)  │
│                                                          │
│  Duration                                                │
│  ( ) 30m   (•) 2h   ( ) 4h   ( ) Until I sign out        │
│                                                          │
│              [ Cancel ]    [ Resume session ]            │
└──────────────────────────────────────────────────────────┘
```

No surprises. The user sees exactly what will be shared before committing. Principle 10 (honesty outranks confidence) + Bret Victor (show the effect before the action).

**Book check — quick.**

- **Ink & Switch — Capstone / Local-first.** Reloadable state with diff-against-now is exactly the shape Capstone argues for. Users own their working states as first-class persistent things. **Strongly reinforces the move.**
- **Raskin.** Reload isn't a mode; it's a named, bounded, explicit invocation. Same pass as the original Session concept.
- **Thaler-Sunstein.** The reload flow defaults to *current* default + original overlay, which is honest. It doesn't default to *snapshot* default, which would be surprising. Right default.
- **Norman.** The diff preview installs a clear mental model — "I'm starting this same thing again, and here's how the world has changed since." Users don't have to build this model themselves.

**What this removes from the Stage 6 design above.**

The "Save as preset" action at session end is no longer needed. All sessions are automatically recallable. Simpler affordance surface.

**What this adds.**

- A **Sessions** sidebar item in the Ledger/Activity window (or a section within Access) listing every past session with reload affordance. Five items in the nav rail now: Activity · Access · Requests · Rules · Sessions. Acceptable — Sessions is a distinct object type, not a view of another object.
  - *Alternative:* fold Sessions into a tab within Access (Default · Session · History). Keeps the nav at four items. My preference is the folded version; it keeps session management adjacent to the default it overlays.
- An "origin session" field on every session: *"Resumed from Apr 10 / Jane follow-up."* The audit trail threads across reloads so a user can see every time a given session was used.

**What this means for the "Jane follow-up" scenario the second time.**

| Step | Action | Time |
|---|---|---|
| 1 | Click menu bar icon | ~1s |
| 2 | Click *Recent: Jane follow-up* | ~1s |
| 3 | Accept duration, review 2-line drift diff, click **Resume** | ~3s |

**3 steps, ~5 seconds.** Near the Mail.app share-extension speed, without the platform dependency. This is the payoff of the reload primitive: the second, third, and nth times a user does the same task, it costs almost nothing.

---

## Net, after your three corrections

The Access model that ships:

1. **Default** — persistent baseline, edited deliberately, small by design.
2. **Session** — named, bounded, layered overlay (add + subtract) for a specific task.
3. **Reload** — every session persists as a recallable thing; the second time is three clicks.

Three primitives, one nav structure, one audit trail, honest microcopy throughout. Everything else in the app — approval flow, activity view, microcopy, menu bar — reshapes around these.

That's the design.

