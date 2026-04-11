# Manifold Launch Plan

> April 11, 2026 — Amar Gandhi, Spatial Duality
> v2: Revised after stress-testing against product reality.
> Derived from YC playbooks, 11 dev tool case studies, current market analysis, and honest assessment of what the product actually is today.

---

## The Category

Manifold is not "the governance layer for AI agents." That is an aspiration, not a product you can ship today. Manifold is a native macOS app that lets a developer hand a real project to an AI agent without handing over the whole machine.

The category is **safe handoff for AI coding on Mac.**

## The One-Liner

**Give AI agents a copy, not your Mac.**

Then the explanation: choose files, create a managed workspace, watch every change, restore or promote with one click.

## Why This Framing Matters

"Permission layer" sounds like enterprise middleware — something an IT team deploys. "Curated workspace" sounds like something a developer uses at their desk. The README's phrase "allow-first workspace curation" is the honest description of what the product does, and it's more concrete than any governance positioning. Lead with the workflow, not the category.

MCP, audit logging, content-addressed blobs — these belong lower on the page as technical details that earn trust with the HN crowd. They are not the hero.

---

## Honest Assessment: What You Have and What You Don't

### What you have

A real product with 230+ tests, 16 MCP tools, content-addressed blob storage, three-way merge promotion, email sensitivity filtering, full audit logging. The backend is mature and the architecture is clean: pure Swift, zero external dependencies, fail-closed MCP server. That's not a prototype — it's a serious piece of software.

The market timing is strong. MCP has crossed 97 million monthly SDK downloads and 10,000 active servers. Stack Overflow's 2025 survey says security/privacy concerns are the top reason developers reject a technology. Anthropic's own data shows Claude Code users approve 93% of permission prompts — exactly the approval-fatigue problem Manifold targets. OWASP published a 2026 Top 10 for Agentic Applications. Microsoft shipped an Agent Governance Toolkit. The problem has become a recognized category.

macOS-native with Liquid Glass — genuinely beautiful on the platform. Raycast proved that design quality drives adoption for macOS dev tools. Your app should feel like it belongs on the Mac, not like a web app in a wrapper.

### What you don't have

A finished UI. The v5.2 redesign plan estimates ~24.5 hours across 10 phases. That's the critical path. Nothing else matters until the app is usable.

Any existing audience. @SpatialDuality has near-zero followers. No newsletter, no community, no prior HN comment history. You're starting from zero distribution.

Users. Not one. Every YC playbook says "10 who love you > 1,000 who like you," but the prerequisite is having 10.

### License discrepancy

README says MIT. The actual LICENSE file says "proprietary and confidential." This must be resolved before any public launch. The open-source playbook and the proprietary playbook are fundamentally different strategies, and every dev tool case study points to open-source as the strongest distribution mechanism — but it's a real tradeoff. You cannot say "open-source" on HN if the LICENSE file says otherwise.

### The binding constraint

The UI, then first-run clarity, then repeat usage. In that order. Technical credibility is already established by the codebase. The next bottleneck is whether someone can install the app, understand it, and come back the next day.

---

## Your Real Day-One Competition

The original plan mapped competitors as enterprise MCP gateways (MintMCP, Permiso, MCPX). That's the wrong competition model. A developer sitting at their Mac right now isn't choosing between Manifold and MintMCP. They have never heard of MintMCP.

Your real alternatives are:

**Claude's built-in sandboxing and auto mode.** Anthropic already provides permission prompts and sandbox containers. 93% approval rate means most people just click through, but the mechanism exists.

**Codex's worktrees.** OpenAI's Codex already gives agents isolated copies with built-in git worktrees. This is structurally similar to what Manifold does for files.

**Plain git + hope.** Most developers just commit before running an agent, use git diff to see what changed, and git checkout to undo. It works, roughly. It's what people do today.

**VS Code + MCP clients.** MCP is flowing into VS Code, ChatGPT, and other products. The protocol is becoming ambient.

