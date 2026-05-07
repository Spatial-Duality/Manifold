# MCP Failure Mode Matrix

This matrix is the source of truth for MCP reliability coverage. The rule is:
every MCP failure must produce either a valid JSON-RPC error or a tool result
with `isError: true`, `_meta.manifold.request_id`, a typed classification, and
a durable event when the request crossed the runtime/XPC boundary.

LaunchAgent scenarios must run as a normal macOS GUI user. A restricted
Codex/Python sandbox can be denied by launchd before Manifold code has control.

## Executable Harnesses

| Harness | Scope |
| --- | --- |
| `swift test --filter MCPProtocolTests` | Protocol parse/invalid-request behavior. |
| `swift test --filter ReliabilityKernelTests` | Request IDs, failure store schema, supervisor state. |
| `swift test --filter StandingAccessTests` | File/email effective access, explicit sessions, writes, privacy. |
| `swift test --filter DiagnosticsRecorderTests` | Durable diagnostics for runtime and MCP failures. |
| `scripts/source_health_mcp_e2e.py` | Real app plus real MCP source rename/delete/replace. |
| `scripts/mcp_restart_disconnect_e2e.py` | Real app plus real MCP helper SIGKILL and reconnect. |
| `scripts/mcp_failure_modes_e2e.py` | Real Codex MCP chaos pass across protocol, XPC, LaunchAgent, helper crash, multi-client, and source health. |

## Failure Modes

