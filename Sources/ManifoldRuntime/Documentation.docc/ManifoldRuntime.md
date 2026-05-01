#  ``ManifoldRuntime``

The single composition root for all Manifold stores and the policy bridge that gates every governed access decision.

## Overview

`ManifoldRuntime` constructs the full store graph (audit log, email index,
content store, snapshot store, exposure ledger, etc.) and exposes it through a
single Swift actor. The XPC service layer (``ManifoldXPC``) wraps this actor;
the app, CLI, and MCP server are all XPC clients that never construct stores
themselves.

This is the boundary at which the trust product enforces its rules:
- Every read goes through `ManifoldBridge.callTool`, which checks the
  `RuleEngine` before returning data.
- Writes are scoped to a `WorkBlock` opened explicitly by the user — standing
  access never includes write capability.
- Agent identity is verified via signed-process attestation
  (``ManifoldXPC/SignedProcessVerifier``), never trusted from a string label.

## Initialization order

`ManifoldRuntime.init(storeURL:)` is synchronous and must complete before the
XPC listener accepts connections. The order matters:

```
1. Open SQLite at storeURL/manifold.db
2. Run pending migrations (in transaction)
3. MailFreshStartReset.cleanupIfNeeded — destroys legacy mail data on v39
4. Construct stores (ContentStore, AuditStore, EmailStore, WorkBlockStore, …)
5. Construct rule + policy stores
6. Construct privacy + index coordinators
7. Schedule one-shot background work via Task: GC, snapshot prune, approval expiry
```

`bootstrap()` is called once after init from the LaunchAgent's `RunLoop.main`;
it seeds the rule catalog, registers enabled mail accounts with the sync
coordinator, and starts the privacy index coordinator.

## Topics

### Composition

- ``ManifoldRuntime``
- ``ManifoldBridge``

### Privacy

- ``PrivacyContentExtractor``
- ``PrivacyRuntimeManager``
