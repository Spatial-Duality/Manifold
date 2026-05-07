# MCP Error Pattern Log

Purpose: collect every recurring MCP/XPC/runtime failure pattern visible in
the git history, plus the current unresolved/reproduced incidents, so the MCP
path can be fixed as one reliability architecture instead of as isolated bugs.

Method used on 2026-05-07:

- `git log --all` across the whole repo for MCP, XPC, runtime, access,
  connection, stale, grant, scope, error, fail, and transport terms.
- Path-limited `git log --all` over `Sources/ManifoldMCP`,
  `Sources/ManifoldXPC`, `Sources/ManifoldRuntime`, core access stores, and
  MCP/runtime tests.
- `git show --stat` and commit bodies for the high-signal fix/hardening
  commits.

Scope found:

- 64 commits touched the MCP/runtime/access path.
- The table below lists the high-signal commits that either introduced the
  MCP architecture or fixed a concrete edge case.
- This file intentionally includes inferred patterns. Inferences are marked
  as such.

## Executive Pattern

The same root shape keeps repeating:

1. The app UI, policy stores, MCP bridge, and runtime session state each have a
   partial view of "what the agent can see."
2. A later feature adds another state layer: standing access, Focus, active work
   blocks, file overrides, source health, email rules, runtime helper identity.
3. One boundary keeps reading stale or narrower state than the UI shows.
4. The MCP-facing error is usually generic, hidden, or transported as plain text.
5. A later commit adds a regression test for that one case, but no end-to-end
   invariant forces every boundary to agree.

Therefore the reliability target should be:

- One resolver for effective access.
- One correlation ID from MCP request through XPC, bridge, audit, metric, and
  response.
- One durable failure ledger for transport, authorization, resolution,
  enforcement, serialization, and disconnects.
- One end-to-end conformance suite that compares UI policy state against MCP
  visible state.

## Current Incidents

| ID | Date | Symptom | Confirmed state | Likely class |
| --- | --- | --- | --- | --- |
| CUR-001 | 2026-05-07 | `list_files` returned `No files available` while Access UI showed Codex checked for `HR`. | Local DB had `codex.allowed_source_ids = ["src-12b3482e"]`, and `HR` had four files. Active default work block had zero grant sources. | Stale default work-block scope overriding current Access matrix. |
| CUR-002 | 2026-05-07 | Direct MCP tool call later failed with `Transport closed`. | The in-thread MCP tool could not complete `manifold/list_files`; local DB was readable. | Transport/process/XPC lifetime failure without enough logs. |
| CUR-003 | 2026-05-07 | User cannot trust whether MCP failure is a permissions issue or runtime issue. | MCP response had no correlation ID, no boundary classification, and no durable failure entry. | Observability gap. |
| CUR-004 | 2026-05-07 13:36:56 +0100 | App crashed during Python/Codex E2E launch at `configureApplicationIconImage()` before runtime bootstrap. | Stack pointed to `ManifoldApp.swift:35`, caused by calling `NSApplication.shared` inside `ManifoldApp.init()`. | AppKit registration too early in SwiftUI app lifecycle. |
| CUR-005 | 2026-05-07 13:42:18 +0100 | App crashed during sandboxed Python/Codex E2E launch inside `SwiftUI.runApp` / `NSApplication.sharedApplication`, with no Manifold frame above `$main`. | Current bundle already had the icon fix; the same bundle passed E2E when run outside the Codex sandbox. Unified logs showed sandboxed `launchctl bootstrap` was denied with `Operation not permitted`. | GUI app launch and LaunchAgent bootstrap from a restricted Codex/Python coalition, not a tool/access bug. |
| CUR-006 | 2026-05-07 15:17-15:18 +0100 | Claude Desktop loaded Manifold and showed the user permission prompt, but `list_files` still failed. | Claude spawned the configured `manifold-mcp --agent cowork` helper. Unified logs showed `Timed out waiting for the Manifold runtime during connect`; no sandbox denial occurred. The MCP process also logged `MCP failure event store unavailable` because default MCP envs did not resolve the production store path. | Runtime connect timeout plus pre-connect failure ledger path bug. |

Uncommitted mitigation already applied before this log:

- `Sources/ManifoldRuntime/ManifoldBridge.swift` now re-synthesizes non-explicit
  default work-block grant sources from current policy.
- `Tests/ManifoldKitTests/StandingAccessTests.swift` adds a regression for an
  empty Codex default work block picking up a newly shared folder.
