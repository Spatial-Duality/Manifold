# Manifold UI — Stage 5: Addendum

Five questions from Amar after reviewing Stages 1–4. Two expose real gaps; one is a framing miss; one is a legitimate naming critique; one is a product-spec alignment check. Answered in order, with the design updates that follow.

---

## Q1 — How does the user see files within folders and select down to each file (or not)?

**Where the Stage 3 design was underspecified.** I treated a source (a folder) as atomic — one toggle per agent per source. That works for "share this whole folder" but fails the realistic case: *"share ~/Projects/Acme with Claude but exclude `/secrets`, exclude any `.env`, exclude `node_modules`."* Without per-file control the product is coarser than the spec promises.

**The fix: progressive disclosure in the Access inspector.**

The Access view stays a scannable matrix (sources × agents). Selecting a source row opens the right-pane inspector. That inspector is where fine-grained control lives.

**Inspector anatomy for a folder source:**

1. **Header** — folder path, file count, size on disk, last activity.
2. **Search** — single field to find a file or subfolder by name. *"find .env"* scrolls you to matches and lets you exclude them in one click.
3. **File tree** — recursive `OutlineGroup` over `FileNode`. Each row shows:
   - A tri-state checkbox: **included** (full check), **excluded** (empty), **mixed** (dash — folder whose children differ).
   - Name, size, modified date, and — crucially — a small *"Claude read 3× / Codex never"* trace. The tree is also evidence.
