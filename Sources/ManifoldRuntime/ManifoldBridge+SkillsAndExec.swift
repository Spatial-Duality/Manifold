// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

/// Skill manifest + ManifoldExec deterministic JSON-plan tools.
///
/// `run_code` is the only entry to the deterministic plan runtime. Plans are
/// JSON arrays of `{op, ...}` steps; the static refusal check rejects shell,
/// network, raw filesystem, and state-changing ops before any step executes.
/// Skills wrap a saved manifest by hash and reuse the same execution path.
extension ManifoldBridge {
    public func runCode(code: String, language: String? = nil) async throws -> ExecRunResult {
        let (_, decisionID) = try await resolveAccessForTool(toolName: "run_code", action: "exec")
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || language?.lowercased() == "status" {
            return await persistExecResult(
                ExecRunResult(
                    status: .completed,
                    reason: "ManifoldExec deterministic JSON-plan runtime is enabled.",
                    output: """
                    Supported language: manifoldexec-json
                    Supported ops: recall_memory, reuse_prior_context, was_exposed_before, what_changed_since, search_structured, query_graph, list_skills, tool_cost_report, verify_ledger_entry
                    Denied inside Exec: shell, network, raw filesystem, write_file, write_binary_file, annotate_pdf, read_file, read_email, save_memory_note, forget_memory, save_skill
                    """
                ),
                toolName: "run_code",
                resourcePath: "status",
                decisionID: decisionID
            )
        }

        guard Self.isSupportedExecLanguage(language) else {
            return await persistExecResult(
                ExecRunResult(
                    status: .refused,
                    reason: "ManifoldExec only accepts deterministic JSON plans, not arbitrary \(language ?? "code").",
                    suggestedAlternative: "Pass JSON like {\"steps\":[{\"op\":\"recall_memory\",\"query\":\"invoice\"}]}."
                ),
                toolName: "run_code",
                resourcePath: "unsupported-language",
                decisionID: decisionID
            )
        }

        let steps: [[String: Any]]
        do {
            steps = try Self.execSteps(from: trimmed)
        } catch {
            return await persistExecResult(
                ExecRunResult(
                    status: .refused,
                    reason: "ManifoldExec refused non-plan input: \(error.localizedDescription)",
                    suggestedAlternative: "Use a JSON object with a steps array. Raw Python, shell, JavaScript, network, and filesystem access are not accepted."
                ),
                toolName: "run_code",
                resourcePath: "invalid-plan",
                decisionID: decisionID
            )
        }

        if let refusal = Self.staticExecRefusal(for: steps) {
            return await persistExecResult(refusal, toolName: "run_code", resourcePath: "refused-plan", decisionID: decisionID)
        }

        do {
            let output = try await executeExecSteps(steps)
            return await persistExecResult(
                ExecRunResult(status: .completed, reason: "ManifoldExec plan completed.", output: output),
                toolName: "run_code",
                resourcePath: "plan",
                decisionID: decisionID
            )
        } catch {
            return await persistExecResult(
                ExecRunResult(status: .failed, reason: error.localizedDescription),
                toolName: "run_code",
                resourcePath: "failed-plan",
                decisionID: decisionID
            )
        }
    }

    public func listSkills(limit: Int = 50) async throws -> String {
        let (_, decisionID) = try await resolveAccessForTool(toolName: "list_skills", action: "skill")
        let skills = (try? await skillStore?.list(limit: limit)) ?? []
        let text = skills.isEmpty
            ? "No saved skills."
            : skills.map { "- [\($0.skillID)] \($0.name) manifest=\(String($0.manifestHash.prefix(12))) executable=json-plan" }.joined(separator: "\n")
        await recordExposure(toolName: "list_skills", resourcePath: nil, text: text, exposureType: "skill", decisionID: decisionID)
        return text
    }

    public func saveSkill(name: String, manifestJSON: String) async throws -> String {
        let (_, decisionID) = try await resolveAccessForTool(toolName: "save_skill", action: "skill_write", resourcePath: name)
        guard let skillStore else {
            return "Skill store unavailable."
        }
        let skill = try await skillStore.save(name: name, manifestJSON: manifestJSON)
        try await ledgerStore?.append(
            entryType: .skill,
            subjectTable: "skill_records",
            subjectID: skill.skillID,
            payload: Self.canonicalJSON(skill),
            metadata: ["name": skill.name, "manifest_hash": skill.manifestHash]
        )
        _ = try? await knowledgeGraphStore?.upsertNode(
            kind: "skill",
            label: "\(skill.name) \(skill.manifestHash)",
            lineage: []
        )
        let text = "Saved skill \(skill.name) with manifest \(skill.manifestHash). JSON-plan invocation is enabled; scope or sink changes require a new manifest hash."
        await recordExposure(toolName: "save_skill", resourcePath: skill.skillID, text: text, exposureType: "skill", decisionID: decisionID)
        return text
    }

    public func invokeSkill(name: String) async throws -> ExecRunResult {
        let (_, decisionID) = try await resolveAccessForTool(toolName: "invoke_skill", action: "skill", resourcePath: name)
        guard let skillStore else {
            return ExecRunResult(status: .failed, reason: "Skill store unavailable.")
        }
        guard let skill = try await skillStore.skill(named: name) else {
            return await persistExecResult(
                ExecRunResult(status: .failed, reason: "No saved skill named \(name)."),
                toolName: "invoke_skill",
                resourcePath: name,
                decisionID: decisionID
            )
        }

        if Self.ruleOfTwoTriggered(in: skill.manifestJSON) {
            return await persistExecResult(
                ExecRunResult(
                    status: .needsApproval,
                    reason: "Rule of Two requires explicit approval because the skill combines untrusted input, sensitive data, and a state-changing action.",
                    suggestedAlternative: "Split the skill into a read-only extraction step and a separate approved write/send step."
                ),
                toolName: "invoke_skill",
                resourcePath: name,
                decisionID: decisionID
            )
        }

        do {
            let steps = try Self.execSteps(from: skill.manifestJSON)
            if let refusal = Self.staticExecRefusal(for: steps) {
                return await persistExecResult(refusal, toolName: "invoke_skill", resourcePath: name, decisionID: decisionID)
            }
            let output = try await executeExecSteps(steps)
            return await persistExecResult(
                ExecRunResult(
                    status: .completed,
                    reason: "Skill \(skill.name) completed with manifest \(skill.manifestHash).",
                    output: output
                ),
                toolName: "invoke_skill",
                resourcePath: name,
                decisionID: decisionID
            )
        } catch {
            return await persistExecResult(
                ExecRunResult(
                    status: .failed,
                    reason: "Skill \(skill.name) manifest is not an executable JSON plan: \(error.localizedDescription).",
                    suggestedAlternative: "Save a manifest shaped like {\"steps\":[{\"op\":\"recall_memory\",\"query\":\"invoice\"}]}."
                ),
                toolName: "invoke_skill",
                resourcePath: name,
                decisionID: decisionID
            )
        }
    }
}
