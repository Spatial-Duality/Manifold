# Manifold Onboarding Design Guide

A research-backed framework for Manifold's first-run experience. This is not "remove all friction." It's "design the right friction so users understand what they're trusting Manifold with and feel confident delegating to AI agents."

---

## Part 1: The Theory — Why Friction Isn't the Enemy

### The Wrong Mental Model

Most onboarding advice says "reduce friction." That's half right and half catastrophically wrong. The full picture comes from three research traditions that, taken together, tell a more honest story:

**BJ Fogg's Behavior Model (B = MAP):** Behavior happens when Motivation, Ability, and Prompt converge at the same moment. Reduce friction *at the action stage* (make it easy to do the thing), but this says nothing about whether the user should understand what they're doing.

**Nir Eyal's Hook Model (Trigger → Action → Reward → Investment):** The investment phase is where users *put effort in* — and that effort increases perceived value (the IKEA effect). Eyal explicitly warns: "If the app is too easy and requires no investment at all, the reward might not feel that satisfying." Any.do outperformed Astrid by *requiring* users to complete tutorial tasks rather than letting them skip.

**Robert Bjork's Desirable Difficulties:** Cognitive psychology research showing that conditions which slow immediate performance *improve long-term retention by 60%.* The mechanism: effort during learning strengthens memory traces. Easy onboarding = forgotten onboarding.

### The Synthesis for Manifold

Manifold is a trust tool. The user is deciding: "Do I trust this app enough to let AI agents work on my files through it?" That decision requires understanding, not just speed. If a user clicks through setup in 30 seconds without understanding what "standing access" or "tracked work block" means, they haven't onboarded — they've just dismissed a dialog.

**The principle: minimize friction on *mechanical* steps (signing in, connecting, selecting folders) but add intentional friction on *understanding* steps (what access means, what versioning protects, what the audit trail shows).**

This is exactly what Superhuman discovered. Their optional onboarding had 15% attendance. When they made it mandatory and full-screen, completion went to 98% and activation improved 2x. The friction of being *required to learn* produced better outcomes than the frictionlessness of being *allowed to skip*.

### Five Types of Productive Friction (from Smashing Magazine's framework)

| Type | When to use | Manifold application |
|------|-------------|---------------------|
| **Error prevention** | Before irreversible actions | Before granting agent access to sensitive folders |
| **Security enhancement** | When trust is being established | Showing exactly what agents will see before confirming |
| **Perceived process quality** | When speed would feel cheap | The "reviewing your files" step should feel thorough, not instant |
| **Behavior nudging** | When the default path matters | Defaulting to read-only standing access, requiring explicit action for write access |
| **Value creation** | When effort increases ownership | Having users *choose* their first folders (not auto-detecting everything) |

### What Apple Says (HIG Onboarding Guidelines)

Apple's guidance is complementary, not contradictory:
- "Help people accomplish something as soon as they start your app" — this means *get to value fast*, not *skip setup*
- "Get setup information from existing device settings and defaults" — reduce mechanical friction
- "Give people time to start enjoying your app before showing supplementary information" — don't front-load everything
- "Well-designed interfaces that follow established patterns require less explanation" — invest in UI clarity so the onboarding can focus on *concepts* not *button locations*

---

## Part 2: Manifold's Onboarding Problem

### What Exists Today

The current `SetupAssistantView.swift` is a 4-screen wizard:
1. **Welcome** — "Manifold controls what AI agents see on your Mac." Continue button.
2. **Connect Apps** — Inline health checks for Claude and Codex. Install MCP button. Skip option.
3. **Add Data** — Folder picker and email account setup. Skip option.
4. **Review & Finish** — Summary of what was configured. Done button.

### What's Wrong With It

The current flow commits three onboarding sins identified by the research:

**Sin 1: Configuration before demonstration.** The user is asked to connect agents and add folders *before seeing what Manifold does with them.* This violates the core insight from Ramli John's EUREKA framework: "minimize the time it takes for new users to experience a product's value." Configuring MCP and selecting folders is investment *before* any reward.

**Sin 2: Everything is skippable.** Both "Connect Apps" and "Add Data" have "Skip" buttons. Superhuman found that optional onboarding had 15% completion vs. 98% for mandatory. When users skip the core setup, they land in an empty app with no data, no connections, and no understanding of why they installed it. They bounce.

