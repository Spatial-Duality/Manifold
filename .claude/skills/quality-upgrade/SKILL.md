---
name: quality-upgrade
description: Raise Manifold toward a Pixelmator-quality macOS app. Use for implementation work that upgrades reliability, responsiveness, navigation, and desktop polish.
---

# Quality Upgrade

Use this when the goal is not just "make it work", but "make it feel like a serious Mac app".

## Execution Order

Read `design/APP-QUALITY-ROADMAP.md` before making a plan or code changes.

1. Runtime reliability
   Fix LaunchAgent/XPC/runtime registration and startup truth first.
2. Honest state
   Remove guessed connection/agent state.
3. Performance
   Move file walking, content search, and other heavy work off the main actor.
4. Navigation coherence
   Fix email/files selection flows so sidebar, list, detail, and inspector state stay aligned.
5. Desktop surface upgrades
   Improve data-heavy views with stronger macOS-native affordances.
6. Final polish
   Tighten hierarchy, spacing, copy, and motion after the flows are solid.

## Expected verification

- `swift build`
- `swift test`
- `xcodebuild -project Manifold.xcodeproj -scheme Manifold -configuration Debug -derivedDataPath /tmp/manifold-derived-data build CODE_SIGNING_ALLOWED=NO`

## Suggested subagents

- `runtime-reliability` for launchd/XPC/runtime startup work
- `performance-auditor` for heavy IO and responsiveness issues
- `ui-polish` for macOS interaction and visual upgrades