| ID | Mode | Invariant | Coverage |
| --- | --- | --- | --- |
| FM-PROTO-001 | Malformed JSON on stdio | Return JSON-RPC `-32700`; process stays alive. | `scripts/mcp_failure_modes_e2e.py`; `MCPProtocolTests.malformedJSONReturnsParseError`. |
| FM-PROTO-002 | JSON-RPC object missing `method` | Return JSON-RPC `-32600` with original id. | `scripts/mcp_failure_modes_e2e.py`; `MCPProtocolTests.missingMethodReturnsInvalidRequest`. |
| FM-PROTO-003 | Unknown JSON-RPC method | Return JSON-RPC `-32601`; no runtime call. | `scripts/mcp_failure_modes_e2e.py`. |
| FM-PROTO-004 | Missing tool name | Return `isError: true` with `transport.malformed_message`. | `MCPProtocolTests`; covered by MCP adapter path. |
| FM-PROTO-005 | Unsupported client protocol version | Negotiate newest supported version, do not reject healthy clients. | `MCPProtocolTests.initializeResponse`. |
| FM-XPC-001 | Runtime unavailable before connect | Return retryable `xpc.runtime_unavailable`; persist `mcp_failure_events`. | `scripts/mcp_failure_modes_e2e.py`. |
| FM-XPC-002 | Runtime helper SIGKILL during/after tool call | Record classified failure; reconnect once; next call sees files. | `scripts/mcp_restart_disconnect_e2e.py`; `scripts/mcp_failure_modes_e2e.py`. |
| FM-XPC-003 | Two concurrent Codex MCP clients hold stale connection IDs across helper crash | Both reconnect through launchd demand-start; stale replies do not leak. | `scripts/mcp_failure_modes_e2e.py`. |
| FM-XPC-004 | XPC invalidation or interruption | Reset client connection, post app notification, classify `xpc.connection_invalidated`. | `ManifoldXPCClient` tests plus helper crash E2E. |
| FM-XPC-005 | XPC command/tool timeout | Single-shot continuation resumes once; classify `xpc.timeout`. | `ManifoldXPCClient` timeout path; add future delay-injection E2E if this regresses. |
| FM-XPC-006 | Malformed XPC reply payload | Return `xpc.reply_malformed`, not a crash. | `XPCCodingTypesTests`; XPC decode paths. |
| FM-XPC-007 | Identity verification failure | Reject unauthorized host/helper; durable `identity.verification_failed`. | `ClientIdentityVerifierTests`. |
| FM-LAUNCHD-001 | LaunchAgent `bootout` while MCP is connected | Next MCP tool returns classified retryable error and durable event. | `scripts/mcp_failure_modes_e2e.py`; requires normal GUI user launchd privileges. |
| FM-LAUNCHD-002 | LaunchAgent bootstrap denied by sandbox | Diagnostic records bootstrap failure; product cannot override OS denial. | Manual/restricted-environment validation; `DiagnosticsRecorderTests`. |
| FM-LAUNCHD-003 | Helper missing from app bundle | App records `runtimeRegistrationFailedHelperMissing`; UI offers restart/recovery. | `ManifoldStoreTests`/diagnostic model coverage. |
| FM-LAUNCHD-004 | Helper launch health timeout | Supervisor marks failed; no silent healthy state. | `RuntimeStatusSnapshotTests`; diagnostics coverage. |
| FM-LAUNCHD-005 | Old helper/app version mismatch | App records `versionMismatchRestart`, bootouts stale helper once, fails closed if launchd still starts the old version. | `scripts/mcp_failure_modes_e2e.py`; `DiagnosticsRecorderTests`; app version-restart logic. |
| FM-LAUNCHD-006 | Two app versions racing for the same Mach service | One active LaunchAgent label wins; stale clients reconnect through the current label. | Manual release/upgrade test until old bundle fixture is added. |
| FM-ACCESS-001 | Access UI and MCP file visibility drift | `list_files`, reads, writes, and search consume one `EffectiveAccessSnapshot`. | `StandingAccessTests`; `source_health_mcp_e2e.py`. |
| FM-ACCESS-002 | Source folder renamed | Bookmark identity follows original source; MCP still reads allowed file. | `scripts/source_health_mcp_e2e.py`. |
| FM-ACCESS-003 | Source folder deleted | MCP removes file from visibility; reads fail closed. | `scripts/source_health_mcp_e2e.py`. |
| FM-ACCESS-004 | Source folder replaced at same path | Replacement content is not exposed under stale grant. | `scripts/source_health_mcp_e2e.py`. |
| FM-ACCESS-005 | Explicit session narrower than default Focus/access matrix | Session-scoped snapshot wins while session is active. | `StandingAccessTests`. |
| FM-ACCESS-006 | Paused source or paused access | Tools fail closed with `access.paused`. | `MCPAccessControlTests`; `StandingAccessTests`. |
| FM-ACCESS-007 | Symlink/path traversal/outside root | Reject as `path.outside_root`; no filesystem escape. | `ScopedFileAccessTests`; bridge tests. |
| FM-ACCESS-008 | Ambiguous relative path | Reject as `path.ambiguous`; ask for disambiguation. | Bridge/access tests. |
| FM-MAIL-001 | No configured/shared email access | `list_emails` fails closed or returns empty with classified access reason. | `StandingAccessTests`. |
| FM-MAIL-002 | Shared email removed or account removed | `read_email` fails closed; no stale body leak. | `EmailStoreTests`; `MailAccountRemovalRuntime` tests. |
| FM-MAIL-003 | IMAP continuation double-callback/throw | Single-shot continuation prevents crash. | `IMAPConnection` single-shot use; focused IMAP parser/session tests. |
| FM-PRIVACY-001 | Vision OCR handler and synchronous `perform` error both fire | Single-shot continuation prevents double-resume crash. | `PrivacyIndexCoordinatorTests`; OCR regression path. |
| FM-PRIVACY-002 | Background privacy indexing fails | Runtime stays up; MCP access remains governed by explicit stores. | `PrivacyIndexCoordinatorTests`; runtime bootstrap path. |
| FM-WRITE-001 | File changed during write | Reject with `write.conflict`; no blind overwrite. | `StandingAccessTests`. |
| FM-WRITE-002 | Write outside effective access | Reject as access/path failure; no side effects. | `StandingAccessTests`; bridge tests. |
| FM-DIAG-001 | `Transport closed` or runtime interruption | Durable failure event exists with request ID, boundary, phase, classification. | `scripts/mcp_restart_disconnect_e2e.py`; `scripts/mcp_failure_modes_e2e.py`. |
| FM-DIAG-002 | Store migration/schema drift | Tests derive current version; repair assertions stay explicit. | `DatabaseMigratorTests`. |

## Acceptance Gate

Before release, run:

```bash
swift test
xcodebuild -project Manifold.xcodeproj -scheme Manifold -configuration Debug -derivedDataPath .deriveddata-ui-tests build
python3 scripts/mcp_failure_modes_e2e.py
```

The Python harness must run outside the restricted sandbox, as the logged-in
user, so launchd can bootstrap and bootout the user LaunchAgent.
