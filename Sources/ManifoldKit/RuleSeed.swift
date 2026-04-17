// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Curated catalog of seeded rules installed on first launch. These are the security
/// floor — always enabled, not directly editable. Users who need to override a seed
/// create a `.userOverride` rule via the UI.
public enum RuleSeedCatalog {

    /// Stable ID so upgrades don't duplicate the same rule.
    public struct SeedID {
        public static let secretsPaths = "seed-file-secret-paths"
        public static let secretsDetector = "seed-file-secret-detector"
        public static let sshKeys = "seed-file-ssh-keys"
        public static let awsCredentials = "seed-file-aws-credentials"
        public static let largeFileWarn = "seed-file-large-warn"
        public static let emailSecurityShield = "seed-email-shield-security"
        public static let emailFinancialShield = "seed-email-shield-financial"
        public static let emailMedicalShield = "seed-email-shield-medical"
        public static let emailLegalShield = "seed-email-shield-legal"
        public static let emailOTPSubjects = "seed-email-otp-subjects"
        public static let agentRedactPII = "seed-agent-redact-pii"
    }

    /// Returns the full list of seeded rules. Deterministic order: files → emails → agents,
    /// then `orderIndex` per group.
    public static func seeds(now: Date = Date()) -> [RuleRecord] {
        let iso = ISO8601DateFormatter.shared.string(from: now)
        var rules: [RuleRecord] = []

        // ── Files ─────────────────────────────────────────────────────────────
        rules.append(RuleRecord(
            id: SeedID.secretsPaths,
            name: "Block secret files by path",
            explanation: "Refuses to share .env, .pem, .key, and other well-known secret files with any agent.",
            scope: .file,
            matcher: .any([
                .pathGlob("**/.env"),
                .pathGlob("**/.env.*"),
                .pathGlob("**/*.pem"),
                .pathGlob("**/*.key"),
                .pathGlob("**/id_rsa*"),
                .pathGlob("**/id_ed25519*"),
                .pathGlob("**/id_dsa*"),
                .pathGlob("**/.netrc"),
                .pathGlob("**/.npmrc"),
                .pathGlob("**/.pypirc"),
                .pathGlob("**/.gitconfig"),
                .pathGlob("**/.git/config"),
            ]),
            action: .deny,
            agents: [],
            window: .always,
            source: .seeded,
            enabled: true,
            orderIndex: 0,
            createdAt: iso,
            updatedAt: iso
        ))

        rules.append(RuleRecord(
            id: SeedID.sshKeys,
            name: "Block SSH & GPG directories",
            explanation: "Refuses anything under ~/.ssh/ or ~/.gnupg/.",
            scope: .file,
            matcher: .any([
                .pathGlob("**/.ssh/**"),
                .pathGlob("**/.gnupg/**"),
            ]),
            action: .deny,
            agents: [],
            source: .seeded,
            enabled: true,
            orderIndex: 1,
            createdAt: iso,
            updatedAt: iso
        ))

        rules.append(RuleRecord(
            id: SeedID.awsCredentials,
            name: "Block cloud credentials",
            explanation: "Refuses AWS, GCP, Azure, and Kubernetes credentials directories.",
            scope: .file,
            matcher: .any([
                .pathGlob("**/.aws/credentials"),
                .pathGlob("**/.aws/config"),
                .pathGlob("**/.config/gcloud/**"),
                .pathGlob("**/.azure/**"),
                .pathGlob("**/.kube/config"),
                .pathGlob("**/.docker/config.json"),
            ]),
            action: .deny,
            agents: [],
            source: .seeded,
            enabled: true,
            orderIndex: 2,
            createdAt: iso,
            updatedAt: iso
        ))

        rules.append(RuleRecord(
            id: SeedID.secretsDetector,
            name: "Block files containing detected secrets",
            explanation: "Refuses any file whose body matches known API-token, JWT, or private-key patterns.",
            scope: .file,
            matcher: .fileSecretDetected,
            action: .deny,
            agents: [],
            source: .seeded,
            enabled: true,
            orderIndex: 3,
            createdAt: iso,
            updatedAt: iso
        ))

        rules.append(RuleRecord(
            id: SeedID.largeFileWarn,
            name: "Warn on large files",
            explanation: "Surfaces a confirmation prompt for files over 50 MB so the agent's context isn't flooded accidentally.",
            scope: .file,
            matcher: .fileSizeOver(50 * 1024 * 1024),
            action: .warn,
            agents: [],
            source: .seeded,
            enabled: true,
            orderIndex: 10,
            createdAt: iso,
            updatedAt: iso
        ))

        // ── Emails ────────────────────────────────────────────────────────────
        rules.append(RuleRecord(
            id: SeedID.emailSecurityShield,
            name: "Block security emails",
            explanation: "Catches 2FA codes, password-reset links, verification emails, login alerts.",
            scope: .email,
            matcher: .emailShield(.security),
            action: .deny,
            agents: [],
            source: .seeded,
            enabled: true,
            orderIndex: 0,
            createdAt: iso,
            updatedAt: iso
        ))

        rules.append(RuleRecord(
            id: SeedID.emailFinancialShield,
            name: "Block financial emails",
            explanation: "Catches bank statements, tax documents, transaction alerts.",
            scope: .email,
            matcher: .emailShield(.financial),
            // Different action per agent: Codex blocks hard; Claude cowork warns.
            // The rule as stored is `deny`; PolicyStore's default plus an agent override
            // rule elsewhere will soften the Claude case. (Follow-up: per-agent action tiers.)
            action: .deny,
            agents: [],
            source: .seeded,
            enabled: true,
            orderIndex: 1,
            createdAt: iso,
            updatedAt: iso
        ))

        rules.append(RuleRecord(
            id: SeedID.emailMedicalShield,
            name: "Block medical emails",
            explanation: "Catches lab results, prescriptions, insurance claims, provider messages.",
            scope: .email,
            matcher: .emailShield(.medical),
            action: .deny,
            agents: [],
            source: .seeded,
            enabled: true,
            orderIndex: 2,
            createdAt: iso,
            updatedAt: iso
        ))

        rules.append(RuleRecord(
            id: SeedID.emailLegalShield,
            name: "Warn on legal emails",
            explanation: "Flags NDAs, contracts, attorney correspondence for explicit confirmation.",
            scope: .email,
            matcher: .emailShield(.legal),
            action: .warn,
            agents: [],
            source: .seeded,
            enabled: true,
            orderIndex: 3,
            createdAt: iso,
            updatedAt: iso
        ))

        rules.append(RuleRecord(
            id: SeedID.emailOTPSubjects,
            name: "Block OTP & verification subjects",
            explanation: "Catches password-reset, verification code, 2FA, and one-time password subject lines.",
            scope: .email,
            matcher: .any([
                .emailSubjectKeyword("password reset", regex: false),
                .emailSubjectKeyword("verification code", regex: false),
                .emailSubjectKeyword("2fa", regex: false),
                .emailSubjectKeyword("one-time", regex: false),
                .emailSubjectKeyword("security alert", regex: false),
            ]),
            action: .deny,
            agents: [],
            source: .seeded,
            enabled: true,
            orderIndex: 4,
            createdAt: iso,
            updatedAt: iso
        ))

        // ── Agents ────────────────────────────────────────────────────────────
        rules.append(RuleRecord(
            id: SeedID.agentRedactPII,
            name: "Redact PII in agent payloads",
            explanation: "Strips detected emails, phone numbers, and SSNs from any payload sent to an agent unless an override rule allows it.",
            scope: .agent,
            matcher: .agentTool(.read),
            action: .redact,
            agents: [],
            source: .seeded,
            enabled: true,
            orderIndex: 0,
            createdAt: iso,
            updatedAt: iso
        ))

        return rules
    }
}
