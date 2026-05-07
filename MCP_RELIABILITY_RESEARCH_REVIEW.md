# MCP Reliability Research Review

Date: 2026-05-07

This document checks the proposed "single authority, disposable runtime,
durable failure ledger" architecture against primary-source contracts and the
current Manifold implementation.

## Verdict

The proposed direction is correct, but the current implementation is only part
way there.

The right target is not a god object. It is a small reliability kernel:

- one authoritative effective-access snapshot
- one runtime supervisor for lifecycle and restart
- one typed error envelope across MCP, XPC, runtime, and diagnostics
- one durable failure/event stream keyed by request ID
- many small stores and adapters behind those contracts

The existing code already has useful pieces: a thin MCP adapter, an XPC-backed
runtime process, LaunchAgent registration, per-agent access policies,
diagnostic JSONL files, tool metrics, and regression tests for the current
stale work-block bug. The missing pieces are the ones that make failures
explainable and recoverable instead of flaky: request IDs, typed failure codes,
timeouts, single-resume XPC guards, runtime generations, supervisor state, and
durable MCP failure events.

## Research Baseline

### MCP and JSON-RPC

Primary sources:

- MCP 2025-06-18 Base Protocol:
  https://modelcontextprotocol.io/specification/2025-06-18/basic
- MCP 2025-06-18 Lifecycle:
  https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle
- MCP 2025-06-18 Transports:
  https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- MCP 2025-06-18 Tools:
  https://modelcontextprotocol.io/specification/2025-06-18/server/tools
- JSON-RPC 2.0:
  https://www.jsonrpc.org/specification

Findings:

- MCP is layered: base protocol, lifecycle, authorization, server features,
  client features, and utilities. A reliable Manifold design should preserve
  those boundaries instead of letting transport, access, and runtime state blur.
- MCP messages are JSON-RPC 2.0. Request IDs correlate requests and responses.
  Responses must contain either `result` or `error`, not both.
- The stdio transport requires stdout to contain only valid MCP messages.
  stderr is the correct place for process logs.
- Lifecycle initialization is explicit. Normal operations should happen only
  after initialization and capability negotiation.
- Implementations should use timeouts for sent requests to avoid hung
  connections and resource exhaustion.
- Tool failures are split into protocol errors and tool execution errors.
  Business/tool failures can be returned as tool results with `isError: true`,
  but malformed calls and protocol faults should be JSON-RPC errors.
- Tool servers must validate inputs, enforce access control, sanitize outputs,
  and log tool usage for audit.

Current code check:

- `Sources/ManifoldMCP/MCPProtocol.swift` supports newline and
  Content-Length framing and responds with JSON-RPC envelopes.
- `Sources/ManifoldMCP/ManifoldMCPServer.swift` keeps MCP thin and forwards
  tool calls to XPC.
- Gaps:
  - malformed JSON currently returns no JSON-RPC parse error in
    `MCPServer.handleMessage`
  - request IDs are not promoted into runtime/logging/failure records
  - no per-request timeout/cancellation layer exists at the MCP adapter
  - many failures become plain text `isError` results, losing boundary, phase,
    retryability, and policy version

### Apple process and XPC model

Primary sources:

- Apple Daemons and Services Programming Guide, Designing Daemons and Services:
  https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html
- Apple Creating Launch Daemons and Agents:
  https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html
- NSXPCConnection invalidation/interruption docs:
  https://developer.apple.com/documentation/foundation/nsxpcconnection/invalidationhandler
  https://developer.apple.com/documentation/foundation/nsxpcconnection/interruptionhandler
  https://developer.apple.com/documentation/foundation/nsxpcconnection/invalidate%28%29

Findings:

- Apple recommends using launchd-managed helpers for background services.
- Apple explicitly frames XPC services as a way to improve reliability and
  security by separating crash-prone or privileged work from the main app.
- Launch jobs can be on-demand or kept alive. Manifold's LaunchAgent approach
  matches the platform shape.
- XPC interruption means the remote process exited or crashed and may be
  reconnectable. Invalidation means the connection ended and cannot be reused.
- After invalidation, a connection should not be used again. A fresh connection
  is required.

Current code check:

- `Sources/ManifoldAgent/main.swift` hosts `ManifoldXPCService` through an
  `NSXPCListener` and records boot/clean-shutdown diagnostics.
- `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift` writes a LaunchAgent
  plist, bootstraps it with `launchctl`, and exposes manual restart/reconnect
  actions.
- `Sources/ManifoldXPC/ManifoldXPCClient.swift` resets its cached connection
  on interruption/invalidation.
- Gaps:
  - there is no explicit `RuntimeSupervisor` state machine
  - restart has no generation ID to reject stale replies
  - restart is spread between app registration, MCP reconnection, XPC reset,
    and string-based classifiers
  - no typed restart reason/backoff policy is persisted
  - XPC continuation callbacks can race with error handlers unless guarded by
    a single-resume abstraction

