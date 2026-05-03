# Manifold

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/Spatial-Duality/Manifold?include_prereleases&sort=semver)](https://github.com/Spatial-Duality/Manifold/releases)
[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-A89E91)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-only-141413)](https://www.apple.com/mac/)

Manifold is a native macOS permission layer for doing real work with Claude and Codex: drafts, contracts, briefs, emails, meeting notes. You choose the files and messages they can see. Manifold routes that access through a local runtime, records what crossed the boundary, and keeps versions you can roll back.

Site: [spatialduality.com/manifold](https://spatialduality.com/manifold/).

## Download

Public builds are distributed from [GitHub Releases](https://github.com/Spatial-Duality/Manifold/releases).

Manifold is a native macOS app. Release builds are Developer ID signed, notarized, and updated with Sparkle.

## What it gives you that the AI apps don't

- **Multi-inbox.** Apple, Google, Microsoft 365, IMAP. All in one view. None shared with any AI by default.
- **Version history per file.** AI edits your brief; you see the diff and can roll back from any new chat, even on a different AI.
- **An AI-usage audit log that's yours to keep.** What each AI read, what it changed, when. Lives on your Mac, independent of which AI did the work.
- **On-device PII redaction.** OpenAI Privacy Filter running on MLX. Catches 2FA codes, addresses, names, and account numbers before they leave the device.

## Architecture

Manifold is split into a SwiftUI app, a local XPC runtime, and thin MCP/CLI clients. Claude and Codex talk to `manifold-mcp`; the runtime verifies the caller, resolves policy, runs local privacy checks, and records the exposure before returning data.

```text
SwiftUI app -> AppRuntimeClient -> ManifoldXPC -> ManifoldAgent -> ManifoldRuntime -> stores
manifold-mcp / manifold-cli ----------------------^
```

The app does not open the local stores directly. Runtime behavior goes through the XPC boundary. Manifold is not a global sandbox; it governs the traffic routed through its MCP server.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the longer one-page overview.

## Build from source

Requirements:

- macOS 26.0 or later
- Xcode 26.0 or later
- Swift 6
- Apple Silicon Mac

Package build and tests:

```bash
swift build
swift test
```

App build:

```bash
xcodebuild -project Manifold.xcodeproj \
           -scheme Manifold \
           -configuration Debug \
           -derivedDataPath /tmp/manifold-derived-data \
           build CODE_SIGNING_ALLOWED=NO
```

Run locally:

```bash
bash scripts/build_and_run.sh
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Report vulnerabilities through the private channels in [SECURITY.md](SECURITY.md), not public issues.

Release notes live in [CHANGELOG.md](CHANGELOG.md).

## Native

Swift, SwiftUI, XPC, `launchd`, Keychain, SQLite. Apple Silicon. Apache 2.0. The Mac is the runtime.

## License

Licensed under the Apache License, Version 2.0. See `LICENSE`.
