# Getting Started

Manifold is the user-owned control plane that sits beside Claude and Codex, recording what they actually saw and changed on your Mac, across sessions and across vendors.

This guide gets you from clone to a first governed session in about 10 minutes.

## Before You Start

- macOS 26.0 or later
- Xcode 26.0 or later
- Swift 6
- A local signing team in Xcode for running the app target
- Claude Desktop, Codex, or both installed if you want to test live agent integration

## 1. Clone And Build

```bash
git clone <repo-url>
cd Manifold
swift build
swift test
```

Then open the app project:

```bash
open Manifold.xcodeproj
```

In Xcode:

1. Select the `Manifold` scheme.
2. Choose your personal signing team in `Signing & Capabilities`.
3. Change the bundle identifier if needed for local builds.
4. Run the app.

If you prefer a shell-first verification pass:

```bash
xcodebuild -project Manifold.xcodeproj \
  -scheme Manifold \
  -configuration Debug \
  -derivedDataPath /tmp/manifold-derived-data \
  build \
  CODE_SIGNING_ALLOWED=NO
```

## 2. Complete First-Run Setup

When Manifold opens:

1. Go through the setup assistant.
2. Connect Claude, Codex, or both.
3. Add one or two folders you want to govern.
4. Optionally add an email account or archive.

The key idea is simple:

- Manifold does not expose your whole Mac.
- You pick the files, folders, and email access that each agent can use.

## 3. Install The MCP Bridge

Manifold uses `manifold-mcp` as the V1 shared agent path.

The easiest path is the app’s built-in install flow:

- In setup or Settings, choose the install/repair action for Manifold MCP.

If you need the manual route, see [mcp-integration.md](mcp-integration.md).

## 4. Share A Small Test Scope

For a safe first run, create or select:

- one folder for Claude
- one folder for Codex
- one shared folder

Example:

```text
shared/
claude-only/
codex-only/
```

Then in Manifold:

1. Share `shared/` with both.
2. Share `claude-only/` only with Claude.
3. Share `codex-only/` only with Codex.

## 5. Run A Governed Read

In Claude or Codex, use a prompt like:

```text
Use the Manifold MCP server only for file and email access in this task.
List the files I can access and read the marker files that are available.
```

What to expect:

- the agent sees only the scope you shared with it
- Manifold records the read/search through the governed path
- the Overview and Activity views update

## 6. Run A Governed Edit

Ask the agent to change a file in the shared scope:

```text
Use the Manifold MCP server only. Update shared/worklog.md with one short line saying which agent made this change.
```

What to expect:

- Manifold routes the edit into a `Tracked Work Block`
- you can review the diff before promoting anything back to originals
- you can discard or restore instead of accepting the change

## 7. Review What Happened

In Manifold, check:

- `Overview` for current access and coverage state
- `Files` for governed sources
- `Emails` for rules and governed visibility
- `Activity` for reads, denials, and exposure history
- `Versions` for tracked file history

## 8. Test With Both Claude And Codex

For a more detailed live workflow, use:

- [../design/CLAUDE-CODEX-TESTING.md](../design/CLAUDE-CODEX-TESTING.md)

That guide covers:

- Xcode run loops
- Codex desktop testing
- Claude Desktop testing
- prompts that force the governed Manifold path instead of native vendor tools

## Where To Go Next

- Want the system shape? Read [architecture.md](architecture.md).
- Want the adapter details? Read [mcp-integration.md](mcp-integration.md).
- Want the product rationale? Read [design-decisions.md](design-decisions.md).
- Want the full product definition? Read [../design/PRODUCT-SPEC.md](../design/PRODUCT-SPEC.md).