### Swift concurrency bridge

Primary source:

- Swift `CheckedContinuation`:
  https://developer.apple.com/documentation/swift/checkedcontinuation

Findings:

- Checked continuations must be resumed exactly once. Multiple resume is
  undefined behavior and missing resume can hang a task.

Current code check:

- `ManifoldXPCClient` wraps XPC callbacks with `withCheckedThrowingContinuation`.
- Gaps:
  - the remote proxy error handler and the reply callback can both attempt to
    resume the same continuation in failure races
  - there is no timeout wrapper around an XPC call that never replies
  - there is no single reusable `XPCRequestBox`/`SingleShotContinuation`

### Logging and diagnostics

Primary source:

- Apple Unified Logging:
  https://developer.apple.com/documentation/os/logging

Findings:

- Unified logging is meant for intermittent bugs and cases where a debugger
  cannot be attached. Subsystem/category naming should make logs filterable.
- For local forensic reliability, unified logs should be complemented by a
  durable app-owned event log because system log retention and privacy behavior
  are not the same as a product-level failure ledger.

Current code check:

- `Logger` is already used across MCP, XPC, runtime, diagnostics, mail, and
  policy stores.
- `DiagnosticsRecorder` writes append-only JSONL outside SQLite, which is the
  right direction for runtime registration failures.
- `ToolMetricsStore` records tool calls into SQLite and the ledger.
- Gaps:
  - `DiagnosticEvent` does not yet model MCP request failures, transport close,
    XPC interruption, policy snapshot mismatch, restart started/succeeded, or
    restart failed
  - `ToolMetricsStore` records tool outcome but not request ID, error code,
    boundary, phase, retryability, runtime generation, or policy version
  - `Transport closed` can still leave no durable product-level event

### Durable state

Primary sources:

- SQLite WAL:
  https://www.sqlite.org/wal.html
- SQLite atomic commit:
  https://www.sqlite.org/atomiccommit.html

Findings:

- SQLite gives atomic commit semantics, and WAL lets readers continue while
  writers append committed transactions.
- SQLite's own reliability confidence comes from crash tests that simulate
  power loss and verify all-or-nothing recovery.

Current code check:

- Manifold already uses SQLite stores for policy, tool metrics, exposure,
  ledger, email, snapshots, and related metadata.
- `DiagnosticsRecorder` deliberately sits outside SQLite for early startup
  failures.
- Gaps:
  - there is no crash/restart fuzz test for MCP/XPC during active tool calls
  - durable failure events do not cover the MCP boundary yet
  - full `swift test` currently fails in `DatabaseMigratorTests`, which means
    storage reliability is not clean enough to call the system bulletproof

## Component-by-Component Review

### 1. MCP adapter

Current files:

- `Sources/ManifoldMCP/MCPProtocol.swift`
- `Sources/ManifoldMCP/ManifoldMCPServer.swift`
- `Sources/ManifoldMCP/ToolDefinitions.swift`

What is right:

- MCP adapter is thin.
- Tool definitions live at the adapter edge.
- stdout framing is separated from tool dispatch.
- Runtime calls are forwarded through XPC instead of duplicating policy logic.

What is not yet bulletproof:

- parse/invalid-request cases should return JSON-RPC errors where possible
- requests should get internal `request_id` even when JSON-RPC ID is client
  supplied or absent
- protocol lifecycle should reject non-initialize requests before initialization
  except allowed ping behavior
- every tool call should carry a request envelope:
  `request_id`, `jsonrpc_id`, `agent`, `tool`, `protocol_version`,
  `runtime_generation`, `access_snapshot_id`
- the adapter needs timeouts around XPC calls and retry policy only for typed
  retryable errors

### 2. XPC client/service boundary

Current files:

- `Sources/ManifoldXPC/ManifoldXPCClient.swift`
- `Sources/ManifoldXPC/ManifoldXPCService.swift`
- `Sources/ManifoldXPC/ManifoldXPCProtocol.swift`
- `Sources/ManifoldXPC/ClientIdentityVerifier.swift`

What is right:

- XPC is the correct Mac boundary.
- Client identity verification exists.
- XPC connection interruption/invalidation resets cached connection.
- App-side notifications exist for connection loss.

What is not yet bulletproof:

- XPC calls need a single-resume guard around reply and error callbacks
- each XPC call needs a deadline and typed timeout error
- the service should return typed transport/runtime failures, not just text
- bridge registry misses should be classified as stale connection generation,
  not only "No active runtime connection"
- the service should write durable failure events before replying with `isError`

### 3. Runtime and access resolution

Current files:

