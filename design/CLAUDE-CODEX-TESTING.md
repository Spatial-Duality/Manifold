# Testing Manifold with Xcode, Codex, and Claude

This document is the practical test loop for Manifold as it exists today.

The goal is not just to see whether the app launches. The goal is to verify the governed path:

`pick data -> route access through Manifold -> record exposure -> review edits -> reuse history`

## What to test

Manifold is only proving its core value when all of these work together:

- the macOS app launches cleanly from a local build
- Claude and Codex can see the Manifold MCP server
- file and email access go through Manifold tools, not only native agent tools
- reads and searches are recorded
- edits become tracked work
- history is visible later through the app and Manifold tools

## Research Summary

### Codex desktop app

Codex works from the current project or a managed worktree and has its own native sandbox and approvals model. For Manifold testing, that means:

- Codex may have native file or command capabilities outside Manifold
- you need to explicitly ask Codex to use the `Manifold MCP server only` when you want to validate governed behavior
- Codex benefits from a project-local run action, which this repo now provides through `.codex/environments/environment.toml`

### Claude Desktop / Cowork

Claude Desktop can gain local capability through desktop extensions and hosted connectors. Cowork can also work in a VM or act on the real desktop through computer use. For Manifold testing, that means:

- Claude may also have capabilities outside Manifold
- you should explicitly ask Claude to use `Manifold MCP server only` for file and email access when validating the governed path
- activity outside the Manifold path is outside Manifold coverage in V1

## Local Run Loop

### Xcode

Use the `Manifold` scheme in [Manifold.xcodeproj](../Manifold.xcodeproj).

Recommended paths:

- Build in Xcode when you are changing app code and want the normal editor/debugger loop
- Use [script/build_and_run.sh](../script/build_and_run.sh) when you want a repeatable shell entrypoint

Available commands:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

### Codex desktop app

This repo now includes [.codex/environments/environment.toml](../.codex/environments/environment.toml), so the Codex desktop app can expose a `Run` action wired to `./script/build_and_run.sh`.

That gives you a consistent local build and run loop without retyping `xcodebuild` commands.

## Agent Setup

### Claude

Manifold writes Claude Desktop MCP config to:

- `~/Library/Application Support/Claude/claude_desktop_config.json`

It also writes Claude Code config to:

- `~/.claude/settings.json`

In the app, use:

- `Settings > AI Apps > Connect Claude`
- or the setup assistant's `Install or Repair Manifold MCP`

Then fully quit and relaunch Claude.

### Codex

Manifold writes Codex MCP config to:

- `~/.codex/config.toml`

In the app, use:

- `Settings > AI Apps > Connect Codex`
- or the setup assistant's `Install or Repair Manifold MCP`

Then fully quit and relaunch Codex.

## Recommended Test Dataset

Create a small controlled dataset:

- `claude-only/marker.txt`
- `codex-only/marker.txt`
- `shared/worklog.md`

Suggested file contents:

- `claude-only/marker.txt`: `CLAUDE_ONLY_MARKER`
- `codex-only/marker.txt`: `CODEX_ONLY_MARKER`
- `shared/worklog.md`: `Initial shared worklog`

For email, add at least:

- one clearly allowed test email
- one clearly blocked test email
- one email containing `MANIFOLD_EMAIL_TEST`

Then set policy in Manifold:

- Claude gets `claude-only` and `shared`
- Codex gets `codex-only` and `shared`
- do not cross-share the private folders

## Governed Path Prompts

### 1. Coverage sanity check

Use this in Claude or Codex:

```text
Use the Manifold MCP server only for file and email access in this task. First call get_status and get_coverage_status, then explain what access path is active.
```

Expected result:

- coverage should show `Manifold-Routed` when the agent is using Manifold tools

### 2. File visibility test

```text
Use the Manifold MCP server only. Call list_files and read the marker files you can access. Tell me which folders are visible to you.
```

Expected result:

- Claude sees `claude-only` and `shared`
- Codex sees `codex-only` and `shared`

### 3. Email visibility test

```text
Use the Manifold MCP server only. Search emails for MANIFOLD_EMAIL_TEST, list accessible matches, and read the allowed message.
```

Expected result:

- allowed email is visible
- blocked email is hidden or denied by policy

### 4. Tracked edit test

```text
Use the Manifold MCP server only. Update shared/worklog.md by appending one line saying which agent performed this test.
```

Expected result:

- the edit should route into tracked work instead of silently changing originals
- the app should show a reviewable change flow

### 5. History and context test

After one agent edits `shared/worklog.md`, ask the other:

```text
Use the Manifold MCP server only. Call get_file_history_context for shared/worklog.md and summarize the recent governed history around that file.
```

Expected result:

- the second agent can use Manifold's local history as durable context

## What to watch in the app

- `Overview`: connected agent state, coverage, and access summary
- `Files`: whether the shared and private boundaries are correct
- `Emails > Email Rules`: whether allow and block behavior matches policy
- `Activity`: reads, searches, and denied attempts
- `Tracked Work Block` review flow: promote, discard, restore
- `Versions`: whether governed edits become inspectable history

## Current Known Testing Risks

- Claude and Codex both have native capabilities outside Manifold, so prompts must explicitly say `use the Manifold MCP server only` when validating governed behavior
- Claude Desktop/Cowork and Codex do not expose local capability in the same way, so a native success does not necessarily prove Manifold coverage
- If the app and helper are built from different versions, startup and restart noise can make early tests confusing
- The highest-value test is not "can the agent read a file"; it is "did the read show up in Activity and did the edit become tracked work"
