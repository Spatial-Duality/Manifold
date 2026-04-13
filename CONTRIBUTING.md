# Contributing to Manifold

## Prerequisites

- macOS 26.0 or later
- Xcode 26.0 or later (Swift 6)
- An Apple Developer account (free tier works for local builds)

## Building

### Swift packages (runtime, CLI, MCP server)

```bash
swift build
swift test
```

### macOS app (Xcode)

1. Open `Manifold.xcodeproj` in Xcode
2. Select your personal team under **Signing & Capabilities**
3. Change the bundle identifier to your own (e.g., `com.yourname.manifold`) — the default `com.spatialduality.manifold` is reserved for official builds
4. Build and run the **Manifold** scheme

### Quick build script

```bash
bash script/build_and_run.sh
```

## Code structure

- `Sources/ManifoldKit/` — core stores, models, and domain logic
- `Sources/ManifoldRuntime/` — composition root and policy engine
- `Sources/ManifoldXPC/` — XPC protocol and service
- `Sources/ManifoldMCP/` — MCP server adapter
- `Sources/ManifoldCLI/` — command-line interface
- `Sources/ManifoldAgent/` — LaunchAgent entry point
- `ManifoldApp/` — SwiftUI desktop application
- `Tests/` — test suite

## Making changes

1. Fork the repo and create a feature branch
2. Make your changes
3. Run `swift build` and `swift test` to verify
4. For app changes, also verify with: `xcodebuild -project Manifold.xcodeproj -scheme Manifold -configuration Debug build CODE_SIGNING_ALLOWED=NO`
5. Open a pull request with a clear description of what changed and why

If your change affects the product story or first-run experience, update the docs that match the audience:

- `README.md` for first impression and quick start
- `docs/` for outsider-facing usage and architecture
- `design/` for the deeper product and implementation source of truth

## Commit messages

Write concise commit messages that explain the *why*, not just the *what*. One sentence is usually enough.

## Code style

- Swift 6 strict concurrency
- Prefer `os.Logger` over `print()` in library/runtime code
- `print()` is fine in CLI tools
- Follow existing patterns in the codebase
- Add `///` doc comments to public API surfaces that contributors are likely to option-click in Xcode
- Use inline comments to explain invariants, trust boundaries, or platform quirks, not obvious line-by-line mechanics

## Reporting issues

Use GitHub Issues. For security vulnerabilities, see [SECURITY.md](SECURITY.md).
