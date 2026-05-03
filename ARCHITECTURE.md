# Architecture

This is the one-pager that explains what lives where and why. Keep it
short. If you reach for "let me also document...", that probably belongs
in code comments or in CONTRIBUTING.

## The boundaries

Manifold is built around a single rule: **the AI never touches the
filesystem or your inbox directly**. Every read goes through a
governance layer. Every write goes through a tracked workspace.

Four boundaries enforce that:

```
   ┌─────────────────────────────────────┐
   │  ManifoldApp (SwiftUI)              │   user-facing UI
   └────────────────┬────────────────────┘
                    │  AppRuntimeClient
   ┌────────────────▼────────────────────┐
   │  ManifoldXPC                        │   typed XPC interface,
   │  (interface + trust checks)         │   audience checks, no logic
   └────────────────┬────────────────────┘
                    │
   ┌────────────────▼────────────────────┐
   │  ManifoldRuntime                    │   composes stores, owns
   │  (governance, audit, versioning,    │   runtime behavior, MLX
   │   on-device PII filter, mail sync)  │   privacy filter
   └────────────────┬────────────────────┘
                    │
   ┌────────────────▼────────────────────┐
   │  ManifoldKit                        │   shared models, types,
   │  (rules, grants, exposure records,  │   diagnostics, value
   │   version snapshots)                │   handles
   └─────────────────────────────────────┘

   ┌─────────────────────────────────────┐
   │  manifold-mcp (executable)          │   thin XPC client. Speaks
   │  manifold-cli (executable)          │   MCP / shell to the
   │  ManifoldAgent (executable)         │   runtime. No business logic.
   └─────────────────────────────────────┘
```

## The modules

| Module               | Type        | Purpose                                                  |
| -------------------- | ----------- | -------------------------------------------------------- |
| `ManifoldApp`        | App bundle  | The SwiftUI app. Onboarding, settings, audit log views.  |
| `ManifoldKit`        | Library     | Shared models, value handles, diagnostic event types.    |
| `ManifoldRuntime`    | Library     | Governance, version snapshots, mail sync, MLX filter.    |
| `ManifoldXPC`        | Library     | Typed XPC interface and audience trust checks.           |
| `ManifoldMCP`        | Executable  | `manifold-mcp` MCP server. XPC client to the runtime.    |
| `ManifoldCLI`        | Executable  | `manifold-cli` shell client. Same XPC, no UI.            |
| `ManifoldAgent`      | Executable  | Background agent process for long-running runtime jobs.  |

## Two kinds of access

**Standing access is read access.** When you grant Claude or Codex a
file or folder, you are granting *read*. The runtime serves the bytes
through the governance layer; nothing happens to your filesystem.

**Tracked work blocks are write access.** When an AI proposes to modify
a file, the runtime stages the change in a tracked workspace and prompts
you to Deny, Allow once, or Add to default. Approved writes land as a
new version on disk; the previous version stays in the snapshot store
and is recoverable from any later chat.

**Do not collapse these paths.** Read does not become write because the
caller "needs to". Write requires a Tracked Work Block. Always.

## Data flow: a Claude read request

1. Claude (or Codex) calls a tool on `manifold-mcp` over MCP.
2. `manifold-mcp` forwards the request via `ManifoldXPC` to the
   running `ManifoldAgent`.
3. `ManifoldXPC` validates the caller's audience and method.
4. `ManifoldRuntime` resolves the rule set, checks grants, runs the
   on-device PII filter (preflight), records an exposure entry in the
   audit log.
5. If the request passes, the runtime returns the bytes. If it does
   not, it returns a typed denial with a reason code.

Nothing in steps 1-5 calls the network for the AI's request.

## Data flow: a Claude write proposal

1. Claude calls the write tool on `manifold-mcp` with the proposed
   file content.
2. `ManifoldRuntime` opens (or reuses) a Tracked Work Block for the
   target path.
3. The runtime computes a diff against the current version on disk.
4. The app surfaces the diff to you with Deny / Allow once / Add to
   default.
5. On approve, the runtime writes the new version, records the prior
   version as a snapshot, and stamps an audit entry with the rule and
   AI identity that proposed it.

## Storage

A local **governance database** in your home directory stores rules,
grants, exposure records, version snapshots, and scoped memory.

- Owner-only filesystem permissions.
- AES-GCM encryption keyed from the macOS Keychain.
- Nothing is uploaded.

The `LocalAuthConfig` plist controls auth-related toggles and lives
next to the database; it is never bundled into the app and is not
committed to the repo (see `.gitignore`).

## Update path (Sparkle)

The app polls a static appcast at
`https://github.com/Spatial-Duality/Manifold/releases/latest/download/appcast.xml`.
The Sparkle EdDSA public key is embedded in the app; the matching private key
signs releases before they are published.

`scripts/generate_appcast.sh` produces the `appcast.xml` for a
notarized DMG. `scripts/validate_appcast.sh` verifies it before
publication.

## The on-device PII filter

The OpenAI Privacy Filter runs on **MLX**. It executes as a preflight
rule in `ManifoldRuntime`: every shared file and message is screened
for PII patterns (2FA codes, SSNs, addresses, names, phone, account
numbers) and either masked, warned about, or blocked according to the
active rule set. The filter never opens a network socket. Apple Silicon
is required because MLX is.

## Threat model summary

The short version:

- **Trusted:** the user, the local Manifold processes, the macOS
  sandbox, the Keychain.
- **Untrusted:** the AI, the file content, the email content, anything
  off-device.
- **Boundary:** `ManifoldXPC` audience checks + governance layer in
  `ManifoldRuntime`.

Anything that crosses the boundary in either direction must be
explicitly modeled. If you find yourself adding a back channel,
something is wrong with the design.
