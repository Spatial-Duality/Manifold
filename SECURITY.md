# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability in Manifold, please report it responsibly.

**Email:** security@spatialduality.com

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge your report within 48 hours and aim to provide a fix or mitigation within 7 days for critical issues.

## Scope

- ManifoldRuntime policy enforcement (ManifoldBridge)
- Rule engine evaluation — bypasses, precedence errors, or seed-deny shadowing in `RuleEngine`/`RuleStore`
- XPC service authentication and authorization, including `SignedProcessVerifier` code-signing checks
- MCP server access control
- Unauthorized local process access to Manifold's XPC or MCP surfaces
- `ScopedFileIdentity` path normalization — symlink, `..`, or prefix-stripping attacks that reach a governed file the rule engine would otherwise block
- On-disk protection (`LocalFileProtection` file perms, `ProtectedStorageCrypto` AES-GCM at rest and Keychain key handling)
- Snapshot and content store integrity
- Workspace isolation boundaries
- Restore and rollback safety for governed files
- Exposure record, snapshot, and email archive confidentiality

## Out of scope

- The Manifold app UI (cosmetic issues)
- Native Claude/Codex capabilities, vendor-hosted connectors, or computer-use features that do not route through Manifold
- Denial of service via local access that does not cross Manifold's trust boundary
- Issues in dependencies we don't control