- `Sources/ManifoldRuntime/ManifoldRuntime.swift`
- `Sources/ManifoldRuntime/ManifoldBridge.swift`
- `Sources/ManifoldKit/PolicyStore.swift`
- `Sources/ManifoldKit/WorkBlockStore.swift`
- `Sources/ManifoldKit/GrantStore.swift`

What is right:

- Runtime is the intended source of truth.
- Current access resolution fails closed.
- The recent fix makes default work blocks re-resolve current standing access
  instead of using stale empty grant sources.
- Explicit selections remain frozen, which is the correct security behavior.

What is not yet bulletproof:

- there is no named, immutable `EffectiveAccessSnapshot` object with an ID and
  policy version
- UI status and MCP results still do not compare snapshot IDs
- no invariant checker records "UI says source visible but MCP source absent"
- empty results are still semantically overloaded as "No files available."
- access failures lack stable codes such as `access.no_policy`,
  `access.paused`, `source.missing`, `source.replaced`,
  `snapshot.mismatch`

### 4. Runtime supervision and restart

Current files:

- `Sources/ManifoldAgent/main.swift`
- `ManifoldApp/ManifoldApp/Models/ManifoldStore.swift`
- `ManifoldApp/ManifoldApp/Models/RuntimeIssue.swift`

What is right:

- LaunchAgent is registered through launchd.
- There is a user-facing restart path.
- Version mismatch triggers one restart attempt.
- Stale MCP helpers can be terminated by installed executable path.

What is not yet bulletproof:

- restart is not one state machine
- automatic restart is not consistently triggered by XPC interruption,
  transport close, request timeout, or health probe failure
- there is no exponential backoff or crash-loop breaker
- manual restart and automatic restart should use the same supervisor method
- restart events should be durable and include old/new runtime generation

### 5. Diagnostics and observability

Current files:

- `Sources/ManifoldKit/Diagnostics/DiagnosticEvent.swift`
- `Sources/ManifoldKit/Diagnostics/DiagnosticsRecorder.swift`
- `Sources/ManifoldKit/ToolMetricsStore.swift`
- `Sources/ManifoldKit/LedgerStore.swift`

What is right:

- Diagnostics are append-only JSONL and independent from runtime SQLite.
- Diagnostic event names are closed and allowlisted.
- Tool metrics are persisted.

What is not yet bulletproof:

- diagnostic schema is too sparse for MCP incidents
- tool metrics are not enough to reconstruct a failed request
- there is no support bundle that joins app diagnostics, MCP stderr, XPC
  events, tool metrics, access snapshot, source health, and latest OSLog rows
  by request ID

### 6. Tests

Current coverage that supports the proposed architecture:

- `MCPProtocolTests` covers framing and basic JSON-RPC envelopes.
- `StandingAccessTests.activeWorkBlockPicksUpNewlySharedSources` covers the
  exact stale default work-block failure mode.
- `DiagnosticsRecorderTests` covers append-only diagnostic persistence.
- `XPCCodingTypesTests` covers XPC JSON payload round-trips.
- `RuntimeIssueClassifierTests` covers app-side restart/reconnect routing.
- `scripts/source_health_mcp_e2e.py` exercises the real app plus real MCP stdio
  server through rename/delete/replace source-health scenarios.

Missing test classes:

- MCP invalid JSON returns JSON-RPC parse error
- non-initialized tool calls are rejected until lifecycle completes
- MCP call times out when XPC never replies
- XPC continuation reply/error race resumes exactly once
- runtime crash during `tools/call` writes durable failure event
- restart increments generation and discards stale replies
- default work block source addition/removal is tested through real MCP stdio,
  not only direct `ManifoldBridge`
- UI effective access snapshot equals MCP visible access snapshot
- tool error result includes stable error code, boundary, phase, request ID,
  retryability, policy version, and snapshot ID

## Test Results

Executed on 2026-05-07.

Passed:

- `swift test --filter MCPProtocolTests`
  - 10 tests passed.
- `swift test --filter StandingAccessTests/activeWorkBlockPicksUpNewlySharedSources`
  - 1 test passed.
- `swift test --filter DiagnosticsRecorderTests`
  - 5 tests passed.
- `swift test --filter XPCCodingTypesTests`
  - 2 tests passed.
- `xcodebuild -quiet -project Manifold.xcodeproj -scheme Manifold -configuration Debug -derivedDataPath /tmp/manifold-derived-data test -only-testing:ManifoldAppTests/RuntimeIssueClassifierTests`
  - passed.
- `python3 scripts/source_health_mcp_e2e.py` outside the sandbox
  - `PASS rename`
  - `PASS delete`
  - `PASS replace`

Failed / not clean:

- `swift test`
  - 661 tests ran.
  - 29 issues failed under `DatabaseMigratorTests`.
  - Failing areas:
    - migration v27 expected version repair behavior
    - migration v34 privacy backend migration count/version
    - migration v35 orphan access scrub
    - migration v39 legacy mail reset
    - current-schema repair expected zero applied migrations but saw four