4. **Default state** — everything included. Reducing scope is explicit; expanding is default. Principle 3 (defaults carry moral weight) cuts both ways here: the *source-level* default is nothing-shared, but *within* a source the user has already opted in — so within it, include-all is the honest default.
5. **Exclusion propagation** — excluding a folder excludes its subtree. Children can be re-included as exceptions, rendered with a visible override marker (a dot on the checkbox indicating "overrides parent"). This is the Finder color-label pattern; users recognize it.
6. **Running count** — persistent at the top of the inspector: *"413 of 428 files will be visible to Claude. 15 excluded."* Counts update live; no save button (autosave with a subtle indicator — Principle 2, no modes).
7. **Bulk affordances** —
   - "Exclude all `.env`" (pattern rule attached to the source)
   - "Exclude folders named `node_modules`, `build`, `.git`" (pre-seeded as a **Smart default** at source-creation time)
   - "Exclude files larger than 10 MB" (for folders where agents don't need binaries)

**Pattern rules are first-class.** A folder source can have include/exclude rules (by glob, by size, by file type, by last-modified age). Rules compose with manual exclusions. The UI shows both — rules at the top, manual exclusions as an expandable list — so the user always knows *why* a given file is out.

**Second-order benefit.** Exclusions are searchable evidence. When a denial shows up in the Activity view ("Claude tried to read ~/Projects/Acme/.env"), the inspector lets you click through to see why: *"Excluded by rule: `*.env` — added by you on April 4."*

---

## Q2 — How does the user do the same for emails?

Same pattern. A mailbox source opens an inspector with three stacked regions:

1. **Folder / label tree** — IMAP folders or Gmail labels as an `OutlineGroup`. Same tri-state checkbox as the file tree. Include Inbox, exclude "Private Finance," include "Work" — this handles the 80% case.
2. **Filter rules** — a small rules editor specific to this mailbox. Each rule is a one-line conditional: *"from @legal.com → exclude," "subject contains invoice → include only subject line," "older than 1 year → exclude."* Rules compose AND; rule conflicts surface with a warning row (never a modal).
3. **Sensitivity** — three concrete named outcomes, not a slider of abstractions:
   - **Subjects only** — agents see sender, recipient, subject, date. Body is hidden.
   - **Trusted senders** — full content for senders you've shared with before; subjects-only for everyone else.
   - **Full content** — complete messages.

The three levels are mutually exclusive, named for *what the agent sees*, not for how paranoid the user feels. Yifrah: microcopy names outcomes, not settings.

**Live preview.** The inspector shows a sample message view as the agent would see it at the current settings. Change "Subjects only" → "Full content" and the preview fills in. This is Bret Victor's direct-manipulation rule: the user sees the effect of a setting without having to imagine it.

**Evidence trace.** Same as folders: a line showing "Claude read 12 messages / denied 3" links to the Activity view filtered to this mailbox.

---

## Q3 — How do the global auto email rules work?

**Where Stage 3 was wrong.** I moved email rules into each mailbox's inspector. That handles mailbox-specific refinements but misses the case you're asking about: *"I want one rule that applies across every mailbox I've ever shared or will share — never let any agent see anything from @legal.com, ever."* Collapsing these into per-mailbox inspectors creates duplicates and loses enforcement as the user adds new accounts. Same mistake I diagnosed in Critique §8 (scattered scope) — I made it myself on rules. Fair hit; fixing.

**The fix: a fourth sidebar item — Rules — for global policies.**

Revised left-rail nav: **Activity · Access · Requests · Rules**. (Versions collapses into an Activity filter, per Q4.)

**What Rules contains.**

Three categories of global policy, each a tabbed section of the Rules view:

1. **Email** — sender/domain blocklists, keyword redactions, sensitivity-triggered defaults. Example rules:
   - *"Never expose email from @legal.com to any agent"*
   - *"Redact credit-card numbers and SSNs from subjects and bodies before any agent sees them"*
   - *"Any email flagged with label `Confidential` — subjects only"*
2. **Files** — global file patterns that override any per-source inclusion:
   - *"Never expose `*.env`, `*.pem`, `.ssh/*` to any agent"* (seeded default — user can remove, but they have to do it deliberately)
   - *"Redact anything matching credit-card patterns from file contents shown to agents"*
   - *"Never let any agent write to `.git/` directories"*
3. **Agents** — rate limits, approval-required operations:
   - *"Require per-request approval for any write to files in `/Production/`"*
   - *"Pause any agent that issues more than 50 reads in a 10-minute window"*

**Rule precedence, made visible.** Global rules beat per-source rules. When a per-source rule would conflict with a global rule, the source inspector shows a banner: *"3 global rules also apply to this mailbox."* Clicking opens the Rules view filtered to the intersecting rules. No hidden arbitration. Principle 10 (honesty outranks confidence).

**Authoring.** Rules are written in a plain-English builder (subject + verb + object), not a regex editor by default. Regex is available as an advanced toggle. Every rule shows a live preview: *"This rule currently matches 42 files across your shared folders and 118 emails across your shared mailboxes."* The user sees blast radius before committing.

**Why this belongs on its own surface.** A global rule has different blast radius, different authoring surface, different evidence trail, and different lifecycle (global rules outlive any individual source) from a per-source rule. Giving them the same UI location conflates two user jobs. APL pattern-language logic: different forces, different pattern.

**Seeded defaults matter.** First-run seeds a small set of rules the user can accept or remove:

- `.env`, `.pem`, `.ssh/*`, `id_rsa` — excluded globally
- Credit-card, SSN, IBAN patterns — redacted globally
- `.git/` — never-write

Principle 3 again: defaults are moral. Shipping Manifold with zero seeded rules would be a design choice that shifts risk to the user while calling it configurability.

---

## Q4 — Why Ledger/Scope/Queue/Versions? Are these overlapping on all files? Information overload?

Two questions. Splitting them.

**(a) Do the four views overlap on "all files"?**

No. Each is a different projection:

- **Access** (was: Scope) — shows *sources* as the primary unit, drilling to individual files/messages inside. State-of-the-world.
- **Activity** (was: Ledger) — shows *events* (reads, writes, denials, searches, reverts). History-of-the-world.
- **Requests** (was: Queue) — shows *pending approvals*. Future-of-the-world.
- **Versions** — shows *changed files within tracked edits*. Subset of Activity with diffs attached.

Four different tenses of the same underlying substrate. Not four lists of all files.

**(b) Is four nav items too many? Are the names right?**

*Items.* Versions is the weakest of the four. It's a saved filter of Activity ("writes inside tracked work blocks, with diffs"). Collapse it. Add "Tracked edits" as a filter chip on the Activity view. The user who wants changesets from Friday afternoon filters the Activity view; they don't need a separate noun. This reduces cognitive load *and* names the conceptual reality — versions are events.

*Names.* Three of my four picks leaked engineering vocabulary and violated my own Principle 5. Renaming:

| Stage 3 name | Stage 5 name | Why |
|---|---|---|
| Ledger | **Activity** | "Ledger" sounds like accounting. "Activity" is what it is. |
| Scope | **Access** | "Scope" is a programmer word. "Access" is the exact word in your product spec. |
| Queue | **Requests** | "Queue" is engineer-speak for a data structure. "Requests" is what users see. |
| Versions | — (removed) | Filter of Activity. |

**Final nav rail: Activity · Access · Requests · Rules.** Four items, every one a plain English noun, each naming a different tense/perspective. That's not overload — it's the smallest legible set.

*Why Access is particularly important.* The product spec uses the word *access*. The UI uses the word *access*. The agent is *granted access* or *denied access*. The Activity view records *access events*. One word, applied consistently, eliminates a glossary the user would otherwise have to build.

---

## Q5 — How does the design reflect "giving AI tools controlled access to the files and email you choose"?

The spec has three load-bearing words: **controlled**, **choose**, **access**. Auditing each.

**Controlled.**

Three different tenses of control, each on its own surface:

- **Past control** — Activity view. Every access was recorded. Writes are reversible. Denials are preserved. Tufte / Few / Bertin / Victor stack — evidence under adversarial scrutiny.
- **Present control** — tracked-edit mode, the menu bar work-block strip, the pause-agent affordance. The user can stop the world at any moment.
- **Future control** — Requests queue, global Rules. What agents *will* be allowed to see next.

All three are first-class surfaces. The user never has to leave Manifold to answer *"has this been controlled?"*.

**Choose.**

The Access view + per-source inspector + Rules together constitute the choice surface. The Stage 5 additions (file tree, mailbox tree, global Rules) are the thing that makes *choose* real. Before Stage 5 the design made you choose *folders*; after Stage 5 you choose *files and messages*.

But there's a deeper fix. My Stage 3 microcopy made the *agent* the subject of every status sentence: *"Claude can see 4 folders."* That sentence grammatically positions the agent as the actor. The user reads it and feels like a spectator.

Replace with user-as-subject:

- **Idle** — *"You haven't shared anything yet."*
- **Active, steady state** — *"You've shared 4 folders with Claude. It read README.md 12 min ago."*
- **Active, tracked edit** — *"Claude is editing 3 files in your Acme folder. You can undo any of it."*

User is subject when describing choices you made. Agent is subject when describing what it did. Two voices, used on purpose. This is Podmajersky's information-architecture-through-words rule, concretely applied. Yifrah + Nicely Said concur.

Every surface's copy needs this pass. Listed in the updated strings catalog.

**Access.**

*Access* becomes the load-bearing noun across the product:

- "Access" names the Access view (was: Scope).
- "Granted access" / "Revoked access" replace "added to scope" / "removed from scope."
- "Access event" names an Activity row.
- "Pending access request" names a Requests card.
- "Access rule" names a global rule.
- "Access denied" replaces "coverage_warning" in the (invisible) schema-to-UI translation.

One word. Every surface. The user never has to learn Manifold vocabulary — the spec's own word carries them through.

---

## The updated nav, final

```
┌──────────────────┐
│  Manifold        │
│                  │
│  📊 Activity     │   ← events (reads, writes, denials, searches)
│  🗺  Access      │   ← sources + drill-down to files/messages
│  ⏳ Requests  •2 │   ← pending approvals
│  🛡  Rules       │   ← global policies
│                  │
└──────────────────┘
```

Four items. Three are plain English nouns that match the product spec. One ("Rules") names a primitive that had to exist because global policies have different blast radius. Every word survives Principle 5 (no engineering vocabulary in the UI).

---

## What actually changed in the design

Concrete diff against Stages 1–4:

1. **Nav rename.** Ledger → Activity, Scope → Access, Queue → Requests. Versions removed (becomes a filter chip on Activity).
2. **New surface: Rules.** Global email, file, and agent policies. Seeded with safe defaults (`.env`, `.pem`, credit-card redaction, etc.). Plain-English rule builder with live blast-radius preview.
3. **File-tree inspector.** Selecting a folder source opens a recursive tree with tri-state checkboxes, search, exclusion rules, live count.
4. **Mailbox inspector.** Folder/label tree, rule editor, three named sensitivity levels, live preview of what the agent would see.
5. **Microcopy pass.** User-as-subject for status sentences. "Access" replaces "scope" everywhere.
6. **Rule precedence UI.** Per-source inspectors show "N global rules also apply" banners; clicking opens the Rules view filtered.

Updated HTML visual spec reflects (1), (3), and the new Rules surface. (2), (4), (5), (6) are specified in prose and listed as Stage 6 work — another HTML pass or we ship directly to Swift.

---

## Where I was wrong, plainly

- Treated folders as atomic. Missed per-file control. Q1 correct.
- Collapsed global rules into per-mailbox inspectors. Lost the policy tier. Q3 correct.
- Named nav items with engineering vocabulary. Violated my own Principle 5. Q4 correct.
- Made agents the subject of status sentences. Robbed the user of authorship. Q5 (copy half) correct.

One right call worth defending:

- The four-section nav structure (state / history / future / policy) holds up. You asked whether it was overload; the renames make the same structure legible. The structure was right; the words were wrong.

Stage 6, if you want it: produce the full strings catalog, the Rules view mockup, the per-source inspector mockup with the file tree rendered, and the mailbox inspector with the live preview.
