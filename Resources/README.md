# Resources/

This folder contains exactly one file: `com.spatialduality.manifold.runtime.plist`, the LaunchAgent plist that registers the Manifold runtime helper with `launchd`.

Why it lives at the repo root rather than inside `Sources/ManifoldAgent/`:

- The post-build script in `project.yml` copies it from `${SRCROOT}/Resources/` into the built `.app` bundle's `Contents/Library/LaunchAgents/`. Moving the file would also require updating the post-build script and possibly adding a `resources:` declaration to the SwiftPM `ManifoldAgent` target — see the trade-off note in `docs/reorganization-plan.md`.
- The file is configuration, not source. Keeping it visible at the top level makes the LaunchAgent registration story easier to find than burying it three levels deep.

If you're touching launchd integration, `docs/architecture.md` and `docs/runtime-migration.md` are the relevant references.
