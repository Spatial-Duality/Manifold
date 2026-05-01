# Post-Reorganization Status

Snapshot from the reorg pass on 2026-05-01. Read once, act on the punch-list, then delete this file.

## What changed (committed work to review)

- **Brand**: `brand/mark-light.svg` and `brand/mark-dark.svg` exist (placeholder system-mono mark — replace with hand-drawn paths when finalised). Loose icon SVGs and the `.afdesign` source are now under `brand/assets/legacy/` and `brand/assets/sources/`. Older mark variants moved to `brand/exploration/`. Python build tools moved to `brand/scripts/`.
- **Docs**: `design/` collapsed into `docs/`. Canonical references promoted (lowercase-kebab filenames). Iteration drafts (01-…-13-) and retired plans moved to `docs/archive/`. HTML mockups moved to `docs/mockups/`. Swift spike moved to `docs/archive/swift-spike/`. New `docs/README.md` indexes everything.
- **Codex tooling**: `codex/AGENTS.md` and `codex/CODEX-PROMPTS.md` moved to `.trash-pending-user-delete/` (not for the public repo). Phase migration history (`PLANS.md`, `phase-1`…`phase-8`) preserved in `docs/archive/runtime-migration-phases/`.
- **TODOS.md** archived as `docs/archive/2026-04-todos.md`.
- **Scripts**: `script/` renamed to `scripts/`; `test-e2e.sh` moved into it. References in `CONTRIBUTING.md`, `docs/claude-codex-testing.md`, `docs/ui-map.md`, and `scripts/run_self_improvement_loop.sh` updated.
- **CI baseline**: intentionally **not** added. Per your preference, GitHub Actions / dependabot / CODEOWNERS are out — manual push process retains full control. Verification stays local via the commands in `CLAUDE.md` and the `xcodebuild` invocation in this file (item 4 below).
- **Tooling**: `.editorconfig`, `.swiftformat`.
- **Resources/**: kept at root (moving it would touch the post-build script in `project.yml` — risk vs. cleanup tradeoff went the wrong way; see `Resources/README.md`).
- **AI-tool scaffolding** (`.claude/`, `.codex/`, `codex/`, `CLAUDE.md`): untracked via `git rm --cached`. Files stay on your local disk; future commits won't include them. `.gitignore` updated to keep them excluded going forward.
- **VERSION** file moved to `.trash-pending-user-delete/`. Source of truth for the release version is now `project.yml` (`MARKETING_VERSION`).
- **README.md**: hero `<picture>` no longer broken (mark-light/mark-dark now exist). All link targets resolve to existing files.

## What you have to do (manual cleanup)

The in-session sandbox could move and rename files, but Xcode-protected build outputs and a few stuck files refused deletion. One script handles all of it:

```bash
cd /Users/x01/Developer/Projects/Manifold
bash scripts/cleanup-pending.sh
```

That removes:

- `.deriveddata-*` (12 directories, ~9 GB)
- `.build/` (~2 GB)
- `.gstack/`
- `default.profraw`
- `SVG External logo files/` (third-party trademarked marks, untracked)
- empty leftover directories (`design/`, `design/html/`, `codex/`, `codex/tasks/`, `.github/workflows/`)
- `.trash-pending-user-delete/` (parking-lot dir containing the old `VERSION`, `AGENTS.md`, `CODEX-PROMPTS.md`, etc.)

Some build outputs are `chflags`-protected. The script will retry with `sudo` automatically if the first pass leaves anything behind.

Also, **delete `.git/index.lock.parked`** by hand if it's still there:

```bash
rm -f /Users/x01/Developer/Projects/Manifold/.git/index.lock.parked
```

That's a leftover from sandbox lock contention; it's not an active git lock.

## Then commit

```bash
cd /Users/x01/Developer/Projects/Manifold
git status                # review the rename detection
git add -A
git diff --cached --stat  # sanity check before commit
git commit -m "Reorganize repo structure for open-source launch"
```

Git will detect most file moves as renames so history is preserved.

## Things to do before pushing public

1. **Replace `brand/mark-light.svg` / `brand/mark-dark.svg`** with the real mark. Current files are minimal `{ | }` rendered with a system mono font — they load correctly but aren't press-quality.
2. **Add a real screenshot** to satisfy `README.md`'s `<!-- TODO: Add screenshot -->`. Recommended shot: Access view with the per-AI chip stack — that's the differentiator. Save into `docs/screenshots/` and reference from README.
3. **Leave the README badges static.** No CI-status badges since you're staying off Actions; the existing License / macOS / Swift badges are fine.
4. **Verify the build still works** locally before pushing — this is your CI now:
   ```bash
   env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache swift build
   env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache swift test
   env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache xcodebuild -project Manifold.xcodeproj -scheme Manifold -configuration Debug -derivedDataPath /tmp/manifold-derived-data build CODE_SIGNING_ALLOWED=NO
   ```
5. **Decide what to do with `DESIGN.md`** (root) vs. `docs/design-standards.md` (just promoted). Both are real, both have content, and they overlap. Probably consolidate into one canonical design system doc and link to it from README.
6. **Decide whether `Resources/` should ever move** into `Sources/ManifoldAgent/Resources/`. Skipped this pass — see `Resources/README.md` for the reasoning. Worth doing eventually with a careful project.yml update.
7. **No CI by choice.** GitHub Actions, dependabot, and CODEOWNERS were intentionally not added — manual push-and-verify keeps you in full control. Document the local verification expectation in `CONTRIBUTING.md` (already done via the existing `swift build` / `swift test` / `xcodebuild` instructions). Revisit only if a maintainer joins and the manual gate becomes a bottleneck.

## What I did *not* touch

- `Sources/`, `ManifoldApp/`, `Tests/`, `ManifoldAppTests/`, `ManifoldAppUITests/` — code layout untouched.
- `Package.swift`, `Manifold.xcodeproj`, `project.yml` — unchanged. The build path is the same as before.
- `LICENSE`, `NOTICE`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `CHANGELOG.md` — unchanged.
- `Resources/com.spatialduality.manifold.runtime.plist` — stays where it was (only `Resources/README.md` is new).

## Verification claim

I edited and moved files using the file tools and the bash sandbox. **I did not run `swift build`, `swift test`, or `xcodebuild` in this session** — the sandbox doesn't have Xcode/Swift toolchain access. You must run them locally before pushing per item 4 above.
