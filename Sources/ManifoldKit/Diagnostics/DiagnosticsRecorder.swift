// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

/// File-backed, append-only diagnostic event recorder. Lives independently of
/// the runtime SQLite store so it remains useful even when the runtime fails
/// to register — which is the priority-1 reliability problem we want to
/// observe.
///
/// On-disk layout:
///   ~/Library/Application Support/Manifold/Diagnostics/
///     ├── app-<launch-uuid>.jsonl       — per-launch app events
///     ├── agent-<launch-uuid>.jsonl     — per-launch agent events
///     └── agent-state.json              — single-writer agent liveness marker
///
/// Files are append-only line-delimited JSON. Each line is a complete
/// `DiagnosticEventRecord`. The reader concatenates files at report-build time;
/// no in-place edits, so concurrent writers across processes cannot corrupt
/// the format.
public final class DiagnosticsRecorder: @unchecked Sendable {

    public enum Process: String, Sendable {
        case app
        case agent
    }

    private static let logger = Logger(subsystem: "com.spatialduality.manifold", category: "diagnostics")

    private let directory: URL
    private let process: Process
    private let launchUUID: String
    private let queue = DispatchQueue(label: "com.spatialduality.manifold.diagnostics", qos: .utility)
    private let encoder: JSONEncoder
    private let dayFormatter: DateFormatter

    /// Caps to keep on-disk diagnostics bounded. A user who never deletes
    /// will not accumulate forever.
    public struct Limits: Sendable {
        public let maxFiles: Int
        public let maxBytesPerFile: Int

        public init(maxFiles: Int = 64, maxBytesPerFile: Int = 256_000) {
            self.maxFiles = maxFiles
            self.maxBytesPerFile = maxBytesPerFile
        }

        public static let `default` = Limits()
    }

    private let limits: Limits

    /// Default location: `~/Library/Application Support/Manifold/Diagnostics/`.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Manifold", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    public init(
        process: Process,
        directory: URL = DiagnosticsRecorder.defaultDirectory(),
        launchUUID: String = UUID().uuidString,
        limits: Limits = .default
    ) {
        self.process = process
        self.directory = directory
        self.launchUUID = launchUUID
        self.limits = limits
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.dayFormatter = DateFormatter()
        self.dayFormatter.calendar = Calendar(identifier: .gregorian)
        self.dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dayFormatter.timeZone = TimeZone(identifier: "UTC")
        self.dayFormatter.dateFormat = "yyyy-MM-dd"

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    public var currentLogFile: URL {
        directory.appendingPathComponent("\(process.rawValue)-\(launchUUID).jsonl")
    }

    public var diagnosticsDirectory: URL {
        directory
    }

    /// Record a single event. Non-blocking — serialized through an internal
    /// queue. If serialization or write fails, we log and drop (diagnostics
    /// must never break the app).
    public func record(_ event: DiagnosticEvent, on date: Date = Date()) {
        let day = dayFormatter.string(from: date)
        let record = DiagnosticEventRecord(
            day: day,
            process: process.recordProcess,
            name: event.name,
            payload: event.payload
        )
        queue.async { [weak self] in
            self?.writeRecord(record)
        }
    }

    /// Synchronous read of all records across all current diagnostics files.
    /// Used by the app-side report builder. Returns an empty array on any
    /// I/O failure — diagnostics are best-effort by design.
    public func readAllRecords() -> [DiagnosticEventRecord] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        let decoder = JSONDecoder()
        var records: [DiagnosticEventRecord] = []
        for url in contents where url.pathExtension == "jsonl" {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let lineData = line.data(using: .utf8),
                      let record = try? decoder.decode(DiagnosticEventRecord.self, from: lineData)
                else { continue }
                records.append(record)
            }
        }
        return records
    }

    /// Hard reset — used by `Delete Local Diagnostics`. Removes the entire
    /// diagnostics directory. The recorder remains usable; the next write
    /// recreates the directory.
    public func deleteAll() throws {
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Agent liveness marker

    /// On agent start, write a state marker so the next app launch can detect
    /// whether the agent crashed (file says `running`, but no agent process
    /// alive). Only the agent should call this.
    public func recordAgentBoot() {
        guard process == .agent else { return }
        writeAgentState(.init(state: .running, launchUUID: launchUUID))
    }

    /// On agent clean shutdown, mark the state as `cleanShutdown`. If the
    /// agent crashes instead, the file remains in `running` and the next app
    /// launch will record a `runtimeUnexpectedExit` event.
    public func recordAgentCleanShutdown() {
        guard process == .agent else { return }
        writeAgentState(.init(state: .cleanShutdown, launchUUID: launchUUID))
    }

    /// Read the most recent agent liveness marker. Used by the app at launch
    /// to detect a crashed previous agent run.
    public func readAgentState() -> AgentStateMarker? {
        let url = directory.appendingPathComponent("agent-state.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentStateMarker.self, from: data)
    }

    public struct AgentStateMarker: Sendable, Codable, Equatable {
        public let state: DiagnosticEvent.AgentLastState
        public let launchUUID: String

        public init(state: DiagnosticEvent.AgentLastState, launchUUID: String) {
            self.state = state
            self.launchUUID = launchUUID
        }
    }

    // MARK: - Private

    private func writeRecord(_ record: DiagnosticEventRecord) {
        let url = currentLogFile
        guard let data = try? encoder.encode(record) else {
            Self.logger.error("Failed to encode diagnostic record: \(record.name, privacy: .public)")
            return
        }

        var line = data
        line.append(0x0A) // newline

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } catch {
                Self.logger.error("Diagnostic write failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            // File doesn't exist yet — create it.
            try? line.write(to: url, options: .atomic)
        }

        enforceLimits()
    }

    private func writeAgentState(_ marker: AgentStateMarker) {
        let url = directory.appendingPathComponent("agent-state.json")
        guard let data = try? JSONEncoder().encode(marker) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func enforceLimits() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        let jsonlFiles = contents.filter { $0.pathExtension == "jsonl" }

        // Cap individual file size by rotating to a new launch UUID file. Since
        // we only ever write to currentLogFile, this means truncating it; do
        // that lazily when it crosses the threshold by writing to a sibling.
        if let attrs = try? currentLogFile.resourceValues(forKeys: [.fileSizeKey]),
           let size = attrs.fileSize, size > limits.maxBytesPerFile {
            // Move oversized current file aside; next write creates a fresh one.
            let archiveURL = directory.appendingPathComponent(
                "\(process.rawValue)-\(launchUUID)-\(Int(Date().timeIntervalSince1970)).jsonl"
            )
            try? FileManager.default.moveItem(at: currentLogFile, to: archiveURL)
        }

        // Cap total file count — drop oldest by mtime.
        if jsonlFiles.count > limits.maxFiles {
            let sorted = jsonlFiles.sorted { (a, b) -> Bool in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return aDate < bDate
            }
            let toDelete = sorted.prefix(jsonlFiles.count - limits.maxFiles)
            for url in toDelete {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

private extension DiagnosticsRecorder.Process {
    var recordProcess: DiagnosticEventRecord.Process {
        switch self {
        case .app: return .app
        case .agent: return .agent
        }
    }
}
