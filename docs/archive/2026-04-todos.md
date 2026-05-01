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

## Completed from /plan-eng-review on 2026-04-27 (commit 93b12fc)

All Personal Data OS eng-review items shipped, including the full bridge
file-level split that was originally flagged as risky pre-launch:

- Hero shot E2E test (cross-agent recall_memory / reuse_prior_context /
  was_exposed_before through two ManifoldBridge instances over the same stores)
- Tool descriptions explicitly mention cross-agent visibility
- StoreHelpers.swift consolidates addColumnIfMissing + StoreJSON
- Paginated LedgerStore.verifyChain (500/page)
- MemoryStore.recall scope filter pushed into SQL via json_each
- ClaimVerification.swift extracts pure parse/grade helpers
- ManifoldBridge split along 4 responsibility files:
  - ManifoldBridge+Capability.swift (create_value_handle, check_capability_flow)
  - ManifoldBridge+SkillsAndExec.swift (run_code, save_skill, invoke_skill,
    list_skills)
  - ManifoldBridge+Memory.swift (reuse_prior_context, recall_memory,
    save_memory_note, list_memory_sources, forget_memory)
  - ManifoldBridge+History.swift (file_history_context, session_context,
    tool_cost_report, verify_ledger_entry, was_exposed_before,
    what_changed_since, query_graph, verify_claimed_actions,
    latest_tool_metric_context)

ManifoldBridge.swift dropped from 4082 → 3302 lines (-780).
Verified: 420/420 swift test, xcodebuild Manifold BUILD SUCCEEDED.