**Sin 3: No "aha moment."** The user never sees Manifold *working*. They never see: "Here's a file an AI agent changed. Here's the version history. Here's how you restore it." The LAUNCH-PLAN.md correctly identifies this gap — "observation-first onboarding with demo mode" is listed as a must-build.

### The Aha Moment for Manifold

Using Superhuman's framework (Signed Up → Setup Moment → Aha Moment → Habit Moment → Engaged):

- **Setup Moment:** Agent connected + at least one folder added
- **Aha Moment:** User sees a real (or simulated) agent interaction — what was read, what was changed, what the version history looks like, and restores a file
- **Habit Moment:** User runs a second agent session through Manifold and checks the activity log unprompted
- **Activation metric:** D7 repeat (second watched session within 7 days — already identified in your launch plan)

---

## Part 3: The Redesigned Flow

### Principle: Show Before Ask

Reverse the current order. Show what Manifold does *first*, then ask the user to set it up. This is the "observation-first" approach from the launch plan, grounded in the research.

### The Six Screens

#### Screen 1: Welcome (5 seconds)
**Purpose:** Orientation + emotional hook.

```
[Manifold icon]

"See what AI agents changed.
Restore any edit.
Keep your originals safe."

[Get Started]
```

- One sentence. Not three paragraphs.
- No feature list. No bullet points.
- The emotional hook is safety ("keep your originals safe"), not control ("govern your AI agents").
- This screen lasts 5 seconds max. Don't overload it.

#### Screen 2: The Demo (60-90 seconds) — THIS IS THE KEY SCREEN

**Purpose:** The aha moment. Before the user configures anything, show them a complete Manifold workflow using simulated data.

