# Changelog

All notable changes to Manifold are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-05-03

Initial public release. The app, runtime, MCP bridge, on-device PII
filter, version history, and audit log are all in this version.

### Added
- SwiftUI Mac app for governing what Claude and Codex can see.
- `manifold-mcp` MCP server. Registers automatically with Claude
  and Codex Mac apps (and the CLI variants if installed) via
  `manifold-mcp --install`.
- Per-AI per-file allow/deny across Claude and Codex. Default-deny on
  contracts, payroll, tax filings, and other sensitive paths.
- Mail support for iCloud, Gmail, and Microsoft 365 (plus IMAP).
  Inbox is denied by default; grant per message or thread, per AI.
- Tracked Work Blocks for AI-proposed writes. Deny, Allow once, or
  Add to default; previous versions remain recoverable.
- Version snapshots per file, accessible from any later chat.
- AI-usage audit log with timestamp, matched rule, and file version.
  Stays on your Mac.
- On-device PII filter (OpenAI Privacy Filter on MLX) as a preflight
  rule. Masks, warns, or blocks 2FA codes, addresses, names, phone
  numbers, account numbers, government IDs.
- Sparkle update path with EdDSA-signed appcast.
- AES-GCM encrypted local governance database (rules, grants,
  exposure records, snapshots, scoped memory) keyed from the
  Keychain.

### Security
- No product telemetry.
- Network access is limited to explicit user-facing flows such as mail,
  OAuth, downloads, and Sparkle updates.
- Audit trail records both what was exposed and whether the PII
  filter ran.

[Unreleased]: https://github.com/Spatial-Duality/Manifold/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/Spatial-Duality/Manifold/releases/tag/v0.4.0
