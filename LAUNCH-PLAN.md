# Manifold Launch Plan

> April 11, 2026 — Amar Gandhi, Spatial Duality
> v3: Revised after codebase verification and positioning stress-test.
> Incorporates YC playbook research, 11 dev tool case studies, market analysis, and three rounds of strategic narrowing.

---

## What Manifold Actually Is (Not What We Want It to Be)

The codebase tells the truth. Manifold today is:

1. **Workspace isolation.** User picks files through Finder. MaterializationEngine copies them into a managed workspace. Agent works on the copy. Originals are never touched directly. This is structural prevention via isolation — not syscall interception, not real-time blocking.

2. **Full audit trail.** AuditStore logs every agent action: every file read, write, search, tool call. Sessions auto-group by agent with 5-minute gaps. This works cross-agent — Claude and Codex sessions are both recorded in the same local SQLite store.

3. **Per-file version history.** SnapshotStore records every file write with SHA-256 hashes. Every version is restorable. This is independent of git — it works on any file, in any directory, whether or not it's in a repo.

4. **Three-way merge promotion.** PromoteEngine compares baseline (at materialization), original (current state), and workspace (agent's changes). Detects conflicts when both human and agent modified the same file. Currently outputs via file copy, not git operations.

5. **Email backup with sensitivity filtering.** EmailSensitivityFilter blocks banking, health, and 2FA domains. IMAP sync, FTS5 search, smart mailboxes. Functional but a separate product surface.

What Manifold is NOT today:

- Not a real-time blocker. Once access is granted, the agent works freely in the workspace.
- Not a secrets scanner. There is no code for detecting .env files, SSH keys, API tokens, or credentials in the file layer. EmailSensitivityFilter handles email domains only.
- Not git-aware. PromoteEngine does file copies, not branches or patches.
- Not cross-machine. Everything is local SQLite on one Mac.

## The Category (Honest Version)

**For users:** See what AI changed. Restore any edit. Keep your originals safe.

**For YC/investors:** The user-owned observation and reversibility layer for AI agent work — cross-agent, file-centric, and independent of any vendor's session UI.

**One-liner:** Give AI agents a copy of your project, not your whole Mac.

These are different sentences for different audiences, and that's fine. The product is the same; the framing changes based on who's listening.

## The Real Competition (Updated)

The feedback is right that enterprise MCP gateways aren't the day-one competition. Neither is "nothing." The actual alternatives a developer faces today:

**Claude Code's built-in controls.** Anthropic ships sandboxing, approval prompts, configurable filesystem/network boundaries. Their own data shows 93% approval rate — which is exactly the approval-fatigue problem, but it means the mechanism exists. Claude Code also stores local transcripts of full session history.

**Codex's isolated environment.** OpenAI's Codex gives agents worktrees, built-in diff review, inline comments, staging/reverting chunks, local history persistence, and OpenTelemetry export. This is structurally similar to Manifold's workspace isolation for code.

**Plain git + hope.** Commit before running the agent. Git diff to see changes. Git checkout to undo. Works for code in repos. Doesn't work for configs, dotfiles, documents, downloads, or anything outside a tidy git workflow.

**Doing nothing.** Most developers today. They run the agent, hope for the best, and manually check what changed.

**Where Manifold wins (the structural gap):**

- **Cross-agent.** No other tool shows what happened across Claude AND Codex on the same machine. Each vendor only shows their own sessions.
- **File-centric, not session-centric.** Vendor UIs organize by session. Manifold organizes by file. "What happened to this file across all agent sessions?" is a question only Manifold can answer.
- **Files git doesn't cover.** Configs, dotfiles, .env files, local documents, memory files, exports, Downloads, client deliverables. MaterializationEngine accepts any filesystem path — it's fully general, not git-dependent.
- **User-owned.** All data is local. No vendor telemetry. No cloud dependency. The audit trail belongs to the user, not to Anthropic or OpenAI.
- **Instant file-level restore.** Not "revert a commit" but "restore this one file to its state before Claude touched it." Finer-grained than git and available for non-git files.

---

## Product Changes Required (Prioritized by Impact)

### Must-have before launch

**1. Sensitive file detection (NEW — does not exist today)**

The feedback's proposed first-run moment — "Claude edited 8 files. One contained a secret-like value. Here is the diff. Restore?" — requires a secrets scanner for the file layer. Currently, only EmailSensitivityFilter exists (email domains). There is no equivalent for files.

Build a lightweight `FileSensitivityScanner` that flags:
- Files matching sensitive path patterns: `.env`, `.env.*`, `id_rsa`, `id_ed25519`, `.ssh/*`, `.aws/credentials`, `.npmrc`, `.netrc`, `*.pem`, `*.key`, `*.p12`
- Files containing secret-like patterns: `AKIA` (AWS keys), `sk-` (OpenAI keys), `ghp_` (GitHub tokens), `-----BEGIN.*PRIVATE KEY-----`, high-entropy strings adjacent to keywords like `secret`, `password`, `token`, `api_key`

This doesn't need to be comprehensive. It needs to catch the obvious cases so the UI can surface "this file looks sensitive" in the audit view. The goal is the emotional moment: fear → clarity → relief.

**Effort estimate:** ~1-2 days. Path pattern matching is trivial (GlobMatcher already exists). Content pattern matching is regex on file reads, scoped to files under a size threshold.

**2. Observation-first onboarding (RESEQUENCE — infrastructure exists, UX needs redesign)**

Current onboarding: add sources → grant access → agent works → review.

Better onboarding: agent already worked → here's what changed → restore the bad parts → now set up your own sources.

The infrastructure for this exists: AuditStore has the data, SnapshotStore has the versions, HistoryModel can display the timeline. What's needed is a first-run flow that shows the value before asking the user to configure anything.

Two approaches:
- **Demo mode:** Ship a pre-populated SQLite database showing a realistic completed session (8 files edited, 2 flagged as sensitive, 1 bad edit, 1 new file created). User experiences the review/restore flow immediately, then transitions to "now connect your own files."
- **Post-session hook:** Skip onboarding entirely. Let the user add a source, run one agent session, then surface a "Session complete — here's what happened" summary that demonstrates the observation/restore value.

The demo mode is better for launch because it doesn't require the user to have an agent session ready. It's the equivalent of the "demo repo with fake secrets" from the v2 plan, but applied to the review experience rather than the materialization experience.

**Effort estimate:** ~2-3 days for demo mode (create sample database, build first-run detection, summary view).

**3. Starter exclusion presets (SMALL — GlobMatcher exists, needs default patterns)**

MaterializationEngine currently skips only noise directories (.git, node_modules, .build, etc.). No default exclusions for sensitive files. Ship a `.manifoldignore` default that auto-excludes obvious sensitive paths. Make it visible and editable in the UI so users can see what's protected.

**Effort estimate:** ~0.5 days. GlobMatcher infrastructure exists. Just add default patterns.

### High-value but can ship post-launch

**4. Git-native promote (ENHANCEMENT — PromoteEngine needs new output mode)**

Currently PromoteEngine does `FileManager.copyItem()`. For directories that are git repos, add an alternative output: create a branch (`manifold/claude-session-YYYY-MM-DD`), apply the workspace changes as a commit, and let the user merge via their normal git workflow. The three-way merge logic stays; only the output format changes.

This makes promotion feel safe and familiar to developers. "Review this branch" is much less scary than "Manifold will overwrite your files."

**Effort estimate:** ~2-3 days. Requires shelling out to git or using libgit2. The three-way merge logic is the hard part and it's already built.

**5. Cross-agent summary view (UI — data layer exists)**

AuditStore already provides cross-agent session data. Build a "What happened on this Mac today" view that shows a unified timeline across Claude and Codex sessions. This is the cross-agent differentiator made visible.

**Effort estimate:** ~1-2 days. Data queries exist in AuditStore. Needs a UI surface.

---

## The YC Question

### Deadline reality

YC Summer 2026 on-time deadline is **May 4, 8pm PT.** That's 23 days from today. On-time applications get the most partner attention and quickest response. Late applications are reviewed by fewer partners and compete for fewer slots.

This changes the timeline materially. The application should be submitted before or alongside the public launch, not after it.

### What makes this high-alpha

The positive case is strong:
- Technically non-obvious (content-addressed blobs, three-way merge, fail-closed MCP bridge, zero external dependencies)
- Clear founder-problem fit (you use AI agents daily and built this because you needed it)
- Real market transition (agents going from "suggestion engines" to "autonomous workers" creates a new trust gap)
- Demos well (the seven-step visceral demo: select → workspace → excluded files absent → bad edit → restore → promote)
- Plausible open-source trust advantage (if you resolve the license)
- Weird in a good way (using Claude to build the tool that controls Claude)

### What makes it risky

The biggest application risk is vendor overlap. Anthropic and OpenAI are both shipping controls that overlap with pieces of Manifold. A YC partner will ask: "Why won't Anthropic just add this?"

The answer: Because vendor tools are session-centric and vendor-specific. Manifold is user-centric, cross-agent, file-centric, and user-owned. Anthropic will never build a tool that shows you what Codex did. OpenAI will never build a tool that shows you what Claude did. Neither will build audit trails for non-code files outside their session UI. The structural gap is that both vendors are incentivized to make their own agent look trustworthy, not to give users independent verification across all agents.

That's a real insight. Show me the incentive, I'll show you the outcome: vendors will always optimize for their own agent's experience, not for user-owned cross-agent visibility.

### Application framing

**User-facing:** See what AI changed. Restore any edit. Keep your originals safe.

**YC-facing:** Manifold is the user-owned observation and reversibility layer for AI agent work. It shows exactly what Claude Code and Codex changed on your machine, flags sensitive file touches, and lets you instantly undo any AI edit. Over time, it becomes the trust layer that makes people confident enough to delegate more to agents.

**The deeper thesis (for the application, not for users):** People delegate more when they trust the agent. Trust requires independent verification, not vendor self-reporting. Manifold is independent verification for AI agent work.

### YC application logistics

- Submit on-time (before May 4)
- Include a demo video (YC says applications with video are statistically more likely to get interviews)
- Be candid about what's built and what isn't (YC explicitly rewards honesty about flaws)
- The seven-step demo is the video: select files, exclude secrets, agent works, show excluded files are absent, bad edit happens, restore, promote good changes
- Frame as "the beginning of a category" not "a clever Mac utility"

---

## Revised Phase Structure

### Phase 0: Ship-Ready + YC Application (Now → May 4)

**23 days. Two parallel tracks.**

**Track A — Product (must-haves for demo/launch):**

- [ ] Finish UI rebuild (v5.2 plan — this is the critical path)
- [ ] Build FileSensitivityScanner (path patterns + content patterns)
- [ ] Ship starter .manifoldignore exclusion presets
- [ ] Build observation-first onboarding (demo mode with sample session)
- [ ] Resolve LICENSE file (MIT vs proprietary — affects entire strategy)
- [ ] Signed, notarized DMG
- [ ] Homebrew tap

**Track B — YC Application (submit before May 4):**

- [ ] Write application (candid about what's built, what isn't, what's the insight)
- [ ] Record demo video (the seven-step sequence, 60-90 seconds)
- [ ] Frame the "why won't vendors just build this?" answer clearly
- [ ] Submit on-time

These tracks are parallel. The YC application doesn't require a polished product — it requires a sharp demo, a clear insight, and honesty about the current state.

### Phase 1: Design Partners (May → 20 users)

Same as v2 plan but with four specific cohorts:

1. **Contractors** working on client repos (high sensitivity, can't risk file leakage)
2. **Startup engineers** using Claude Code daily (volume users, approval fatigue)
3. **Open-source maintainers** (public trust matters, accidental secret exposure risk)
4. **Security-minded Mac power users** (care about audit trails, will stress-test edges)

Sit with each one. Answer four questions:
1. What were they scared the agent would touch?
2. What did they expect Manifold to preserve?
3. What confused them in the first five minutes?
4. What would make them use this every week?

**Gate before broad launch:** Most partners finish first run in under 10 minutes. Meaningful fraction come back for a second run within 7 days.

### Phase 2: Show HN (When gate is passed)

**Title:** "Show HN: Manifold – Give AI agents a copy of your project, not your whole Mac"

**Post structure:** Lead with the concrete problem (agent modifies wrong file, no audit trail, no undo). Show the four-step loop (choose → workspace → watch → restore/promote). State the honest boundary (what it does and doesn't control). Technical nerd bait (Swift 6, zero deps, content-addressed blobs, fail-closed MCP). Personal story. Link to repo, demo, .dmg.

**Files are the hero. Email is not mentioned.** Email can be a Show HN follow-up post in 6-8 weeks.

**Launch package (five things, not eight):**
- Show HN linking to GitHub
- One X thread with 45-90 second demo
- One blog post (your site + Dev.to)
- One Reddit post (r/programming OR r/MacOS, not both day-one)
- GitHub Discussions for support

### Phase 3: Post-Launch Compounding (Weeks 1-8)

**Weekly cadence:** One user-visible improvement + one trust/content artifact.

**Integration guides (discovery channels):**
- Week 1: Claude Code setup guide
- Week 2: Codex setup guide
- Week 3: VS Code / generic MCP client
- Week 4: Cursor / Windsurf

**Comparison pages (honest, not marketing):**
- Manifold vs Claude's built-in sandboxing
- Manifold vs Codex worktrees
- Manifold vs plain git worktrees
- Manifold vs doing nothing

**User stories** as they emerge from design partners. Specific workflows, before and after.

Ship git-native promote in this phase. Ship cross-agent summary view. Ship whatever design partners ask for most.

### Phase 4: Email as Second Act (Week 8+)

Only after the file workflow has retention. Email broadens the product surface and raises the trust bar. By this point you'll have design partner feedback on whether email is something they actually want, or something that sounds good in a feature list but nobody uses.

### Phase 5: Monetization (When pulled by usage)

Don't build pricing until 100+ active weekly users. The first paid features will likely be: shared team policies, centralized audit export, admin controls, MDM deployment. Let usage pull them out.

---

## Operating Metrics

**Activation:** Install → first workspace → first agent file change → first promote or restore.

**Time to value:** Minutes from install to first successful watched run. Target: under 10 minutes.

**D7 repeat:** Percent of activated users who do a second run within 7 days. This is the number that matters. A tool people use once and forget is not a product.

**Referral proof:** Percent of new users who came from another user, not from content. When this rises, you have organic pull.

Stars, upvotes, and launch rank are useful signals. They are not the operating system.

---

## What's Cut

- "AI agent governance platform" messaging → own "safe handoff" first, expand later
- Apple Mail as co-equal launch pillar → files only at launch, email is second act
- Discord → GitHub Discussions until real traffic exists
- Product Hunt → postpone until onboarding is polished and app feels visually complete
- Star-count goals as primary metric → D7 repeat is what matters
- Eight-channel launch day → five focused things
- Enterprise compliance positioning → premature for a solo dev with zero enterprise customers
- "We do permissioning better than vendors" → dangerous framing that puts you under vendor roadmaps
- Broad "trust layer for all AI" for v1 → that's the trajectory, not the launch

---

## The Honest Risks

**Vendor convergence.** Anthropic and OpenAI are shipping controls fast. Claude Code already has sandboxing, transcripts, approval policies. Codex has worktrees, diff review, OpenTelemetry. The gap today (cross-agent, file-centric, user-owned) is real but could narrow. Mitigation: ship fast, build user base, go deeper on the files-outside-git niche that vendors won't prioritize.

**Apple platform risk.** macOS Tahoe has App Intent Domains and enhanced privacy controls. If Apple ships native AI agent file permissions, Manifold's surface shrinks. Mitigation: Apple moves slowly on dev tooling (12-18 months minimum), and won't build three-way merge or cross-agent audit trails.

**"Mac only" ceiling.** Long-term, the company can't stay "just a Mac file watcher." Agents run on Linux servers, in cloud containers, on Windows. But for launch, macOS-only is the right constraint — it's where your expertise is, where the design quality matters, and where the power users are.

**Solo developer bandwidth.** YC application + UI rebuild + product changes + design partners + Show HN + content — that's a lot for one person in 6-8 weeks. Be ruthless about what actually needs to happen versus what would be nice.

---

## Decision Framework

1. **Can a new user experience the value in under 10 minutes?** If not, fix onboarding.
2. **Are activated users coming back within 7 days?** If not, the product isn't sticky. Fix that before adding users.
3. **Does this make the product better for the 20 people using it?** If not, it's premature.
4. **What's the incentive?** Who benefits and why would they care? If unclear, it's theater.
5. **Is this the product or the pitch?** Build the product. The pitch follows from what's real.
6. **YC deadline: does this help the May 4 submission?** If not, it can wait.