- This fixes CUR-001, not CUR-002 or the broader logging architecture.
- `ManifoldApp/ManifoldApp/ManifoldApp.swift` now defers application icon
  mutation until the first window appears and uses `NSApp`, fixing CUR-004.
- `Sources/ManifoldMCP/ManifoldMCPServer.swift` now writes durable
  `mcp_failure_events` directly for pre-XPC connection failures, so CUR-005's
  user-visible `xpc.runtime_unavailable` state is no longer invisible even
  when the runtime never connects.
- `Sources/ManifoldKit/IMAPConnection.swift` now uses the shared
  `SingleShotThrowingContinuation` guard for connect, send, and read
  continuations instead of a one-off flag.
- `scripts/mcp_restart_disconnect_e2e.py` now kills the real LaunchAgent
  helper, verifies launchd demand-start recovery through MCP, and asserts that
  the interruption leaves a durable `mcp_failure_events` row.
- `Sources/ManifoldKit/ManifoldRuntimeEnvironment.swift` now resolves
  production app-support, runtime-store, and diagnostics paths when no test
  environment is present, so Claude-launched MCP helpers can persist
  pre-connect failures.
- `scripts/claude_mcp_desktop_probe.py` now exercises Claude Desktop's wrapper
  path with redacted status output. On 2026-05-07 17:29 +0100 it verified
  `initialize`, `tools/list`, `list_files`, and `list_emails` through the
  installed signed helper with no MCP failure-store or transport errors in
  unified logs.
- `Sources/ManifoldMCP/ManifoldMCPServer.swift` now treats the failure recorder
  as a tiered path: production DB ledger first, append-only diagnostics spool
  second, structured unified log last. `Tests/ManifoldKitTests/MCPProtocolTests.swift`
  asserts both DB persistence and spool fallback preserve the same request ID
  and typed `xpc.runtime_unavailable` classification.

## Historical Error Timeline

