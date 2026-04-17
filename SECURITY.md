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
- XPC service authentication and authorization
- MCP server access control
- Unauthorized local process access to Manifold's XPC or MCP surfaces
- Snapshot and content store integrity
- Workspace isolation boundaries
- Restore and rollback safety for governed files
- Exposure record, snapshot, and email archive confidentiality

## Out of scope

- The Manifold app UI (cosmetic issues)
- Native Claude/Codex capabilities, vendor-hosted connectors, or computer-use features that do not route through Manifold
- Denial of service via local access that does not cross Manifold's trust boundary
- Issues in dependencies we don't control