**What to show (Superhuman's "synthetic inbox" applied to Manifold):**

A pre-populated simulation showing:
1. A project folder (`~/Projects/my-app/`) with 5-6 files
2. A simulated Claude session that read 3 files, modified 2
3. The activity log showing what happened
4. The version history showing before/after for one modified file
5. A "restore" action on a bad edit — the user taps "Restore" and sees the file revert

**Design details:**
- Full-screen, not a modal. Superhuman found full-screen onboarding increased feature adoption by 20%.
- Interactive, not a slideshow. The user clicks through the demo steps. They *do* the restore action. Bjork's research: doing is 60% better than watching for retention.
- Clearly labeled as demo data. "This is a simulation. Your real files will appear after setup."
- No skip button on this screen. This is the mandatory productive friction. If they don't see the demo, they won't understand the product.

**The productive friction here:** The user is *required* to spend 60-90 seconds experiencing the product before configuring it. This feels slow compared to "skip everything." But Superhuman's data shows this converts 2x better because users understand what they're setting up *for*.

**What this teaches without saying it:**
- Manifold works at the file level, not the prompt level
- Every agent action is logged and visible
- File versions are automatic and restorable
- The user is in control — they initiate restores, not the tool

#### Screen 3: Connect Your Agent (the productive friction screen)

**Purpose:** First real configuration step. Minimum one agent connected.

**What changed from current:** 
- No "Skip" button. At least one agent must be connected (or the user explicitly says "I'll do this later and I understand the app won't work yet").
- The screen shows *what connecting means* — not just health check dots. Show: "When connected, Manifold will record what Claude reads and writes through the MCP bridge. This is what you saw in the demo."
- The "Install MCP" button should have an inline explanation: "This adds Manifold as a tool server. Claude will route file operations through Manifold instead of accessing your disk directly."

**Why this friction is productive:** The user needs to understand *what they're connecting and why.* A green checkmark next to "Connection verified" doesn't convey understanding. The brief explanation ("route file operations through Manifold") builds the mental model that makes the rest of the app make sense.

#### Screen 4: Choose Your First Folder (investment step)

**Purpose:** The user's first investment. Choosing what to protect.

**What changed from current:**
- Frame as protection, not sharing: "Choose a folder to protect" not "Choose what to share"
- Show the sensitivity scanner results (when built): after selecting a folder, briefly show "Found 3 files matching sensitive patterns (.env, .pem). These will be excluded by default."
- Suggest a starter folder: "Start with a project you're actively using AI tools on. You can add more anytime."
- Require at least one folder. No skip.

**Why requiring this is productive friction:** The IKEA effect — users who choose their first folder have invested in the setup. They're more likely to return. An empty Manifold with no folders is worthless, and letting users reach that state is a design failure.

**Why showing sensitivity results is productive friction:** The brief pause to review excluded files builds trust. "Oh, Manifold caught my .env file and excluded it automatically. This thing is actually looking out for me." This is the Wells Fargo eye-scan principle — a brief moment of visible thoroughness increases perceived security.

#### Screen 5: Your Workspace Is Ready (reward)

**Purpose:** Show the real app, populated with their data, connected to their agent.

- Display the Overview tab with their connected agent(s) and folder(s)
- Show the activity panel (empty, but ready)
- Brief note: "The next time Claude or Codex accesses your files through Manifold, you'll see it here."

This is the transition from onboarding to product. No "Done" button that dismisses to a blank screen. The user is already *in* the product.

#### Screen 6: (Deferred) First Real Session

This isn't a setup screen — it's what happens when the user actually uses an AI agent after setup. The first time activity appears in the log, consider a subtle highlight or callout: "First tracked activity — Claude read 2 files from my-app/." This closes the loop from the demo in Screen 2 to real usage.

---

## Part 4: The Friction Map

For every step in the onboarding, here's the explicit friction decision:

| Step | Friction level | Why |
|------|---------------|-----|
| Welcome screen | Zero friction | Get out of the way. 5 seconds. |
| Demo walkthrough | **High friction** (mandatory, 60-90 sec) | This is where understanding happens. Skipping this = user doesn't know what they installed. |
| Agent connection | **Medium friction** (required, with explanation) | User must understand what "connecting" means, not just click a green button. |
| Folder selection | **Medium friction** (required, shows sensitivity scan) | Investment + trust-building. The sensitivity scan is productive friction that increases confidence. |
| Workspace ready | Zero friction | Reward moment. Show the real product, populated. |
| First real activity | Low friction (subtle highlight) | Close the loop. Reinforce the demo. |

---

## Part 5: Anti-Patterns to Avoid

### 1. The Grand Tour

Don't add tooltips pointing to every UI element ("This is the sidebar! This is the toolbar! This is the activity log!"). Samuel Hulick's core insight: "Don't fix a broken interface by overlaying yet another interface on top of it." If the UI needs a tour to be understood, the UI needs redesign, not a tour.

### 2. Permission Front-Loading

Don't ask for all permissions upfront (Full Disk Access, folder access, network access, notification permission). Apple's HIG: "Give people time to start enjoying your app before showing supplementary information." Request permissions at the moment they're needed, with context for why.

### 3. Feature Dumping

The onboarding should teach ONE thing: "Manifold shows you what AI agents did and lets you undo it." Not: work blocks, standing access, exposure records, sensitivity rules, email governance, MCP protocol details. Those are features the user discovers as they use the product. Front-loading them creates cognitive overload.

### 4. The Empty State Trap

Never let a user complete onboarding and land on a blank screen. If they skipped connecting an agent, show a clear "Not connected — here's what to do" state, not an empty activity log with no explanation.

### 5. Congratulations Theater

The current Screen 4 shows a checkmark and says "You're ready." This is feel-good friction — it takes time but adds no value. Replace it with the actual product, populated with the user's data. The reward of a good onboarding is *being in the product*, not being told you're ready for the product.

---

## Part 6: Measurement

### What to Track

| Metric | What it tells you | Target |
|--------|-------------------|--------|
| Demo completion rate | Are users watching the demo or finding a way to skip? | >90% (it's mandatory, but track attempts to dismiss) |
| Time in demo | Are they clicking through quickly or engaging? | 45-90 seconds (too fast = not reading, too slow = confused) |
| Agent connection rate at onboarding | Are users connecting at least one agent? | >70% |
| Folder selection rate at onboarding | Are users adding at least one folder? | >80% |
| Time to first real activity | How long after setup before an agent actually uses Manifold? | <24 hours |
| D7 repeat | Second watched session within 7 days | This is the number that matters |

### The Metric That Actually Matters

Everything above feeds into one question: **does the user run a second agent session through Manifold within 7 days?** If yes, onboarding worked. If no, it didn't — regardless of how many screens they completed or how "smooth" the flow felt.

This is Bjork's insight applied to product: easy onboarding feels good in the moment but produces weaker retention. The demo adds effort, the required agent connection adds effort, the folder selection adds effort — and all of that effort makes the user more likely to come back because they *understand what they set up and why*.

---

## Part 7: Implementation Priorities

### What to Build (in order)

**1. The demo screen (~3 days)**
This is the highest-leverage change. It requires:
- A set of simulated data (fake project files, fake agent session, fake activity log entries, fake version history)
- An interactive walkthrough UI that steps through the simulation
- A "Restore" action the user performs on a simulated bad edit
- Clear labeling that this is a simulation

**2. Reorder the existing screens (~0.5 day)**
Move the demo to Screen 2 (before Connect Apps). Remove skip buttons from Connect Apps and Add Data. Replace the Review & Finish screen with a live view of the real app.

**3. Folder sensitivity scan integration (~1 day, depends on FileSensitivityScanner)**
After the user selects a folder, briefly show what sensitive files were auto-excluded. This is the trust-building friction moment.

**4. First-activity highlight (~0.5 day)**
When the first real agent activity appears after onboarding, add a subtle callout connecting it back to the demo: "This is real — Claude just read 2 files from your project."

### What NOT to Build

- A product tour / tooltip overlay
- A video walkthrough (the interactive demo is better — doing beats watching)
- Separate onboarding for each feature area
- An achievement/gamification system
- A progress bar across the entire app ("You've completed 3 of 7 setup steps!")

---

## Part 8: Reference — The Books and Frameworks

### Primary Sources

| Source | Key Insight for Manifold |
|--------|--------------------------|
| **Hooked** (Nir Eyal, 2014) | Investment during onboarding increases perceived value. The demo is the reward; folder selection is the investment. |
| **Tiny Habits** / **Behavior Model** (BJ Fogg) | B = MAP. Motivation is highest at first launch — use it. Don't waste it on configuration. |
| **Desirable Difficulties** (Robert Bjork, 1994) | Effort during learning improves retention by 60%. A mandatory demo beats a skippable one. |
| **Product-Led Onboarding** (Ramli John) | EUREKA framework + Bowling Alley. Define the activation metric (D7 repeat). Use bumpers to guide toward it. |
| **The Elements of User Onboarding** (Samuel Hulick) | "Don't fix a broken interface by overlaying another interface." Fix the UI, not the onboarding. |
| **Don't Make Me Think** (Steve Krug) | Minimize *unnecessary* cognitive load. But Manifold's onboarding requires *necessary* cognitive load — understanding what access means. |
| **Nudge** (Thaler & Sunstein) | Default to the safe option (read-only standing access). Make the risky option (write access) require deliberate choice. |
| **Superhuman's Onboarding Playbook** (First Round Review) | Full-screen, mandatory, interactive > optional, tucked-away, passive. Synthetic environments for safe practice. |

### The Friction Design Literature

| Source | Key Insight |
|--------|-------------|
| **Smashing Magazine** (2018, "Friction as Design Tool") | Five types of productive friction. Transparency about *why* friction exists reduces frustration. |
| **UXPA Journal** (Ericson, "Reimagining Friction") | Friction is neutral, not negative. Design it intentionally. Match friction to context. |
| **Bjork Lab, UCLA** | Performance vs. learning distinction: easy conditions improve immediate performance but hurt long-term retention. |
| **The IKEA Effect** (Norton, Mochon, Ariely, 2012) | Labor increases perceived value. Users who *build* their Manifold setup value it more than users who auto-configure. |

### Apple-Specific

| Source | Key Insight |
|--------|-------------|
| **Apple HIG: Onboarding** | Get to value fast. Use device defaults for mechanical setup. Don't front-load permissions. |
| **Apple HIG: Launching** | First launch should feel fast and purposeful. Don't ask for reviews or supplementary info before value. |
| **WWDC Sessions on App Lifecycle** | The first 30 seconds determine whether the user keeps or deletes the app. |
