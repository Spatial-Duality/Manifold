// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

enum OfficialCLIBackendError: Error, LocalizedError {
    case notInstalled
    case helperUnavailable(String)
    case invalidResponse
    case unsupportedLabel(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Official CLI backend is not installed."
        case .helperUnavailable(let detail):
            return "Official CLI helper is unavailable: \(detail)"
        case .invalidResponse:
            return "Official CLI helper returned an invalid response."
        case .unsupportedLabel(let label):
            return "Official CLI helper returned an unsupported label: \(label)"
        }
    }
}

actor OfficialCLIPrivacyBackend: PrivacyBackend {
    let kind: PrivacyBackendKind = .officialCLI

    private let storageURL: URL
    private let installRootURL: URL
    private let helperScriptURL: URL
    private let venvURL: URL
    private let checkpointURL: URL
    private let pythonExecutableURL: URL
    private let modelID = "openai/privacy-filter"

    private var helperProcess: Process?
    private var helperStdIn: FileHandle?
    private var helperStdOut: FileHandle?
    private var helperStdErr: FileHandle?
    private var stdoutBuffer = Data()
    private var lastError: String?
    private var modelVersion = "openai/privacy-filter"

    init(storageURL: URL) {
        self.storageURL = storageURL
        self.installRootURL = storageURL.appendingPathComponent("official-cli", isDirectory: true)
        self.helperScriptURL = installRootURL.appendingPathComponent("privacy_filter_helper.py")
        self.venvURL = installRootURL.appendingPathComponent("venv", isDirectory: true)
        self.checkpointURL = installRootURL.appendingPathComponent("checkpoint", isDirectory: true)
        self.pythonExecutableURL = venvURL.appendingPathComponent("bin/python")
    }

    func install() async throws -> PrivacyModelInfo {
        try FileManager.default.createDirectory(at: installRootURL, withIntermediateDirectories: true)
        try writeHelperScript()

        if !FileManager.default.fileExists(atPath: pythonExecutableURL.path) {
            try runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: ["-m", "venv", venvURL.path]
            )
        }

        try runProcess(executableURL: pythonExecutableURL, arguments: ["-m", "pip", "install", "--upgrade", "pip"])
        try runProcess(
            executableURL: pythonExecutableURL,
            arguments: [
                "-m", "pip", "install",
                "git+https://github.com/openai/privacy-filter.git",
                "huggingface_hub",
            ]
        )

        try await load()
        let response = try sendCommand(
            [
                "command": "install",
                "checkpoint_dir": checkpointURL.path,
                "model_id": modelID,
            ]
        )
        if let resolvedModelVersion = response["model_version"] as? String {
            modelVersion = resolvedModelVersion
        }
        return await modelInfo()
    }

    func uninstall() async throws {
        await unload()
        if FileManager.default.fileExists(atPath: installRootURL.path) {
            try FileManager.default.removeItem(at: installRootURL)
        }
        lastError = nil
    }

    func load() async throws {
        guard isInstalled else {
            throw OfficialCLIBackendError.notInstalled
        }
        if helperProcess?.isRunning == true {
            return
        }

        try writeHelperScript()
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = pythonExecutableURL
        process.arguments = [helperScriptURL.path]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        helperProcess = process
        helperStdIn = stdinPipe.fileHandleForWriting
        helperStdOut = stdoutPipe.fileHandleForReading
        helperStdErr = stderrPipe.fileHandleForReading
        stdoutBuffer.removeAll(keepingCapacity: false)

        let response = try sendCommand(
            [
                "command": "warm",
                "checkpoint_dir": checkpointURL.path,
                "model_version": modelVersion,
                "device": "cpu",
            ]
        )
        if let resolvedModelVersion = response["model_version"] as? String {
            modelVersion = resolvedModelVersion
        }
    }

    func unload() async {
        if helperProcess?.isRunning == true {
            _ = try? sendCommand(["command": "shutdown"])
        }
        helperStdIn?.closeFile()
        helperStdOut?.closeFile()
        helperStdErr?.closeFile()
        helperProcess?.terminate()
        helperProcess = nil
        helperStdIn = nil
        helperStdOut = nil
        helperStdErr = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
    }

    func modelInfo() async -> PrivacyModelInfo {
        PrivacyModelInfo(
            modelVersion: modelVersion,
            available: isInstalled,
            loaded: helperProcess?.isRunning == true,
            note: lastError
        )
    }

    func scan(_ request: PrivacyScanRequest) async throws -> PrivacyScanResult {
        let results = try await scanBatch([request])
        guard let result = results.first else {
            throw OfficialCLIBackendError.invalidResponse
        }
        return result
    }

    func scanBatch(_ requests: [PrivacyScanRequest]) async throws -> [PrivacyScanResult] {
        guard !requests.isEmpty else { return [] }
        try await load()

        let response = try sendCommand(
            [
                "command": "scan_batch",
                "checkpoint_dir": checkpointURL.path,
                "device": "cpu",
                "items": requests.map { request in
                    [
                        "text": request.text,
                        "operating_point": request.operatingPoint,
                    ]
                },
            ]
        )

        guard let rawResults = response["results"] as? [[String: Any]],
              rawResults.count == requests.count else {
            throw OfficialCLIBackendError.invalidResponse
        }

        return try zip(requests, rawResults).map { request, rawResult in
            try Self.scanResult(from: rawResult, request: request, modelVersion: modelVersion)
        }
    }

    private var isInstalled: Bool {
        FileManager.default.fileExists(atPath: pythonExecutableURL.path)
            && FileManager.default.fileExists(atPath: checkpointURL.appendingPathComponent("config.json").path)
    }

    private func writeHelperScript() throws {
        let data = Data(Self.helperScript.utf8)
        if FileManager.default.fileExists(atPath: helperScriptURL.path),
           let existing = try? Data(contentsOf: helperScriptURL),
           existing == data {
            return
        }
        try data.write(to: helperScriptURL, options: .atomic)
    }

    private func runProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderrText = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            lastError = stderrText
            throw OfficialCLIBackendError.helperUnavailable(stderrText)
        }
    }

    private func sendCommand(_ payload: [String: Any]) throws -> [String: Any] {
        guard let helperStdIn, let helperStdOut else {
            throw OfficialCLIBackendError.helperUnavailable("helper pipes are not open")
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        helperStdIn.write(data)
        helperStdIn.write(Data([0x0A]))

        let line = try readLine(from: helperStdOut)
        guard let jsonData = line.data(using: .utf8),
              let response = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw OfficialCLIBackendError.invalidResponse
        }

        if let ok = response["ok"] as? Bool, ok == false {
            let message = response["error"] as? String ?? "unknown helper error"
            lastError = message
            throw OfficialCLIBackendError.helperUnavailable(message)
        }

        lastError = nil
        if let result = response["result"] as? [String: Any] {
            return result
        }
        return response
    }

    private func readLine(from handle: FileHandle) throws -> String {
        while true {
            if let newlineRange = stdoutBuffer.range(of: Data([0x0A])) {
                let lineData = stdoutBuffer.subdata(in: 0..<newlineRange.lowerBound)
                stdoutBuffer.removeSubrange(0..<newlineRange.upperBound)
                if let line = String(data: lineData, encoding: .utf8) {
                    return line
                }
            }

            let chunk = try handle.read(upToCount: 4_096) ?? Data()
            if chunk.isEmpty {
                let stderrText = helperStdErr.flatMap {
                    String(data: $0.readDataToEndOfFile(), encoding: .utf8)
                }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "helper closed stdout"
                lastError = stderrText
                throw OfficialCLIBackendError.helperUnavailable(stderrText)
            }
            stdoutBuffer.append(chunk)
        }
    }

    private static func scanResult(
        from rawResult: [String: Any],
        request: PrivacyScanRequest,
        modelVersion: String
    ) throws -> PrivacyScanResult {
        let rawSpans = rawResult["detected_spans"] as? [[String: Any]] ?? []
        let spans = try rawSpans.compactMap { rawSpan in
            try detectedSpan(from: rawSpan, text: request.text)
        }

        let redactedText = rawResult["redacted_text"] as? String ?? request.text
        let elapsedMs: Int
        if let latencyMs = rawResult["latency_ms"] as? Double {
            elapsedMs = Int(latencyMs.rounded())
        } else if let latencyMs = rawResult["latency_ms"] as? Int {
            elapsedMs = latencyMs
        } else {
            elapsedMs = 0
        }

        return PrivacyScanResult(
            spans: spans,
            redactedText: redactedText,
            findingsSummary: summary(for: spans),
            backend: .officialCLI,
            modelVersion: modelVersion,
            elapsedMs: elapsedMs,
            cacheHit: false
        )
    }

    private static func detectedSpan(
        from rawSpan: [String: Any],
        text: String
    ) throws -> DetectedSpan? {
        guard let label = rawSpan["label"] as? String,
              let start = rawSpan["start"] as? Int,
              let end = rawSpan["end"] as? Int else {
            return nil
        }
        let category = try category(for: label)
        let converted = try utf16Range(in: text, scalarStart: start, scalarEnd: end)
        let preview = converted.preview
        return DetectedSpan(
            startUTF16: converted.startUTF16,
            endUTF16: converted.endUTF16,
            category: category,
            confidence: 0.95,
            textPreview: preview,
            replacement: category.replacementToken
        )
    }

    private static func category(for label: String) throws -> PrivacyCategory {
        switch label {
        case "private_person": return .privatePerson
        case "private_email": return .email
        case "private_phone": return .phone
        case "private_address": return .address
        case "private_url": return .url
        case "private_date": return .date
        case "account_number": return .accountNumber
        case "secret": return .secret
        default:
            throw OfficialCLIBackendError.unsupportedLabel(label)
        }
    }

    private static func utf16Range(
        in text: String,
        scalarStart: Int,
        scalarEnd: Int
    ) throws -> (startUTF16: Int, endUTF16: Int, preview: String) {
        let scalars = text.unicodeScalars
        guard let startScalarIndex = scalars.index(scalars.startIndex, offsetBy: scalarStart, limitedBy: scalars.endIndex),
              let endScalarIndex = scalars.index(scalars.startIndex, offsetBy: scalarEnd, limitedBy: scalars.endIndex),
              let startIndex = String.Index(startScalarIndex, within: text),
              let endIndex = String.Index(endScalarIndex, within: text),
              let utf16Start = startScalarIndex.samePosition(in: text.utf16),
              let utf16End = endScalarIndex.samePosition(in: text.utf16) else {
            throw OfficialCLIBackendError.invalidResponse
        }

        return (
            text.utf16.distance(from: text.utf16.startIndex, to: utf16Start),
            text.utf16.distance(from: text.utf16.startIndex, to: utf16End),
            String(text[startIndex..<endIndex].prefix(64))
        )
    }

    private static func summary(for spans: [DetectedSpan]) -> String {
        guard !spans.isEmpty else { return "No sensitive spans detected." }
        let counts = Dictionary(grouping: spans, by: \.category).mapValues(\.count)
        return counts.keys.sorted(by: { $0.rawValue < $1.rawValue }).map { category in
            "\(counts[category] ?? 0) \(category.displayName.lowercased())"
        }.joined(separator: ", ")
    }

    private static let helperScript = #"""
