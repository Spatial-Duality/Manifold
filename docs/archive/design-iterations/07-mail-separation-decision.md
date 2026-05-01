# Manifold UI — Stage 7: Mail separation decision

## The question

After everything — Stages 1 through 6, the default + session model, the reload primitive — should mail selection be a **top-level sidebar surface** separate from file access, or should it stay folded into a unified Access view?

## Short answer

**Separate. Mail becomes its own top-level sidebar item.** The unified matrix I argued for in Stage 3 and partially defended in Stage 5 doesn't survive the weight that sessions and per-message selection put on the email primitive. Flipping the earlier call.

## What the evolution has revealed

Three things shifted the calculation since Stage 3.

**1. Sessions made selection a frequent task, not a one-time setup.** In the Stage 3 model, email scope was set once and rarely revisited — the per-mailbox inspector with a rule editor was adequate for a rarely-used surface. In the Stage 6 model, users start *Jane follow-up* sessions as a normal working rhythm, and each session may involve picking specific messages. A surface that's invoked often has different ergonomic requirements from one invoked rarely. The mailbox inspector buried inside Access is three surfaces deep; for a frequent task, that's wrong.

**2. Per-message selection is mail-shaped, not file-shaped.** My Stage 5 design added a "Messages" tab to the mailbox inspector with a checkbox list. That's the right primitive but the wrong container. Real mail selection needs: search-first navigation (by sender, by subject, by thread), sender pivot ("show me everything from Jane"), threading (messages come in conversations), label/folder views, date slicing. This is a mail client's whole surface area, not a drawer inside a file-access matrix. Compressing it into an inspector sacrifices the affordances users need.

**3. The reload primitive depends on session construction being fast.** If the second-time flow is three clicks / five seconds (Stage 6), the *first-time* flow has to be cheap enough that users feel free to start sessions. When email selection costs four navigation steps (menu bar → Ledger → Access → click mailbow → switch inspector tab → search → pick), first-session cost is high enough to discourage starting sessions at all. That silently kills the session primitive.

The unified matrix was right for the scope I first imagined (durable, folder-shaped, rarely-edited). It's wrong for the scope Manifold actually wants (session-first, message-grained, frequently-constructed).

## The decision

**Sidebar nav: Activity · Access · Mail · Requests · Rules.**

- **Activity** — events (reads, writes, denials, searches, reverts), grouped by session.
- **Access** — folder sources, their contents via file tree, their exclusion rules.
- **Mail** — mailbox sources, message-grained selection, per-sender/thread/label pivots, sensitivity levels.
- **Requests** — pending approvals queue.
- **Rules** — global policies (split by domain as before: Email · Files · Agents).

Five items. Three are daily-frequent (Activity, Access, Mail). Requests hides when empty. Rules is infrequent-after-setup.

Sessions remain folded — they appear as **chips and tabs** inside Activity, Access, and Mail rather than as a sidebar item. That was the Stage 6 preference and it stands; adding a sixth sidebar item would cost more than the clarity it'd buy.

## Why, in five sentences

Email and files are different primitives with different selection grammars. Sessions make email selection a frequent task. Frequent tasks deserve first-class real estate. Rules are already split by domain, which is the product admitting the primitives differ. Forcing the selection UIs to share a surface costs affordance depth on both sides and buys nothing users asked for.

## What this unlocks in Mail

The dedicated surface can finally do what mail clients do, minus the reading — because Manifold isn't a mail reader, it's a *"what should the agent see from mail"* surface. Concrete affordances:

**Top-level tabs inside Mail:** *Default · Session · All messages*
- Default: the persistent baseline — which mailboxes are shared, at what sensitivity, with which rules.
- Session: live only when a session is active — shows additions/subtractions against default for this session.
- All messages: the full searchable index across connected mailboxes, for picking.

**Primary affordances in "All messages":**
- Search bar — sender, subject, body, label. First-class.
- Sender pivot — left rail lists top senders by recent volume; click Jane, see Jane's thread. Fast path for "last few messages from contact X."
- Thread view — messages grouped by conversation. Picking a thread picks the whole thread (one checkbox, many messages); expand to pick individual messages.
- Date slicer — last 7 days, last 30, custom range.
- Per-message checkbox with state indicator: *shared (default), shared (session), not shared, excluded by rule*.

**Right inspector** (like Access) — when a mailbox is selected in Default, shows sensitivity level, rules, counts, live preview of what the agent sees.

**Sensitivity, still three levels:** Subjects only · Trusted senders · Full content. Unchanged from Stage 5 — correct grammar.