These validate the need but narrow the window. Manifold wins only if it is meaningfully simpler, clearer, and more trustworthy for local Mac workflows than the defaults users already have. The gap Manifold fills: none of these alternatives show you what the agent read, give you per-file version history independent of git, handle non-code files (documents, configs, notes), or let you control email access. And none of them feel like a native Mac app.

---

## Three Product Changes Before Launch

These matter more than any marketing. They're the difference between "interesting idea" and "I use this every day."

### 1. Built-in demo repo with fake secrets

Create a sample repo bundled with Manifold that contains fake API keys in .env, mock SSH keys, simulated client documents in a /confidential folder, and some normal code files. When a new user opens Manifold for the first time, they can experience the full loop safely in under five minutes: select the safe files, exclude the secrets, grant access, watch the agent work, see an excluded file is absent from the workspace, restore a bad edit, promote the good changes back. Without this, first-run requires the user to risk their own files — a trust ask you haven't earned yet.

### 2. Git-native promote

Currently, PromoteEngine copies modified files back to originals. For developers, this should create a git patch, branch, or commit instead. "Manifold created a branch with Claude's changes. Review the diff, merge when ready." This fits the developer workflow and makes promotion feel safe rather than magical. The three-way merge is the right engine underneath, but the output should be git-native.

### 3. Starter presets that auto-exclude sensitive paths

