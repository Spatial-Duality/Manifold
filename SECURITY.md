# Security policy

Manifold mediates AI access to your files and email. Security issues in
Manifold can leak the things you trusted Manifold to keep private. We treat
them as such.

## Supported versions

| Version  | Supported |
| -------- | --------- |
| 0.4.x    | Yes       |
| < 0.4    | No        |

We support the latest minor release. Older versions stop receiving security
updates as soon as a new minor ships.

## Reporting a vulnerability

**Please do not open a public issue for security reports.**

Use one of these private channels:

1. **GitHub Security Advisory.** Open a private advisory at
   https://github.com/Spatial-Duality/Manifold/security/advisories/new.
   This is the preferred path. It keeps the report private and lets us
   collaborate on a fix in the same place.
2. **Email.** Send to security@spatialduality.com. Include a description,
   repro steps, the Manifold version, and the macOS version.

## What to expect

- **Acknowledgement** within 72 hours.
- **Initial assessment** within 7 days.
- **Fix or mitigation plan** before disclosure, with the timeline driven by
  severity.
- **Credit in the advisory** unless you ask us not to.

## Scope

In scope:
- The Manifold app and runtime
- The MCP bridge (`manifold-mcp`)
- The on-device PII filter
- The local governance database (storage, encryption, permissions)
- The Sparkle update path
- Anything that could leak file or email content to an AI you did not grant
  access to

Out of scope:
- Bugs in Claude, Codex, or other upstream MCP clients
- Issues that require physical access to an unlocked Mac
- Self-XSS or social engineering against the user
- Reports against unsupported versions (see table above)

## Disclosure

We default to a **90-day coordinated disclosure window** from the date of
first contact. We will publish a security advisory with details once a fix
ships, and will credit reporters who want credit.

We do not run a bug bounty. We do read every report.
