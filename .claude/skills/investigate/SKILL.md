---
name: investigate
description: Investigate Manifold bugs, build failures, runtime registration issues, XPC problems, or user-reported breakages. Use for "why is this broken", "can't add folders", startup failures, and similar debugging tasks.
---

# Investigate

Use this workflow for Manifold bugs and regressions.

## Goals

- Reproduce or localize the failure quickly.
- Find the root cause, not just the first bad symptom.
- Fix the issue and verify the real user path.

## Workflow

1. Identify the failing surface.
   App UI, launch/runtime registration, XPC transport, runtime/store logic, or package build.
2. Inspect the nearest hotspot first.
   Start with `ManifoldStore`, `AppRuntimeClient`, `ManifoldXPC`, `ManifoldAgent`, runtime startup files, and the relevant view/model pair.
3. Prefer evidence over guesses.
   Use build output, logs, runtime state, and concrete file references.
4. Fix the root cause.
   Do not stop at papering over a symptom in the UI if the real failure is launchd/XPC/runtime startup.
5. Verify.
   Use `swift build`, `swift test`, and `xcodebuild` as appropriate. For launch/runtime bugs, verify behavior too.

## Manifold-specific reminders

- Folder-add failures are often runtime registration failures, not picker bugs.
- Never leave `connectedAgent` or similar status derived from heuristics if real runtime data is available.
- Main-thread file IO and search are quality bugs even if they "work".