| Commit | Date | Area | Failure or risk captured | Fix or hardening shipped | Pattern |
| --- | --- | --- | --- | --- | --- |
| `5b9b002` | 2026-04-03 | MCP bootstrap | Initial MCP path depended on a user-granted run and shared SQLite access. | Added `manifold-mcp`, file/mail tools, path safety, audit reads/writes. | First trust boundary was tool-level, not yet runtime-level. |
| `fe4614c` | 2026-04-03 | MCP protocol | Dependency-heavy MCP SDK replaced; protocol handling became local code. | Zero-dependency stdio JSON-RPC server and tests. | Protocol reliability became our responsibility. |
| `6a7544e` | 2026-04-04 | Access model | Real Claude testing found run requirement and poor metadata made MCP hard to use. | Global access, rich `list_files`, full tool audit. | Tool UX and access semantics changed together. |
| `ca2eed2` | 2026-04-04 | Binary files | Binary files could appear but not be usefully inspected through JSON-RPC text. | `file_info`, `list_archive`, `extract_file`. | List/read semantics need type-specific paths. |
| `43ee1aa` | 2026-04-05 | Access control | Paused/archived sources leaked, source-prefix paths failed, status was unclear. | Positive allowlist filtering, smart path prefix strip, status split, 23 tests. | Source status and path normalization must be enforced together. |
| `1bb6860` | 2026-04-05 | Observability | Silent `try?` hid load/source/session failures. | Added `os.Logger`, UI error banners, DB rollback logging. | Silent fallbacks delayed root-cause analysis. |
| `c9af005` | 2026-04-05 | Architecture review | Safety and observability review found size, audit, stale cache, force unwrap, and silent error gaps. | Materialization guards, grant audit IDs, initializer failure logs, no stale `approvedSources` cache. | Broad reviews exposed cross-cutting problems. |
| `e833203` | 2026-04-06 | Grant boundary | Email isolation, ambiguous bare paths, and write provenance were unsafe or unclear. | Grant-scoped emails, ambiguous path errors, snapshot-on-write. | Ambiguity should fail closed with a clear error. |
| `12b2b79` | 2026-04-10 | Standing access | File tools still required session grants after standing access shipped. | Routed all file tools through `resolveAccessMounts`; standing reads/writes hit originals. | New access mode must update every tool entry point. |
| `f4fd76a` | 2026-04-10 | Concurrency | MCP server registration/start race and UI reload races. | `MCPServer` became an actor; timers/reloads debounced and cancelled. | Async boundary races cause flakiness unless isolated. |
| `83ffed4` | 2026-04-10 | Cache/path | 10-second file cache risked stale visibility; `/var` vs `/private/var` prefix mismatch. | Cache keyed on mount paths; standardized URLs. | Performance caches must be keyed by access state and normalized identity. |
| `49c8293` | 2026-04-11 | Runtime boundary | Runtime moved behind XPC, adding process and identity failure modes. | `ManifoldAgent`, XPC protocol/client/service, bridge registry. | XPC added a new reliability boundary without full transport diagnostics. |
| `7613e87` | 2026-04-11 | Version check | Runtime version check could restart repeatedly. | Restart-once guard. | Recovery loops can create their own outage. |
| `a13a754` | 2026-04-13 | Trust model | UI/runtime/access model needed to align after XPC migration. | Caller identity verifier, governance model, email rules, exposure records. | Declared agent labels are not enough; bind to verified client identity. |
| `c86d0df` | 2026-04-27 | Memory/history | Cross-agent memory/exposure visibility needed hardening and scope filtering. | SQL scope filtering, paged ledger verification, cross-agent tests. | Derived context must inherit source scope. |
| `518354c` | 2026-04-27 | Bridge complexity | `ManifoldBridge` exceeded 4k lines and mixed many responsibilities. | Split into capability, skills/exec, memory, history extensions. | Large bridge surface hides invariant drift. |
| `bd0698b` | 2026-04-28 | Runtime enforcement | Privacy filter Block mode was UI-honest but not enforced. | Runtime filter enforcement in `readFileBytes`. | Settings must be enforced in the bridge, not just displayed. |
| `ac5137a` | 2026-04-29 | Overrides | Unsharing a folder left per-file allow overrides active. | Clear overrides when source is removed from policy; hide removed sources. | Revocation must cascade to every derived allow path. |
| `0f5b09a` | 2026-04-29 | Orphans | Soft-removed sources left stale policy IDs and override dots. | Migration scrubbed orphan overrides and policy IDs; remove handler cascaded. | Data hygiene can look like access leakage even when runtime denies correctly. |
| `799dd2d` | 2026-04-29 | Instant propagation | User can change sharing at any time; next MCP call must reflect it. | Regression toggles source scope and file overrides through `bridge.listFiles`. | "Next call reflects UI" is a core invariant. |
| `91a615b` | 2026-04-29 | Defense in depth | Policy cache, email temporary reveals, and symlink containment had gaps. | Cache freshness check, reveal cascade, symlink tests. | Multiple stores must be invalidated atomically. |
| `31436dc` | 2026-04-29 | Writes | Governed file write enforcement needed deeper coverage. | Approval queue, identity verifier, write path hardening, many standing tests. | Writes need stricter gates than reads. |
| `a8c9833` | 2026-04-30 | Helper identity | Rebuilt app replaced helper on disk while old `manifold-mcp` process kept old code in memory. | CDHash compare, stale-helper signal, reconnect agents action. | Process lifetime can invalidate code-signature assumptions. |
| `d95fe20` | 2026-04-30 | Email sessions | Explicit file/email sessions hid later explicitly shared emails. | Email policy kept shared mail visible in explicit sessions. | Explicit session scope and standing shares interact. |
| `dfff77e` | 2026-04-30 | Test harness | Need synthetic privacy MCP loop. | Large synthetic MCP harness in standing tests. | End-to-end synthetic loops catch integration regressions. |
| `6930ea4` | 2026-05-01 | Connection state | UI had a 5-second window claiming connected after XPC drop; string-grep recovery was brittle. | Typed `RuntimeIssue`, XPC disconnect notification, connection event ring buffer, backoff. | Connection state must be typed and event-driven. |
| `9de26cc` | 2026-05-03 | UI/review reliability | Mail sync and review UI had reliability bugs. | Mail sync state, repair UI coverage, store tests. | UI state drift affects perceived access reliability. |
| `cb735a7` | 2026-05-03 | Startup | First-run runtime startup needed polish. | Store startup changes and tests. | Runtime bootstrap must be explicit and observable. |
| `58ebcd0` | 2026-05-04 | Focus | Default Focus always running changed session semantics. | Atomic Focus activation, version source of truth, stale rebuild acceptance. | Focus adds another state layer that must feed MCP resolver. |
| `1a63631` | 2026-05-05 | Source identity | Source moves/permissions broke access or overused pause/remove states. | Bookmarks, source health, repair commands, MCP source-health E2E script. | Source identity must be durable, not path-only. |