## What this means for the "last few emails from Jane" flow

Under this split, with a live session:

| Step | Action | Time |
|---|---|---|
| 1 | ⌘-click menu bar → Start session, pick defaults, ⏎ | ~3s |
| 2 | Manifold opens on Mail tab with session active | ~0s |
| 3 | Click Jane in the sender rail | ~1s |
| 4 | Select the 5 most recent messages | ~3s |

**4 steps, ~7 seconds.** Faster than the Stage 6 flow (8 steps, ~13s) because the selection surface is where the selection happens instead of four navigation steps away. Still ~5 seconds on reload.

That 6-second difference per invocation is multiplicative over daily use. It's the difference between sessions being a first-class habit and sessions being a theoretical feature.

## Cross-domain glance — still handled

The one thing the unified matrix did well is now handled elsewhere:

- **Menu bar panel header** answers the cross-domain safety question in one sentence: *"You've shared 4 folders and 1 mailbox with Claude."* That was already the spec.
- **Activity view filter chips** let you scope events to Files only / Mail only / both.
- **Rules view** keeps a *"Applies to: folders, mailboxes, or both"* column.

No place the user asks *"across everything, what does Claude see?"* and doesn't get a clear answer. The unified matrix was one way to answer it; the one-sentence header is a better way for a trust product.

## What this rules out

- A single Access matrix with folders and mailboxes as peer rows — gone.
- "Add source" as a polymorphic command — gone. *Add folder…* and *Add mailbox…* live in Access and Mail respectively.
- Mailbox selection as a drawer-inside-an-inspector — gone. Mail is its own surface.

## What this keeps

- The session primitive and its reload behavior.
- The Default ∪ Session − Subtractions model for both files and mail.
- The Rules view's tabbed structure (Email / Files / Agents).
- The user-as-subject status copy.
- The fixed agent palette and the 4pt/8pt grid.
- The Activity view's three-pane shape with sparklines.

None of the load-bearing design decisions from Stages 2 and 6 change.

## What I was wrong about earlier

Stage 3 claimed one primitive (scope) covered both folders and mailboxes. It doesn't — they share a job, not a model. Stage 5 partially backed off (split inspectors, kept unified matrix), but that compromise treats the cross-domain glance as primary when it's actually secondary. Stage 7 fully resolves: **two surfaces, two selection grammars, one coherent mental model (default + session) across both.**

Said bluntly: the reason I kept insisting on one surface was that it looked cleaner in a mockup. That's a designer-ego reason. The Stage 6 session model made the cost of that tidiness legible, and the answer is now clear.

## Book check — short

- **Alexander (APL, NSF):** Two primitives, two names, two surfaces. Matches Alexander's method — let the forces name the pattern rather than collapsing them for symmetry.
- **Cooper (AF):** Separate surfaces let each match its own native posture. Mail is higher-frequency transient; Access is sovereign-ish (rarely edited baseline).
- **Raskin (THI):** The cost of modality (hunt-and-peck between inspector tabs) goes down when selection lives in a surface shaped for selection. Fewer modes in practice.
- **Tidwell (DI):** Domain-specific master-detail is a stronger pattern than polymorphic master-detail when the details diverge. Confirms split.
- **Cranor/Garfinkel (S&U):** Selection under time pressure (session start) benefits from the cheapest possible affordance path. Sender pivot + search + threading = that path for mail.

No book on the list argues against the split once sessions are in the model.

## What to update

1. **03-surface-redesign.md § D** — rewrite Access to be folders-only; add new § D2 for Mail.
2. **04-visual-spec.html + 05-visual-spec-updates.html** — update sidebar nav from four items to five; add a Mail mockup (sender rail, message list, per-message checkboxes, session tab).
3. **06-sessions-and-defaults.md** — update the "Jane follow-up" walkthrough to use the Mail surface directly instead of Access → mailbox → inspector.
4. **Strings catalog** — add mail-specific microcopy (sender labels, thread phrasing, *"Share this thread with Claude for this session"* etc.).

Stage 8, if wanted: update the HTML spec to show the Mail surface end-to-end with the sender rail and message picker live. This is probably the last visual pass before engineering.

## The honest summary

Your question forced the right answer. The session model created a frequency of email-selection that the folded matrix couldn't carry. Separating Mail gives message-grained selection the affordance depth it needs, without costing the cross-domain audit story (handled elsewhere). Five sidebar items, three daily-frequent, each shaped for its primitives. The design is finally coherent.
