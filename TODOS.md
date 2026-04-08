# TODOS

All items below were implemented on branch `claude/hungry-spence` and reviewed via design + eng reviews.

## ~~.manifoldignore support~~ ✓
Implemented in `GlobMatcher.swift` + `MaterializationEngine.swift`. Gitignore-style patterns, tested with 10 tests.

## ~~Materialization cleanup on session end~~ ✓
Implemented in `SessionModel.swift`. Cleans grant dir after endSession, orphan cleanup at launch.

## ~~Pre-session preview~~ ✓
Implemented in `SessionModel.swift` + `DashboardView.swift`. 5 interaction states, email sensitivity context, DESIGN.md alignment.

## ~~Wire domain presets into session behavior~~ ✓
Implemented via `EmailSensitivityFilter.swift`, migration v11, `GrantStore`/`ManifoldBridge` wiring. 8 tests.

---

## Next: v2 features to plan

(Add new items here as they emerge from usage and feedback.)