import json
import os
import sys
import time
from pathlib import Path

from huggingface_hub import snapshot_download
import opf

MODELS = {}


def response(ok, result=None, error=None):
    payload = {"ok": ok}
    if result is not None:
        payload["result"] = result
    if error is not None:
        payload["error"] = error
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def ensure_model(checkpoint_dir, device="cpu"):
    key = (checkpoint_dir, device)
    model = MODELS.get(key)
    if model is None:
        model = opf.OPF(model=checkpoint_dir, device=device, output_mode="typed", decode_mode="viterbi")
        MODELS[key] = model
    return model


def read_model_version(checkpoint_dir):
    config_path = Path(checkpoint_dir) / "config.json"
    if config_path.exists():
        return f"openai/privacy-filter@{config_path.stat().st_mtime_ns}"
    return "openai/privacy-filter"


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        payload = json.loads(line)
        command = payload.get("command")
        if command == "install":
            checkpoint_dir = payload["checkpoint_dir"]
            model_id = payload.get("model_id", "openai/privacy-filter")
            snapshot_download(
                repo_id=model_id,
                local_dir=checkpoint_dir,
                local_dir_use_symlinks=False,
                resume_download=True,
            )
            response(True, {"checkpoint_dir": checkpoint_dir, "model_version": read_model_version(checkpoint_dir)})
        elif command == "warm":
            checkpoint_dir = payload["checkpoint_dir"]
            device = payload.get("device", "cpu")
            ensure_model(checkpoint_dir, device=device)
            response(True, {"model_version": read_model_version(checkpoint_dir), "loaded_models": len(MODELS)})
        elif command == "scan_batch":
            checkpoint_dir = payload["checkpoint_dir"]
            device = payload.get("device", "cpu")
            items = payload.get("items", [])
            model = ensure_model(checkpoint_dir, device=device)
            results = []
            for item in items:
                started = time.perf_counter()
                result = model.redact(item["text"])
                payload_dict = result.to_dict()
                payload_dict["latency_ms"] = (time.perf_counter() - started) * 1000.0
                results.append(payload_dict)
            response(True, {"results": results, "model_version": read_model_version(checkpoint_dir)})
        elif command == "status":
            response(True, {"loaded_models": len(MODELS)})
        elif command == "shutdown":
            response(True, {"shutdown": True})
            raise SystemExit(0)
        else:
            response(False, error=f"unsupported command: {command}")
    except Exception as exc:
        response(False, error=str(exc))
"""#
}
