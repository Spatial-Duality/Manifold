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

---

## Deferred from /plan-eng-review on 2026-04-27 (commit 93b12fc)

These came out of the Personal Data OS eng review. The demo-critical pieces
(hero shot E2E test, tool descriptions, paginated ledger verify, SQL push-down
on memory recall, store helpers consolidation, claim-verification extraction)
were all implemented. The remaining items below were deemed too risky to land
3 days before the Thu 2026-04-30 launch.

### Full ManifoldBridge file-level split

**What:** `ManifoldBridge` is currently 4005 lines in one file. Existing
`// MARK:` sections give it logical organization, and `ClaimVerification.swift`
already lifts the pure parsing/grading helpers out. The next step is moving
the public methods into multiple `extension ManifoldBridge` files grouped by
responsibility:
- `ManifoldBridge+Memory.swift` — recall, save, list_sources, forget, prior_context
- `ManifoldBridge+Capability.swift` — create_value_handle, check_capability_flow
- `ManifoldBridge+SkillsAndExec.swift` — run_code, save_skill, invoke_skill, list_skills
- `ManifoldBridge+History.swift` — was_exposed_before, what_changed_since,
  verify_ledger_entry, file_history_context, query_graph

**Why:** A 4000-line actor file is hostile to navigation and code review.
File-level split makes the responsibility boundaries enforceable.

**Cost:** Bridge's `private let` properties (db, stores, runtimeContext) and
several private helpers (`resolveAccessForTool`, `recordExposure`,
`expireDerivedMemoryIfNeeded`, `sourceIDs(in:)`, `grantID(in:)`,
`canAccessMemory`, `decisionContext`, `recordAccessDecision`,
`Self.canonicalJSON`) need to be bumped from `private` to default-internal so
extensions in sibling files can reach them. This expands their visibility
within the `ManifoldRuntime` module but stays inside the module boundary.

**Why deferred:** Touches the demo-critical bridge surface 3 days before launch.
The minimal-viable claim-verification extraction (Apr 27) demonstrates the
pattern is safe; the full split needs more time to land carefully.

**Where to start:** Pick the smallest group first (likely
`ManifoldBridge+Capability.swift` — only 2 methods, ~100 lines). Bump
the necessary properties, run `swift test` after each move, commit per move.