## Repeated Failure Families

### 1. Transport and process lifetime

Symptoms:

- `Transport closed`.
- MCP helper spawned by Claude/Codex stays alive after app rebuild.
- XPC interruption invalidates connection while UI or MCP still believes it is active.
- Version drift or restart loop leaves helper/runtime in a fragile state.

Historical commits:

- `49c8293` introduced the XPC boundary.
- `7613e87` added restart-once guard.
- `a8c9833` fixed stale helper signature errors.
- `6930ea4` added typed runtime issues and XPC disconnect notification.
- CUR-002 shows this is still not fully observable.

Edge cases to cover:

- Host app kills MCP process mid-call.
- Runtime helper restarts while a tool call is in flight.
- XPC proxy callback never fires after invalidation.
- XPC reply data is empty or malformed.
- Stdio stdin closes while an XPC request is active.
- stdout write fails or back-pressures.
- Old helper process remains after app rebuild.
- Runtime is reachable but connection ID has been evicted.

Required architecture:

- Add `request_id` per MCP call and propagate to XPC, bridge, audit, and tool metrics.
- Persist `mcp_transport_event` records: `stdin_eof`, `malformed_json`,
  `decode_failed`, `xpc_call_started`, `xpc_call_failed`, `xpc_reconnected`,
  `xpc_reply_malformed`, `stdout_write_failed`, `server_shutdown`.
- Make `ManifoldXPCClient` continuations single-resume safe under both proxy
  error handler and reply callback.
- Add timeout classification for connect and tool calls.
- Return structured user-facing error text that includes boundary and request ID.

### 2. Access scope drift

Symptoms:

- UI shows a folder checked but MCP lists no files.
- Unchecked folder remains visible through per-file overrides.
- Removed source still appears in UI or policy rows.
- Active work block freezes an older view of standing access.

Historical commits:

- `43ee1aa`, `12b2b79`, `ac5137a`, `0f5b09a`, `799dd2d`, `91a615b`,
  `58ebcd0`, CUR-001.

Edge cases to cover:

- Policy changed while an active default work block exists.
- Policy changed while an explicit session exists.
- File override allow on a source not in default scope.
- File override deny inside a shared folder.
- Source removed while policy/override rows still reference it.
- Source paused or health failed while active session references it.
- Focus activation changes both agents atomically.
- Mirror-to-both toggles while Codex/Claude connected.

Required architecture:

- Define an `EffectiveAccessSnapshot` type as the sole output of access
  resolution, with source IDs, file scopes, email IDs/rules, source health,
  active Focus, active work block, and resolver version.
- Every tool should use this snapshot, never raw policy/grant tables directly.
- Persist the snapshot summary for each MCP request in tool metrics.
- Add an invariant test: app-visible policy -> MCP `list_files` visible set
  equals resolver visible set on the next call.

### 3. Source identity and path safety

Symptoms:

- Source prefix duplicated or stripped wrong.
- Bare paths ambiguous across mounts.
- Symlink escapes source root.
- `/var` and `/private/var` path aliases break prefix checks.
- Finder move makes a source appear gone.

Historical commits:

- `43ee1aa`, `e833203`, `83ffed4`, `91a615b`, `1a63631`.

Edge cases to cover:

- Two sources with same last path component.
- Same file name exists in multiple sources.
- Source moved but bookmark resolves.
- Bookmark stale or permission denied.
- Symlink inside source points outside source.
- Relative path starts with source mount name.
- Single-file source vs folder source.
- Hidden/system directories.

Required architecture:

- Path resolution should return a typed result:
  `resolved`, `ambiguous`, `outsideRoot`, `sourceUnavailable`,
  `requiresRepair`, `notShared`.
- No path failure should become generic `File not found` in logs.
- `list_files`, `read_file`, writes, archive tools, and source health repair
  should share one resolver.

### 4. Email visibility drift

Symptoms:

- Email cache leaks outside grant.
- Explicit sessions hide later shared emails.
- Account removal leaves reveal/share rows.
- Sensitivity rules produce confusing visible counts.

Historical commits:

- `e833203`, `d95fe20`, `91a615b`, `9de26cc`.

Edge cases to cover:

- Shared email outside explicit session.
- Email selected in explicit session but later unshared.
- Account removed with shared emails, grant emails, temporary reveals.
- Sensitivity strict/moderate/open transitions while session active.
- Mail sync creates duplicates or stale mailbox membership.

Required architecture:

- Email effective access should be part of `EffectiveAccessSnapshot`.
- `list_emails`, `read_email`, `read_email_eml`, and `search_emails` must log
  whether access came from explicit grant, shared email, domain/contact/keyword
  rule, temporary reveal, or default policy.

### 5. Write safety and provenance

Symptoms:

- Writes bypass snapshots.
- Writes target ambiguous paths.
- Direct writes continue after source unshared.
- Binary writes/archives exceed safe limits.

Historical commits:

- `e833203`, `31436dc`, `bd0698b`, `c9af005`, `ca2eed2`.

Edge cases to cover:

- Source unshared between resolve and write.
- File changed between read and write.
- Expected-before hash mismatch.
- Binary payload too large.
- Write to `.eml` or read-only mail artifacts.
- Draft workspace vs direct original mismatch.
- Filter mode blocks a write/read after file content scan.

Required architecture:

- Every write should log a preflight decision and a commit result separately.
- Every write failure should include source ID, canonical path, write mode,
  before hash status, resolver version, and request ID.
- Writes should require fresh effective access at commit time.

### 6. Observability gaps

Symptoms:

- Errors surfaced as plain text without classification.
- `try?` or fallback hides failures.
- Tool metrics record duration/output but not enough boundary context.
- User cannot tell runtime denied access vs MCP transport died.

Historical commits:

- `1bb6860`, `c9af005`, `6930ea4`, CUR-002, CUR-003.

Required architecture:

- Add a durable MCP failure table or reuse ledger/audit with a typed action.
- Error fields:
  - `request_id`
  - `timestamp`
  - `agent`
  - `client_name`
  - `tool_name`
  - `boundary` (`stdio`, `mcp_adapter`, `xpc_client`, `xpc_service`,
    `bridge_resolver`, `bridge_tool`, `store`, `filesystem`, `privacy_filter`)
  - `phase` (`decode`, `connect`, `authorize`, `resolve`, `execute`,
    `serialize`, `reply`, `disconnect`)
  - `classification`
  - `is_retryable`
  - `redacted_message`
  - `connection_id`
  - `grant_id`
  - `focus_id`
  - `source_ids`
  - `duration_ms`
- User-facing MCP errors should say:
  `Manifold error <request_id> at <boundary>/<phase>: <safe message>`.

## Proposed Failure Taxonomy

| Class | Boundary | Retry? | User action | Examples |
| --- | --- | --- | --- | --- |
| `transport.stdin_eof` | stdio | no | Restart host MCP client | Host closed MCP pipe. |
| `transport.malformed_message` | stdio | maybe | Report client/protocol issue | Invalid JSON or bad `Content-Length`. |
| `xpc.runtime_unavailable` | xpc_client | yes | Start/restart Manifold runtime | Helper not running. |
| `xpc.connection_invalidated` | xpc_client | yes | Retry after reconnect | Runtime restart or sleep. |
| `xpc.reply_malformed` | xpc_client/service | maybe | Collect logs | Empty/non-JSON reply. |
| `identity.verification_failed` | xpc_service | no | Reconnect/reinstall helper | Signature invalid or stale helper. |
| `access.no_access_configured` | bridge_resolver | no | Grant access in Manifold | No files/emails shared. |
| `access.paused` | bridge_resolver | no | Resume agent access | Agent paused. |
| `access.source_unavailable` | bridge_resolver | no | Repair source | Bookmark/permission/missing source. |
| `access.scope_stale` | bridge_resolver | yes | Retry after policy refresh | Policy/grant/focus mismatch. |
| `path.ambiguous` | bridge_tool | no | Use mount-prefixed path | Bare path in multiple sources. |
| `path.outside_root` | bridge_tool | no | Correct path | Symlink or `..` escape. |
| `privacy.blocked` | bridge_tool | no | Override/change filter | Secret/PII block mode. |
| `write.conflict` | bridge_tool | yes | Re-read before writing | Hash mismatch or changed file. |
| `store.migration_missing` | store | no | Repair DB/migrate | Missing table/schema drift. |

## Invariants To Enforce

1. If Access UI says Codex can see a healthy folder, MCP `list_files` must show
   its files on the next call unless an explicit session intentionally narrows
   scope.