- `python3 scripts/source_health_mcp_e2e.py` inside the sandbox failed because
  the GUI app did not bootstrap the synthetic source. Running the same harness
  outside the sandbox passed, so this is an execution-environment limitation,
  not a product failure in that harness.

## Decision Against Proposed Solution

### Proposed: one authority for access

Decision: correct.

But make the authority a small value-producing compiler, not a god file.

Recommended shape:

```text
AccessPolicyStore
WorkBlockScopeStore
FileVisibilityOverrideStore
SourceHealthStore
EmailRuleStore
EffectiveAccessSnapshotCompiler
EffectiveAccessSnapshot
AccessInvariantChecker
```

The compiler produces immutable snapshots. Adapters consume snapshots. No UI,
MCP, or XPC code should independently reinterpret policy rows.

### Proposed: restartable/disposable runtime

Decision: correct.

But restart must be centralized.

Recommended shape:

```text
RuntimeSupervisor
  state: stopped | starting | ready(generation) | degraded | restarting | failed
  actions: start, stop, restart, reconnect, healthProbe
  policy: retry/backoff/crash-loop breaker
```

Manual restart, version mismatch restart, XPC invalidation recovery, and MCP
transport-close recovery should all use this single path.

### Proposed: durable failure ledger

Decision: mandatory.

Current diagnostics and tool metrics are useful but insufficient. Add:

```text
MCPFailureEvent
  event_id
  request_id
  jsonrpc_id
  agent
  tool_name
  boundary
  phase
  error_code
  retryable
  runtime_generation
  policy_version
  access_snapshot_id
  connection_id
  process_id
  message
  created_at
```

This should be written for every MCP/XPC/runtime failure, including transport
close and timeout.

### Proposed: typed errors everywhere

Decision: correct and urgent.

Plain text errors are the root of many flaky recovery paths. Define one typed
error model and map it at every boundary:

```text
protocol.parse_error
protocol.invalid_request
protocol.invalid_params
transport.stdin_closed
transport.stdout_closed
xpc.interrupted
xpc.invalidated
xpc.timeout
runtime.unavailable
runtime.restart_in_progress
identity.verification_failed
access.paused
access.no_policy
access.no_sources
access.snapshot_mismatch
source.missing
source.moved
source.replaced
privacy.blocked
write.conflict
```

The MCP tool text can stay human-readable, but the structured payload must be
machine-readable.

## Reference Architecture

```text
MCPServer
  - parses/framing/lifecycle only
  - creates MCPRequestEnvelope
  - enforces timeout
  - returns JSON-RPC or MCP tool result

MCPRequestEnvelope
  - request_id
  - jsonrpc_id
  - agent
  - protocol_version
  - tool_name
  - started_at

RuntimeSupervisor
  - owns XPC connection lifecycle
  - owns restart/backoff/generation
  - performs health probes

XPCClient
  - transport only
  - single-resume continuations
  - typed timeout/interruption/invalidation errors

RuntimeService
  - validates caller identity
  - dispatches tools
  - records durable failure/tool events

EffectiveAccessSnapshotCompiler
  - combines policy, work block mode, source health, overrides, mail rules
  - emits immutable snapshot with version and reason codes

ManifoldBridge
  - executes governed file/mail operations against a snapshot
  - records exposures/decisions

Diagnostics
  - append-only JSONL for early lifecycle
  - SQLite/ledger failure events after runtime is available
  - exportable support bundle by request ID
```

## Build Order

1. Add typed `ManifoldFailure` / `MCPFailureEvent` model.
2. Thread `MCPRequestEnvelope` from MCP into XPC and runtime.
3. Add single-resume XPC request wrapper and per-call timeouts.
4. Add `RuntimeSupervisor` with generation IDs and shared restart path.
5. Add `EffectiveAccessSnapshot` and snapshot compiler.
6. Make `list_files` and `list_emails` return structured metadata:
   snapshot ID, policy version, source count, empty reason.
7. Add diagnostics/failure support bundle.
8. Move current access-resolution logic behind the snapshot compiler.
9. Add crash/restart/failure injection tests.
10. Fix `DatabaseMigratorTests` before claiming full reliability.

## Bottom Line

The solution is right if it is implemented as a reliability architecture, not
as a large manager file.

The standard to hold the system to is:

- no silent empty results
- no stale authority
- no untyped transport failures
- no hanging XPC calls
- no ambiguous restart behavior
- no failed MCP call without a durable event
- no UI/MCP access mismatch without an invariant violation

Current Manifold has enough foundation to get there, but it is not there yet.
The next engineering move should be typed failure plumbing plus supervisor
generation IDs, before adding more feature surface.
