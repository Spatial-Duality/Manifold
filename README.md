# Manifold

The macOS app for doing real, non-code work with Claude and Codex Mac apps. Drafts, contracts, briefs, emails, meeting notes. File by file, message by message. With version history, an AI-usage audit log, and on-device PII redaction.

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

Manifold is split into a SwiftUI app, a local XPC runtime, and thin MCP/CLI clients.

```text
SwiftUI app -> AppRuntimeClient -> ManifoldXPC -> ManifoldAgent -> ManifoldRuntime -> stores
manifold-mcp / manifold-cli ----------------------^
```

The app does not open the local stores directly. Runtime behavior goes through the XPC boundary.

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

Swift, SwiftUI, sandboxed XPC. Apple Silicon. Apache 2.0. The Mac is the runtime.

## License

Licensed under the Apache License, Version 2.0. See `LICENSE`.
