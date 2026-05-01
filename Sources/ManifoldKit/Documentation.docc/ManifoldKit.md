#  ``ManifoldKit``

Local types, stores, and policy primitives that govern what AI agents can see through Manifold.

## Overview

ManifoldKit is the data + policy layer of the Manifold runtime. It owns:

- **Persistence**: SQLite-backed `EmailStore`, `MailArchiveStore`, `ExposureStore`,
  `AuditStore`, `SnapshotStore`, `ContentStore`, and `WorkBlockStore`.
- **Schema lifecycle**: ``DatabaseMigrator`` runs each numbered migration in a
  transaction; `repairCurrentSchema` handles incremental schema drift.
- **Policy primitives**: `RuleStore`, `PolicyStore`, `EmailPolicyEngine`, and
  `RuleEngine` evaluate every governed access decision before content leaves
  Manifold.
- **Content storage**: ``ContentStore`` stores blobs by content-addressable hash
  with deduplication and garbage collection.
- **Mail subsystem**: ``EmailSyncEngine`` and ``MailSyncCoordinator`` keep
  IMAP backups fresh; ``KeychainMailSecretStore`` holds credentials in Keychain
  (never in process memory longer than necessary).

## Architecture

ManifoldKit has zero UI dependencies. The app target embeds it through
``ManifoldRuntime`` as the single composition root. The XPC layer
(``ManifoldXPC``) marshals calls between the in-process app and the
out-of-process `ManifoldAgent` LaunchAgent, which is the only process that
constructs runtime stores.

```
ManifoldApp ──► ManifoldXPC.client ──► ManifoldAgent (separate process)
                                            │
                                            └─► ManifoldRuntime
                                                   │
                                                   └─► ManifoldKit (this module)
```

## Hard rules

- **Standing access = read; Tracked Work Block = write.** Never extend standing
  access with a quiet write path. Writes go through a `WorkBlock`.
- **Verified identity, not declared identity.** `RuleEngine` resolves the agent
  via signed-process verification, never the self-reported label.
- **Single composition root.** Stores must not be constructed outside
  ``ManifoldRuntime``. The XPC client + MCP + CLI all flow through it.

## Topics

### Persistence

- ``EmailStore``
- ``EmailSyncEngine``
- ``MailArchiveStore``
- ``MailSyncCoordinator``
- ``ContentStore``
- ``DatabaseMigrator``

### Policy

- ``RuleStore``
- ``EmailPolicyEngine``

### Credentials

- ``KeychainMailSecretStore``

### Configuration

- ``ConfigWriter``

### Types

- ``EmailAccount``
- ``WorkBlockRecord``
- ``MailCredentialReference``
- ``MailCredentialKind``
