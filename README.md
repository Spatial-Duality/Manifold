# Manifold

Choose what AI agents can see. Get everything back.

Manifold is a native macOS app that controls which files and emails AI agents can access. Every file they touch is backed up. Restore any version with one click.

## How it works

1. **Pick files** — Select files and folders through Finder. Connect Apple Mail for email context.
2. **Grant access** — Click "Grant to Claude" to start a tracked access run. Manifold syncs your files into a managed workspace.
3. **Work normally** — Claude works in the workspace. Manifold watches every change via FSEvents.
4. **Restore anything** — See every modification in a timeline. Restore any version. Promote approved changes back to your real files.

## The design

Most tools in this space do **deny-first sandboxing**: block the agent from touching things. Manifold does **allow-first workspace curation**: give the agent exactly what it needs.

You pick files in a Finder dialog. That's it. No sandbox profiles, no config files, no technical knowledge required.

The agent works in a managed copy of your files. Your originals are never modified. Every change is versioned. Every version is restorable.

## What Manifold controls (and what it doesn't)

Manifold controls **local files in the managed workspace**. It tracks and backs up every write. It lets you restore any previous state.

Manifold does **not** control agent connectors, plugins, computer use, or network access. Those capabilities are outside the workspace boundary. The boundary is honest and visible.

## Architecture

- **ManifoldKit** — Swift package. Content-addressed blob store (SHA-256 dedup), per-write snapshots, FSEvents monitoring, managed workspaces, access run lifecycle.
- **Manifold.app** — Native SwiftUI. Menu bar + main window. Sources, Profiles, Activity views. Liquid Glass on macOS 26.
- **manifold-cli** — Terminal interface. `init`, `grant`, `watch`, `log`, `restore`, `promote`.

28 tests. All passing.

## Status

Early development. The core library works. The app shell exists. Working toward V1 with Apple Mail integration, onboarding, and macOS notifications.

## Requirements

- macOS 14+
- Swift 6.0+
- Xcode 16+ (for building the app)

## Building

```bash
# Build the library + CLI
swift build

# Run tests
swift test

# Build the app
cd ManifoldApp && ./build.sh
```

## License

MIT
