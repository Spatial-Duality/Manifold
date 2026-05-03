# Contributing to Manifold

Thanks for considering a contribution. Manifold is small and the codebase
is opinionated; the rules below exist so PRs can land quickly.

## Before you start

- **For non-trivial work, open a discussion or issue first.** Saves both of
  us from wasted effort if the design is wrong.
- **Read the [code of conduct](CODE_OF_CONDUCT.md).** It applies to all
  spaces (issues, PRs, discussions).
- **Read the [architecture overview](ARCHITECTURE.md).** Knowing where code
  belongs will save you from a lot of back-and-forth in review.

## Requirements

- macOS 26.0 or later (Apple Silicon)
- Xcode 26.0 or later
- Swift 6

The runtime is sandboxed XPC, so you cannot meaningfully run it from a
non-macOS environment.

## Build

Two equivalent paths.

Swift Package Manager (fast feedback):

```bash
swift build
swift test
```

Xcode project (for the full app bundle):

```bash
xcodebuild -project Manifold.xcodeproj \
           -scheme Manifold \
           -configuration Debug \
           -derivedDataPath /tmp/manifold-derived-data \
           build CODE_SIGNING_ALLOWED=NO
```

To run the app locally:

```bash
bash scripts/build_and_run.sh
```

To run a focused test target via Xcode:

```bash
xcodebuild -project Manifold.xcodeproj \
           -scheme Manifold \
           -configuration Debug \
           -derivedDataPath /tmp/manifold-derived-data \
           test CODE_SIGNING_ALLOWED=NO
```

## Architecture boundaries

Manifold has four important boundaries:

- The SwiftUI app talks to the runtime through `AppRuntimeClient`.
- XPC types and trust checks live in `ManifoldXPC`.
- `ManifoldRuntime` composes stores and owns runtime behavior.
- `manifold-mcp` and `manifold-cli` are thin XPC clients.

Standing access is read access. Tracked work blocks are write access. Do not
collapse those paths.

## Code style

- **SwiftFormat** is the source of truth. Config lives in `.swiftformat`.
  Run `swiftformat .` before committing. PRs that fight the formatter
  will be asked to re-run it.
- **EditorConfig** handles tabs/whitespace. Most editors pick `.editorconfig`
  up automatically.
- **No `print(...)` in shipped code.** Use the structured logger.
- **No `force-unwrap` on values that cross the XPC boundary.** Treat the
  other side of XPC the way you'd treat an external API.

## Commit conventions

- Subject line: 50 characters, imperative mood. "Fix X" not "Fixed X" or
  "Fixes X".
- Body: wrap at 72. Explain the *why*, not the *what*. The diff already
  shows the what.
- One logical change per commit. Refactors and behavior changes go in
  separate commits.
- Reference issues and advisories by number, e.g. `Fixes #42`.

## Pull requests

- **Branch from `main`.** Rebase, don't merge, when bringing your branch
  up to date.
- **Tests pass locally** (`swift test`) before you open the PR.
- **One PR per logical change.** Bundling unrelated changes makes review
  slow and revert hard.
- **Fill out the PR template.** The checklist exists for a reason.
- **Be ready for review feedback.** We try to be quick (most PRs get a
  first review within a few days). Drive-by reviewers are welcome.

## What we say no to

- Telemetry of any kind (no opt-out fallback, no "anonymous usage").
- Network requests that aren't strictly necessary for an explicit user
  action. Manifold's promise is "fully on-device" and we mean it.
- Hard dependencies on cloud services for core flows.
- New file-types or mailbox providers without an audit-log story for what
  the AI gets to see.

If your idea touches any of those, propose it in an issue first so we can
talk before you build.

## Reporting bugs and requesting features

Use the issue forms:
- [Bug report](https://github.com/Spatial-Duality/Manifold/issues/new?template=bug_report.yml)
- [Feature request](https://github.com/Spatial-Duality/Manifold/issues/new?template=feature_request.yml)

For security issues, see [SECURITY.md](SECURITY.md). Please do not open a
public issue for vulnerabilities.

## License

By contributing, you agree your contributions are licensed under the
[Apache License 2.0](LICENSE), the same license as Manifold itself.
