# Manifold UI — Stage 2: Posture and Principles

Stage 1 found the load-bearing problem: Manifold is built as a sovereign app but its job is a daemon's job. Stage 2 resolves the posture question, then derives a small set of principles that govern every downstream decision. Stage 3 applies these to each of the 15 surfaces.

These principles are meant to be argued with. If one of them is wrong, several surface decisions downstream will be wrong. Better to find that out now.

---

## Posture: Manifold is a daemon with two visible surfaces

**The daemon is the product.** The running runtime — `ManifoldRuntime` under `ManifoldAgent`, governed through `ManifoldBridge` — does the work. It watches, scopes, enforces, records, reverts. The daemon has no UI. It has no UI *on purpose*: the user should win by forgetting it's running.

**The menu bar panel is the primary UI.** It is the face of the daemon. It is where ~95% of user contact happens. It answers the only two questions a user ever has about a trust product running in the background: *"is it working?"* and *"what did it just do?"* Apple HIG has been patient about menu bar extras because they know this is the right surface for this kind of product. Cooper's *About Face* chapter 9 calls this **daemonic posture with a transient surface-up**.

**The Ledger is the secondary UI.** A single full window that opens rarely, like Console.app or Activity Monitor. Its core is the exposure ledger (surface E in the map); it contains as subordinate views the workspace/scope (D), the approval queue (F), and version history (G). It is not a three-tab app. The sidebar in the Ledger is a narrow nav rail for *the kind of evidence you want to see*, not *what Manifold lets you do*.

**Settings is a hidden surface.** Command-comma, from either the menu bar panel or the Ledger window. Settings is a destination, never a gate. It is allowed to be engineering-flavored; the user who finds themselves there has self-selected into engineering-flavored prose.

**Finder / Mail integrations are the third "surface"** — they don't belong to Manifold's app proper; they live in the user's existing workflows and bring Manifold's consent model to the files and messages the user is already looking at. Raskin's modelessness applied to spatial context: don't make the user switch apps to grant scope.

**What this rules out:**

- The three-tab segmented control in the main window
- The Overview tab as a standalone surface
- Full-screen modal approval sheets that block the frontmost app
- "Open Manifold" as a verb the user should ever need

**What this implies:**

- The main window becomes the **Ledger window**
- The menu bar panel is the target for disproportionate design investment
- Approvals go to a queue, and the menu bar panel shows the queue's count

This is a higher-leverage change than any visual polish. It is the foundation.

---

## Principle 1 — Trust is earned by visible evidence, not by claims

**Source:** Tufte (*Beautiful Evidence*, *Visual Explanations*); Few (*Now You See It*); Whitten & Tygar; Cranor & Garfinkel.

Trust products fail when they *assert* they are working. They succeed when the user can *see* they are working. Every security product that says "You are protected" and nothing else is, functionally, a placebo. The user has no way to falsify it.

Manifold's asset here is the exposure ledger. It should be the most finished surface in the app. It should be evidence presented under adversarial scrutiny, in Tufte's phrase — dense, position-encoded, temporally coherent, with one-click drill-down from summary to the actual bytes that changed.

**Rules this out:**
- Agent status labels that don't map to a consequence the user can feel or see
- "Everything is fine" screens with no data
- Hiding denials. Denials are the product working.

