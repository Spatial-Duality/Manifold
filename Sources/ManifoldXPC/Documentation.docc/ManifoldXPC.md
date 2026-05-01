#  ``ManifoldXPC``

The XPC boundary between the Manifold app, the `manifold-mcp` MCP server, and the `ManifoldAgent` LaunchAgent that hosts the runtime.

## Overview

`ManifoldXPC` provides:

- ``ManifoldXPCProtocol`` — the Objective-C-friendly protocol every IPC call
  flows through.
- ``ManifoldXPCClient`` — used by the app, the MCP server, and the CLI to
  reach the agent. Notifies observers via
  `connectionStateChangedNotification` when the connection invalidates so
  app-side state can react in <100ms instead of waiting for a poll cycle.
- ``ManifoldXPCService`` — the agent-side service that hosts
  `ManifoldRuntime` and dispatches incoming commands.
- ``SignedProcessVerifier`` and ``ClientIdentityVerifier`` — agent identity
  attestation. Every connection's signing identity is checked before any
  governed call is allowed.

## Architecture

```
┌─────────────┐  ┌──────────────────┐  ┌─────────────────┐
│ Manifold.app│  │ manifold-cli     │  │ manifold-mcp    │
└──────┬──────┘  └─────────┬────────┘  └────────┬────────┘
       │                   │                    │
       │            ManifoldXPCClient           │
       │                   │                    │
       └───────────────────┼────────────────────┘
                           │
                ┌──────────▼──────────┐
                │ Mach service        │
                │ (com.spatialduality │
                │  .manifold.runtime) │
                └──────────┬──────────┘
                           │
                ┌──────────▼──────────┐
                │ ManifoldXPCService  │
                │ (in ManifoldAgent)  │
                │   │                 │
                │   └─► ManifoldRuntime
                └─────────────────────┘
```

## Hard rules

- The XPC layer is the **only** way to talk to `ManifoldRuntime`. The app must
  not construct stores in-process.
- `SignedProcessVerifier` verifies every connection's code signature before
  the agent dispatches commands. Unsigned or mismatched-team-ID processes are
  rejected.
- Sensitive data (passwords, OAuth token sets) **must not cross the XPC
  boundary as plaintext payload values**. The R5 pattern is: app writes
  Keychain, sends a UUID-shaped reference, agent reads from Keychain.

## Topics

### Client

- ``ManifoldXPCClient``

### Service

- ``ManifoldXPCService``
- ``ManifoldXPCProtocol``

### Identity verification

- ``SignedProcessVerifier``
- ``ClientIdentityVerifier``
- ``ProcessAttestation``

### Errors

- ``ManifoldXPCError``