2. If a folder is unchecked for an agent, no file in that source can remain
   visible through stale overrides unless there is an intentional per-file allow
   visible in the UI.
3. A removed, paused, missing, replaced, or permission-denied source must never
   be visible to MCP.
4. Every MCP request has a request ID visible in unified logs and durable
   metrics/audit.
5. Every MCP failure is classified by boundary and phase.
6. `Transport closed` without a durable `mcp_transport_event` is itself a bug.
7. Reconnect paths must not depend on string-grepping user-facing text.
8. Cache keys must include all access-affecting inputs: mount paths, source IDs,
   policy updated timestamps, overrides, Focus ID/version, source health, and
   explicit session scopes.
9. Explicit sessions freeze only what the user explicitly selected; default
   standing/default Focus sessions must follow the current Access matrix.
10. Runtime helper replacement must not invalidate already running helper
    processes without surfacing a typed stale-helper event.

## Edge-Case Test Matrix

### MCP transport

- Newline-framed valid request.
- Content-Length valid request.
- Malformed JSON with request ID.
- Malformed JSON without request ID.
- Bad Content-Length header.
- Partial Content-Length body followed by EOF.
- Large request body.
- Notification without ID produces no response.
- Response serialization failure is logged.

### XPC client/service

- Runtime unavailable during connect.
- Runtime invalidates during tool call.
- Runtime returns empty data.
- Runtime returns malformed JSON.
- Tool result has `isError = true`.
- Tool result has no content.
- Inactive connection ID triggers reconnect once.
- Reconnect failure preserves original request ID.
- Verification failure logs requested agent and client PID.

### Access resolver

- Default Focus with Codex HR checked and active work block with empty sources.
- Default Focus with source removed after grant creation.
- Explicit session with selected file only.
- Explicit session with no selected file but selected email.
- Per-file allow on otherwise unshared source.
- Per-file deny inside shared source.
- Source health `available`, `moved`, `needs_permission`, `missing`, `replaced`.
- Mirror-to-both toggle.
- Separate Claude/Codex sharing toggle.

### File/path

- Two folders with same canonical mount name.
- Bare ambiguous `README.md`.
- Mount-prefixed `hr/README.md`.
- Source-prefix submitted twice.
- Symlink escape.
- `/var` vs `/private/var`.
- Single-file source.
- Hidden/noise directories.

### Email

- Shared email after explicit file session starts.
- Unshared email after explicit session starts.
- Account deletion cascades grants/shares/reveals.
- Strict sensitivity only shared emails.
- Moderate/open policies.
- Search result redaction.

### Writes

- Direct text write to shared source.
- Direct write after source unshared.
- Expected hash mismatch.
- File changes between resolve and commit.
- Binary file through `write_file` refused.
- Oversized `write_binary_file`.
- Draft workspace path.
- Filter mode block on read/write.

## First Fix Batch Recommended

Do these before more UI work:

1. Add request IDs and boundary/phase logging to `MCPProtocol`,
   `ManifoldMCPServer`, `ManifoldXPCClient`, `ManifoldXPCService`, and
   `ManifoldBridge`.
2. Add a durable MCP failure event model/table or ledger entry type.
3. Make the XPC client's checked continuations single-resume safe under error
   handler plus reply callback races.
4. Add structured user-facing error responses with request ID and boundary.
5. Add end-to-end tests that compare effective access state against MCP
   `list_files`, including the CUR-001 default work-block case.
6. Add a real MCP stdio harness test for runtime restart/disconnect, based on
   the existing `scripts/source_health_mcp_e2e.py` pattern.

Implemented follow-up:

- `scripts/mcp_restart_disconnect_e2e.py` covers runtime helper kill/restart,
  stale connection recovery, and durable failure logging.
- The harness must run with normal user LaunchAgent privileges. A sandboxed
  Codex/Python coalition can still be denied by launchd before product code can
  recover; that condition is now classified as environment/setup rather than an
  MCP access resolver bug.

## Open Questions

- Should failure logs live in `audit_log`, `ledger_entries`, a new
  `mcp_failure_events` table, or all three?
- Should request IDs be generated by the MCP adapter or accepted from the MCP
  client when present?
- Should the app expose a "MCP Diagnostics" pane that groups failures by
  boundary, request ID, agent, and tool?
- Should default Focus always create an active work block, or should default
  standing access remain separate from tracked work blocks?
- Should transport errors be surfaced through `get_status` so agents can report
  the last failure without requiring Console access?