**Rules this in:**
- A ledger view with real information density (Tufte's small multiples, sparklines, session shapes)
- Status text that reads *"Claude can see 4 folders. Last looked at README.md 12 minutes ago."*
- A denial surface that is calm but prominent. Denials are successes.

---

## Principle 2 — Modelessness. The user's locus of attention is never hijacked.

**Source:** Raskin (*The Humane Interface*); Whitten & Tygar; Apple HIG on non-modal affordances.

Raskin's rule: a mode exists whenever the same user action produces different results depending on state. Every mode taxes the user's locus of attention. In a trust product, this tax is specifically harmful: users satisfice on consent dialogs, and satisficing means false consent.

**Rules this out:**
- `.sheet(...)` for approval flows
- Modal blocking on "Allow Claude to read this folder"
- Status indicators that change meaning based on context the user has to remember

**Rules this in:**
- An **approval queue**: requests accumulate silently; the user approves when they return to their own work
- Scope changes are made in-place in the scope view, never through a modal
- Tracked-work affordances are ambient (toolbar strip, menu bar strip), not interrupts

---

## Principle 3 — Defaults carry moral weight

**Source:** Thaler & Sunstein (*Nudge*); Cranor & Garfinkel on failure modes; Ink & Switch on user ownership.

The initial scope a new agent can see is a nudge. The default for "what agent can see" must be *nothing*. Then the user opts folders in. Defaulting to "everything in home folder" or even "last-opened folder" would be a design choice that shifts risk from Manifold to the user while calling it *convenience*.

**Rules this out:**
- First-run flows that ask "where should Claude look?" with suggested folders pre-selected
- "Allow" as the default button on any approval dialog
- Bulk-grant operations that skip per-source confirmation

**Rules this in:**
- Start empty. The first scope addition is a deliberate gesture.
- **"Deny"** (or the equivalent, e.g., "Not this time") is the focused default on every approval
- Bulk operations require the user to type or long-press — Jarrett & Gaffney's *Forms That Work* on consequential confirmations

This is where Manifold earns the right to be called an ethical product. Not by messaging. By defaults.

---

## Principle 4 — Scope is a spatial primitive, not a list

**Source:** Alexander (*A Pattern Language*, *Notes on the Synthesis of Form*); MacEachren (*How Maps Work*); Bret Victor ("Magic Ink," "Inventing on Principle"); Ink & Switch (*Local-first software*, *Capstone*).

The user model for Manifold has a few primitives: **source** (a folder or mailbox), **scope** (a set of sources an agent can see), **session** (a period when an agent is active), **exposure** (a specific read or write inside a session), **workspace** (a tracked copy where writes are reviewable). These primitives must be *drawn* before they are *listed*. Scope is particularly spatial: "these folders and no others" is a set-theoretic statement that rewards spatial treatment — Venn-like overlap when agents share a folder, concentric rings when one agent's scope contains another's.

Currently Manifold renders scope as a checkbox list in the Review sheet and an invisible concept everywhere else. That's Alexander's failure mode: the forces that produce "scope" as a primitive are live in the code but absent in the UI.

**Rules this out:**
- Scope editing via checklist only
- Scope represented the same in five different places
- Agent A's view of scope disconnected from Agent B's view of scope

**Rules this in:**
- A single canonical **Scope** view in the Ledger window, showing both agents' scopes laid over the same set of sources — overlap is visible
- Context menus on any source surface to "Share with Claude / Codex / both" without going to the Scope view
- Scope changes animate between states so the user sees the change land (Val Head, *Designing Interface Animation*)

---

## Principle 5 — Language is the product. Engineering vocabulary leaks build user-side engineering models.

**Source:** Yifrah (*Microcopy*); Podmajersky (*Strategic Writing for UX*); Metts & Welfle (*Writing Is Designing*); Kate Kiefer Lee (*Nicely Said*); Evans (*Do I Make Myself Clear?*).

Every user-visible string in Manifold is a design decision. Currently the app is bilingual: it speaks product (*"Start Tracked Work Block," "What can Claude see right now?"*) and it speaks engineering (*"mcp_connection," "coverage_warning," "runtime not connected," "manifold-routed"*). A user who learns Manifold ends up with an unnecessary model of its event schema.

The fix is not to rename event types in the database. It is to guarantee the user never sees them. A copy layer translates events into human sentences at the edge.

**Rules this out:**
- Any schema string leaked to the UI
- "Connected" / "Disconnected" as status without consequence text
- Denial language that reads as a firewall rejection

**Rules this in:**
- A **strings catalog** that is the source of truth for every user-visible phrase, with tone guidance
- Denial sentences in the past tense: *"Claude tried to read ~/Finances. Blocked — not in your workspace."*
- Status sentences in plain consequence: *"Claude can see 4 folders. Last read: README.md, 12 minutes ago."*

---

## Principle 6 — Color-as-identity and color-as-state occupy separate channels

**Source:** Albers (*Interaction of Color*); Bertin (*Semiology of Graphics*); Ware (*Information Visualization: Perception for Design*).

Agent identity (Claude vs Codex) is *who*. Status (active / paused / blocked / denied) is *what*. These must be distinguishable in peripheral vision, across accessibility modes, and on the same row where both appear. The current app uses system-semantic `Color.blue` / `Color.purple` for agents, which follow the user's accent choice and can collide with `Color.red` / `Color.orange` used for status.

**Rules this out:**
- Agent colors tied to system accent
- A palette where a red accent user sees Claude as red

**Rules this in:**
- A fixed Manifold palette with agent colors chosen for mutual contrast and contrast against both Manifold-status colors and every macOS accent
- Dark-mode variants hand-picked, not auto-derived
- Status always conveyed with a second channel (iconography, position, or text) so color is a reinforcement, not the only signal (Ware on pre-attentive cues)

---

## Principle 7 — Density with rhythm. The Ledger should reward close reading.

**Source:** Bringhurst (*Elements of Typographic Style*); Hochuli (*Detail in Typography*); Müller-Brockmann (*Grid Systems*); Lupton (*Thinking with Type*).

The Ledger, the Scope view, the Files view, and the approval queue are all dense-data surfaces. Dense does not mean cluttered. It means information per vertical inch is high *and the eye travels easily*. That is a typographic achievement, not a visual-design achievement.

**Rules this out:**
- SwiftUI default row paddings in dense tables
- `.relative` date formatting in scannable columns (variable width kills scan)
- Typography defined as roles without a baseline grid

**Rules this in:**
- A 4pt (or 2pt) baseline grid that every view aligns to
- Tabular numerics everywhere counts or times appear
- Fixed-width date columns, ISO-style with humanized secondary text
- Typographic states (normal / muted / paused / suspect) defined once and applied consistently

---

## Principle 8 — Direct manipulation. Every exposure is a handle.

**Source:** Bret Victor ("Magic Ink," "Inventing on Principle"); Tufte (*Visual Explanations*); Ink & Switch (*Capstone*).

The user should be able to grab any entry in the Ledger and act on it: revoke this folder from Claude's scope, revert this write, show me every file this session touched, show me all sessions that read this file. A log has no handles. Manifold's ledger must.

**Rules this out:**
- Ledger entries that are display-only
- Revert buried inside a row expansion
- No way to say "stop this agent from ever touching this file again" from the ledger row

**Rules this in:**
- Context menus on every ledger row with scope-level actions
- Selection → toolbar actions (batch revert, batch revoke)
- Click a file path in any surface → inspector slides in with version history

---

## Principle 9 — Accessibility is a structural property, not a polish layer

**Source:** Horton & Quesenbery (*A Web for Everyone*); Kalbag (*Accessibility for Everyone*); Apple HIG.

VoiceOver must produce a coherent read of the menu bar panel, the ledger, and the approval queue. Keyboard navigation must reach every action. Color must never be the only signal. Reduce-motion must dampen every transition. These are not polish items; they are acceptance criteria.

**Rules this out:**
- Green dot / red dot status with no text or icon second channel
- Animations without reduce-motion variants
- Focus order that follows visual layout but not semantic order

**Rules this in:**
- Every status has: color + icon shape + text
- A11y identifiers on every actionable element (many exist; the discipline should be universal)
- Keyboard shortcuts published in the Help menu

---

## Principle 10 — Reliability outranks polish. Honesty outranks confidence.

**Source:** CLAUDE.md; *The Design of Everyday Things* (Norman on error and signifiers); Ink & Switch.

If Manifold cannot reach its runtime, the UI says so in plain language with a "Reconnect" action, and every other surface is clearly in a *reduced-confidence* typographic state. No green dots on unverified state. No "Connected" over an XPC failure. No guessed history when the store is empty because the database hasn't migrated.

This is not a polish principle; it is the one principle that subsumes all the others. Pixelmator-bar means the user never catches the app in a lie.

---

## The principle hierarchy, from load-bearing down

1. Honesty (10)
2. Trust by evidence (1)
3. Posture — daemon, not sovereign (the posture call itself)
4. Modelessness (2)
5. Defaults (3)
6. Language (5)
7. Scope as primitive (4)
8. Direct manipulation (8)
9. Density with rhythm (7)
10. Color discipline (6)
11. Accessibility (9)

Every Stage-3 decision should be traceable to one of these. If a decision can't be, it's probably wrong.

Stage 3 next: A through O.