Ship default exclusion patterns for .env, .env.*, id_rsa, id_ed25519, .ssh/*, .aws/credentials, .npmrc (with auth tokens), .netrc, *.pem, *.key, Keychain files, and ~/Documents/Private (or similar). Make these visible and editable. The message: "Manifold already knows what not to share." This is trust-by-default, not trust-by-configuration.

---

## Phase 0: Pre-Launch (Now → UI Complete)

**Duration:** However long the UI takes. Use this time to build distribution and ship readiness — not marketing.

### Ship readiness

**README overhaul.** Lead with "Give AI agents a copy, not your Mac." Then the four-step loop: choose files → managed workspace → watch changes → restore or promote. Screenshots. A GIF of the core workflow. Technical details (MCP, architecture, content-addressed storage) go lower. The README is your landing page; make it scannable in 10 seconds.

**Distribution stack.** Not postlaunch cleanup — prelaunch checklist:

- GitHub Releases as source of truth
- Signed, notarized DMG from day one (Apple Developer ID + notarization gives Gatekeeper confidence)
- Homebrew tap immediately (`brew install --cask spatial-duality/tap/manifold`), then submit to homebrew-cask once stable
- Sparkle for auto-updates
- CLI install path alongside the app (`manifold-mcp --install` already exists — good)

Skip the Mac App Store. Wrong optimization for this audience, and the sandboxing requirements may conflict with your file access model.

**Demo recording.** Not a product tour — a visceral seven-step sequence:

1. A repo with fake secrets and mixed-sensitivity files
2. Manifold selects a subset, excludes the secrets
3. Claude works on the managed copy
4. Show that excluded files are absent from the workspace
5. The agent makes a bad edit to a config file
6. Restore the original with one click
7. Promote the good changes back via git branch

45-90 seconds. That's the whole story. Put it on YouTube and embed in README.

**Trust pages.** Because this is a security-adjacent tool, trust is part of the product, not just the positioning. Publish five short pages (can be markdown in the repo or on your site):

1. What Manifold protects (and the specific mechanisms)
2. What Manifold does not protect (connectors, plugins, computer use, network — be explicit)
3. Where data is stored (all local, which directories, how blobs work)
4. What telemetry exists (ideally: none. If any, be precise)
5. How restore, promote, and deletion work (what actually happens to files)

The README's existing honesty about the boundary ("Manifold does not control agent connectors, plugins, computer use, or network access") is your biggest trust asset. Security tools lose credibility when they imply more coverage than they provide. Manifold should feel unusually precise, not unusually grand.

### Distribution building

**Start commenting on HN now.** Not about Manifold. About AI agent security, MCP, file permissions, data sovereignty, approval fatigue. Build a comment history that shows you think deeply about these problems. 30-60 days minimum before launch. When you Launch HN, people will click your profile.

**Identify your first 20 design partners by name.** Split across four cohorts:

1. Contractors working on client repos (high sensitivity, can't risk file leakage)
2. Startup engineers using Claude Code daily (volume users, approval fatigue)
3. Open-source maintainers (public trust matters, concerned about accidental secret exposure)
4. Security-minded Mac power users (care about audit trails, will stress-test edge cases)

These aren't abstract personas. Find specific people. Who in your network, in MCP Discord, in HN threads complaining about agent file access, fits these descriptions?

**Engage in MCP community.** GitHub discussions, Discord. When someone asks "how do I control what my agent can access?" you want to already be known as someone who's been helpful in that space.

### What NOT to do

- Don't set up Discord. Empty Discord is negative signal.
- Don't pitch newsletters or podcasts. Nothing to show yet.
- Don't schedule recurring social posts. No audience to post to.
- Don't build pricing pages or enterprise features.
- Don't position as "AI agent governance platform." That's a Series A pitch, not a launch message.

---

## Phase 1: Design Partners (UI Complete → Launch)

**Duration:** 3-4 weeks. The goal is not an audience — it's 20 manual installs with real users on real repos.

### The Collison Installation (Weeks 1-2)

Install Manifold for your first 10 design partners yourself. Video call or in person. Sit with them while they do a real task with the agent they already use (Claude Code or Codex).

You are answering four questions:

1. **What were they scared the agent would touch?** (Tells you what presets and exclusions to build)
2. **What did they expect Manifold to preserve?** (Tells you if your mental model matches theirs)
3. **What confused them in the first five minutes?** (Tells you what to fix in onboarding)
4. **What would make them use this every week?** (Tells you what to double down on)

Don't pitch. Don't explain features. Watch and listen.

### Fix and expand (Weeks 2-4)

Fix what breaks. Your design partners will find issues in the first five minutes that 230 tests didn't catch. UI flows that make sense to you won't make sense to them. Ship daily updates.

Expand to 20 design partners total, across all four cohorts. Ask your first 10 to each refer one person. If they won't refer anyone, the product isn't good enough yet — go back to fixing.

### Gate: Do not launch broad until two things are true

1. **Most design partners can finish a first run in under 10 minutes.** If onboarding takes longer, you'll lose HN visitors.
2. **A meaningful fraction come back for a second run within the same week.** For this product, second-session behavior matters more than star velocity. If people try it once and don't return, adding more users won't help.

### Run the PMF test

Ask each design partner: "How would you feel if you could no longer use Manifold?" Target: >40% say "very disappointed." If you're below 40%, iterate before launching. This is the Superhuman method and it's the clearest signal that exists.

### Collect specific stories

Not "this is great!" but: "Manifold caught that Claude rewrote my .env file and I restored it in one click" or "I finally know which files Codex actually read during a session." Specific stories are the raw material for the HN post and every piece of content after it.

---

## Phase 2: Show HN

**Timing:** Tuesday-Thursday, 8:00-10:00 AM US Eastern. Check that no major tech news is dominating HN that day.

### Title

"Show HN: Manifold – Give AI agents a copy of your project, not your whole Mac"

(Show HN, not Launch HN — you're not a YC company. Show HN is for sharing what you've built.)

### Post structure

Write in your voice. Peer-to-peer, not corporate. The Launch HN guidelines apply even for Show HN: no superlatives, no marketing language, talk like you're having a drink with a friend.

Framework (rewrite in your own words):

- One sentence: what it is
- The problem: what happens today when you give Claude Code access to a repo with secrets, client files, or mixed-trust content
- How it works: the four-step loop (choose → workspace → watch → restore/promote)
- The honest boundary: what Manifold controls and explicitly what it does not
- Architecture nerd bait: Swift 6, zero dependencies, content-addressed blobs, three-way merge, fail-closed MCP
- The personal story: why you built it, the irony of using Claude to build it
- Link to repo, link to demo video, link to the .dmg download

Do NOT lead with email. Files are the hero. Email is a second-act feature that broadens the story later.

### Launch day rules

**Reply to every comment.** Within minutes. This is the single most important thing you do on launch day.

**Treat "I just use git" as a gift.** "Git tracks commits, but it doesn't show you what the agent read, doesn't handle non-code files, and requires you to commit before every agent run. What would be more useful to you?" Turn critics into design partners.

**Do not coordinate upvotes.** HN's detection is sophisticated. Let it succeed or fail on merit.

**Have the .dmg working and downloadable.** If "how do I try it?" requires building from source, you've lost 80% of potential users.

### The launch package (focused, not broad)

- Show HN post linking to GitHub repo
- One X thread with the 45-90 second demo video
- One technical blog post on your site and cross-posted to Dev.to
- One Reddit post where the framing fits the community (r/programming or r/MacOS, not both on day one)
- GitHub Discussions enabled for support

That's it. Five things. A solo developer spreading across eight channels on day one dilutes support and engagement across all of them.

---

## Phase 3: Post-Launch (Days 1-14)

### First 48 hours

**Fix bugs reported on HN within hours.** Reply with "Fixed in [commit]. Thanks for catching this." This signal — responsive developer who ships fast — is worth more than any feature.

**Track the activation funnel.** Download → install → first workspace created → first file changed by agent → first restore or promote. Where do people stop? That's what you fix next.

**Email every user who installed it.** Personally. Not a drip campaign. "Thanks for trying Manifold. What worked? What didn't? I'm the developer and I read every reply." You are doing the thing that doesn't scale.

### Days 3-14

**Post a follow-up.** "What I learned from launching Manifold on HN" — specific feedback, what you changed, what surprised you. This is content that earns a second look from people who missed the first post.

**Publish the first integration guide: Claude Code.** Step-by-step: install Manifold, run `manifold-mcp --install`, open your project, grant access, start a Claude Code session. This is discoverable content — people searching "Claude Code file permissions" or "Claude Code security" should find it.

---

## Phase 4: Compound (Weeks 3-8)

Only proceed if Phase 3 showed retention signal: design partners still using it, new users coming back for second sessions, organic sharing happening.

### Weekly cadence

Every week, ship one user-visible improvement and one trust/content artifact. Specifically:

**Integration guides (one per week):**
- Week 3: Claude Code (already published)
- Week 4: Codex
- Week 5: VS Code / generic MCP client
- Week 6: Cursor / Windsurf

These become discovery channels. When someone searches "how to use MCP with Cursor safely," your guide should appear.

**Comparison pages (one per week):**
- Manifold vs Claude's built-in sandboxing
- Manifold vs Codex worktrees
- Manifold vs plain git worktrees
- Manifold vs doing nothing

Be honest in these. Acknowledge what the alternatives do well. Explain specifically where Manifold adds value (per-file history independent of git, non-code file handling, email access control, audit trail of reads not just writes). Honest comparisons build more trust than marketing pages.

**User stories (as they emerge):**
When a design partner or user has a concrete "Manifold saved me" moment, write it up with their permission. One specific workflow, before and after. These are the most persuasive content you can produce.

### Community (minimal)

GitHub Discussions for support. Not Discord — too early, and an empty Discord hurts perceived momentum. Respond to every GitHub issue within 24 hours.

### Newsletters (only now, with traction)

Pitch 2-3 targeted newsletters after you have: HN post with comments, GitHub stars, real users, integration guides. Console.dev, TLDR, Changelog. They cover things with existing momentum, not cold pitches.

---

## Phase 5: Sustainability (Months 3-6)

### When to think about money

Not until you have 100+ active weekly users who'd be "very disappointed" without Manifold. Charging before that creates friction that slows the learning loop.

### What monetization will look like (let usage pull it out)

The first monetizable asks from users will likely be: shared policies across a team, centralized audit export, admin controls, MDM deployment profiles, team templates. Don't build these first. Build them when users ask for them.

When ready, the pricing logic:

**Free (forever):** Full app, 1-2 agents, 90-day audit history, all file versioning. Must be genuinely useful — not a crippled trial.

**Pro ($19/month):** Unlimited agents, unlimited history, compliance-format audit export, email integration, priority support.

**Team ($49/seat/month):** Shared policies, team audit dashboard, SSO. The enterprise wedge.

The Tailscale pattern: engineer uses it free at home → brings to work → team adopts → admin needs team features → pays. The incentive flows naturally.

### The Apple risk

macOS Tahoe has App Intent Domains and enhanced privacy controls. If Apple ships native AI agent file permission control in macOS 27-28, Manifold's value proposition narrows.

Mitigations: ship fast and build a user base (Apple moves slowly on dev tooling — 12-18 months minimum). Go deeper than Apple will (three-way merge, email sensitivity, audit trails — Apple won't build these). Build the community moat (Raycast thrives despite Apple improving Spotlight every year).

### The platform risk

MCP is becoming ambient — built into VS Code, ChatGPT, Claude Desktop. If MCP clients start shipping built-in workspace isolation, Manifold's integration advantage shrinks. Mitigation: Manifold's value isn't being an MCP server. It's the full workflow: selection → isolation → versioning → audit → promotion. That's five things, not one.

---

## Operating Metrics

Track four numbers. Everything else is vanity.

**Activation rate:** Percent of installs that complete: first workspace created → first file changed by agent → first promote or restore. This is your onboarding quality metric.

**Time to value:** Minutes from install to first successful watched run. If this is more than 10 minutes, your onboarding is broken.

**D7 repeat:** Percent of activated users who do a second run within 7 days. This is the retention signal that matters. A tool people use once and forget is not a product. For Manifold, second-session behavior matters more than star velocity.

**Referral proof:** Percent of new users who say they came from another user, not from content. When this number rises, you have organic pull. Until then, you're pushing.

Stars, upvotes, and launch rank are useful signals of interest. They are not the operating system for the company.

---

## What to Cut From the Original Plan

**"AI agent security platform" messaging.** Too broad for what the product is today. Own "safe handoff for AI coding on Mac" first. Expand the category later if usage demands it.

**Apple Mail as co-equal launch pillar.** Files are easier to explain, easier to demo, and closer to the Claude/Codex workflow. Lead with files. Treat email as private beta or second act. Leading with both makes the product feel broader than it is and raises the trust bar before you've earned it.

**Discord.** Empty community channels are negative signal. GitHub Discussions until there's real traffic.

**Product Hunt as launch center.** PH rewards visual polish and broad appeal. Manifold is a technical tool for a specific audience. HN is the right venue. PH can come later when onboarding is polished and the app feels visually complete.

**Star-count goals as success metric.** Stars measure curiosity. D7 repeat measures whether you changed someone's workflow. Optimize for the second.

**Eight-channel launch day.** A solo developer spreading across HN, PH, Reddit, Dev.to, X, Discord, newsletters, and podcasts on the same day will do all of them poorly. Five focused things on launch day. Expand channels in Phase 4.

**Enterprise compliance positioning.** Real but premature. You're a solo developer with zero enterprise customers. Build for individual developers first. Enterprise features emerge from team pull, not from preemptive feature building.

---

## The One-Sentence Strategy

**Own one sentence in the market: Manifold lets a Mac developer hand a real project to an AI agent without handing over the whole machine.**

That's concrete, true to the product boundary, and much harder for bigger vendors to match without caring about this exact workflow. It's also what the product actually does today — not what it might become in two years.

---

## Decision Framework

When deciding what to work on, ask in order:

1. **Can a new user finish a first run in under 10 minutes?** If not, fix onboarding before anything else.
2. **Are activated users coming back within 7 days?** If not, the product isn't sticky enough. Fix that before adding users.
3. **Does this action make the product better for the 20 people already using it?** If not, it's probably premature optimization.
4. **What's the incentive?** Who benefits from this action, and why would they care? If you can't answer clearly, it's theater.
5. **Am I doing this because it feels productive, or because it moves D7 repeat?** Conferences feel productive. Fixing the onboarding bug your design partner reported moves D7.
