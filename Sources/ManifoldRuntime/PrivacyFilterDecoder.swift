// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

enum PrivacyFilterDecoderError: Error, LocalizedError {
    case invalidConfig(String)
    case invalidLogits(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfig(let message):
            return "Invalid Privacy Filter config: \(message)"
        case .invalidLogits(let message):
            return "Invalid Privacy Filter logits: \(message)"
        }
    }
}

struct PrivacyFilterDecoder: Sendable {
    let id2Label: [Int: String]
    let slidingWindow: Int
    private let operatingPointBiases: [String: TransitionBiases]

    init(configURL: URL, calibrationURL: URL?) throws {
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
        guard let rawLabels = config?["id2label"] as? [String: Any] else {
            throw PrivacyFilterDecoderError.invalidConfig("Missing id2label")
        }

        var labels: [Int: String] = [:]
        labels.reserveCapacity(rawLabels.count)
        for (rawID, rawLabel) in rawLabels {
            guard let id = Int(rawID), let label = rawLabel as? String else {
                throw PrivacyFilterDecoderError.invalidConfig("Invalid id2label entry")
            }
            labels[id] = label
        }
        guard labels[0] == "O", !labels.isEmpty else {
            throw PrivacyFilterDecoderError.invalidConfig("Missing background label")
        }
        id2Label = labels

        if let sliding = config?["sliding_window"] as? Int {
            slidingWindow = sliding
        } else if let number = config?["sliding_window"] as? NSNumber {
            slidingWindow = number.intValue
        } else {
            slidingWindow = 128
        }

        operatingPointBiases = try Self.loadBiases(calibrationURL)
    }

    func constrainedViterbi(logits: [[Float]], operatingPoint: String) throws -> [Int] {
        guard let first = logits.first else {
            return []
        }
        let tokenCount = logits.count
        let labelCount = first.count
        guard id2Label.count == labelCount else {
            throw PrivacyFilterDecoderError.invalidLogits(
                "id2label has \(id2Label.count) labels but logits have \(labelCount)"
            )
        }
        guard logits.allSatisfy({ $0.count == labelCount }) else {
            throw PrivacyFilterDecoderError.invalidLogits("Ragged logits")
        }

        let biases = operatingPointBiases[operatingPoint]
            ?? operatingPointBiases["default"]
            ?? .default
        let transition = transitionMatrix(labelCount: labelCount, biases: biases)
        let impossible = Float(-1.0e9)
        var dp = Array(
            repeating: Array(repeating: impossible, count: labelCount),
            count: tokenCount
        )
        var backpointers = Array(
            repeating: Array(repeating: 0, count: labelCount),
            count: tokenCount
        )

        for labelIndex in 0..<labelCount {
            if allowedStart(id2Label[labelIndex] ?? "O") {
                dp[0][labelIndex] = logits[0][labelIndex]
            }
        }

        if tokenCount > 1 {
            for tokenIndex in 1..<tokenCount {
                for current in 0..<labelCount {
                    var bestScore = impossible
                    var bestPrevious = 0
                    for previous in 0..<labelCount {
                        let score = dp[tokenIndex - 1][previous] + transition[previous][current]
                        if score > bestScore {
                            bestScore = score
                            bestPrevious = previous
                        }
                    }
                    backpointers[tokenIndex][current] = bestPrevious
                    dp[tokenIndex][current] = logits[tokenIndex][current] + bestScore
                }
            }
        }

        var bestLast = 0
        var bestFinal = impossible
        for labelIndex in 0..<labelCount {
            let score = dp[tokenCount - 1][labelIndex]
                + (allowedEnd(id2Label[labelIndex] ?? "O") ? 0 : impossible)
            if score > bestFinal {
                bestFinal = score
                bestLast = labelIndex
            }
        }

        var path = Array(repeating: 0, count: tokenCount)
        path[tokenCount - 1] = bestLast
        if tokenCount > 1 {
            for tokenIndex in stride(from: tokenCount - 1, through: 1, by: -1) {
                path[tokenIndex - 1] = backpointers[tokenIndex][path[tokenIndex]]
            }
        }
        return path
    }

    func decodeSpans(
        predictions: [Int],
        offsets: [TokenOffset],
        text: String,
        allowedCategories: Set<PrivacyCategory>
    ) -> [DetectedSpan] {
        var spans: [DecodedTokenSpan] = []
        var activeCategory: String?
        var activeStart: Int?

        func close(_ endTokenExclusive: Int) {
            guard let category = activeCategory, let start = activeStart else {
                return
            }
            spans.append(DecodedTokenSpan(label: category, tokenStart: start, tokenEnd: endTokenExclusive))
            activeCategory = nil
            activeStart = nil
        }

        for (index, prediction) in predictions.enumerated() {
            let label = id2Label[prediction] ?? "O"
            let split = Self.splitLabel(label)
            switch split.tag {
            case "O":
                close(index)
            case "S":
                close(index)
                if let category = split.category {
                    spans.append(DecodedTokenSpan(label: category, tokenStart: index, tokenEnd: index + 1))
                }
            case "B":
                close(index)
                activeCategory = split.category
                activeStart = index
            case "I", "E":
                if activeCategory != split.category {
                    close(index)
                    activeCategory = split.category
                    activeStart = index
                }
                if split.tag == "E" {
                    close(index + 1)
                }
            default:
                close(index)
            }
        }
        close(predictions.count)

        let detected = spans.compactMap { span -> DetectedSpan? in
            guard let category = Self.privacyCategory(for: span.label),
                  allowedCategories.contains(category) else {
                return nil
            }
            let usableOffsets = offsets[safe: span.tokenStart..<span.tokenEnd]
                .filter { $0.end > $0.start }
            guard let first = usableOffsets.first, let last = usableOffsets.last else {
                return nil
            }
            let startUTF16 = Self.utf16Offset(in: text, scalarOffset: first.start)
            let endUTF16 = Self.utf16Offset(in: text, scalarOffset: last.end)
            guard endUTF16 > startUTF16 else {
                return nil
            }
            let preview = Self.preview(text: text, startUTF16: startUTF16, endUTF16: endUTF16)
            return DetectedSpan(
                startUTF16: startUTF16,
                endUTF16: endUTF16,
                category: category,
                confidence: 0.95,
                textPreview: preview,
                replacement: category.replacementToken
            )
        }
        return Self.merge(detected)
    }

    func redactedText(_ text: String, spans: [DetectedSpan]) -> String {
        Self.redact(text: text, using: spans)
    }

    func findingsSummary(for spans: [DetectedSpan]) -> String {
        Self.summary(for: spans)
    }

    private func transitionMatrix(labelCount: Int, biases: TransitionBiases) -> [[Float]] {
        let impossible = Float(-1.0e9)
        var matrix = Array(
            repeating: Array(repeating: impossible, count: labelCount),
            count: labelCount
        )
        for previous in 0..<labelCount {
            for current in 0..<labelCount {
                let previousLabel = id2Label[previous] ?? "O"
                let currentLabel = id2Label[current] ?? "O"
                if Self.allowedTransition(previous: previousLabel, current: currentLabel) {
                    matrix[previous][current] = Self.transitionBias(
                        previous: previousLabel,
                        current: currentLabel,
                        biases: biases
                    )
                }
            }
        }
        return matrix
    }

    private func allowedStart(_ label: String) -> Bool {
        ["O", "B", "S"].contains(Self.splitLabel(label).tag)
    }

    private func allowedEnd(_ label: String) -> Bool {
        ["O", "E", "S"].contains(Self.splitLabel(label).tag)
    }

    private static func allowedTransition(previous: String, current: String) -> Bool {
        let previousSplit = splitLabel(previous)
        let currentSplit = splitLabel(current)

        switch previousSplit.tag {
        case "O":
            return ["O", "B", "S"].contains(currentSplit.tag)
        case "B", "I":
            return currentSplit.category == previousSplit.category
                && ["I", "E"].contains(currentSplit.tag)
        case "E", "S":
            return ["O", "B", "S"].contains(currentSplit.tag)
        default:
            return false
        }
    }

    private static func transitionBias(
        previous: String,
        current: String,
        biases: TransitionBiases
    ) -> Float {
        let previousTag = splitLabel(previous).tag
        let currentTag = splitLabel(current).tag

        if previousTag == "O", currentTag == "O" {
            return biases.backgroundStay
        }
        if previousTag == "O", ["B", "S"].contains(currentTag) {
            return biases.backgroundToStart
        }
        if ["B", "I"].contains(previousTag), currentTag == "I" {
            return biases.insideToContinue
        }
        if ["B", "I"].contains(previousTag), currentTag == "E" {
            return biases.insideToEnd
        }
        if ["E", "S"].contains(previousTag), currentTag == "O" {
            return biases.endToBackground
        }
        if ["E", "S"].contains(previousTag), ["B", "S"].contains(currentTag) {
            return biases.endToStart
        }
        return 0
    }

    private static func splitLabel(_ label: String) -> (tag: String, category: String?) {
        if label == "O" {
            return ("O", nil)
        }
        let pieces = label.split(separator: "-", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else {
            return ("O", nil)
        }
        return (pieces[0], pieces[1])
    }

    private static func privacyCategory(for label: String) -> PrivacyCategory? {
        switch label {
        case "account_number": return .accountNumber
        case "private_address": return .address
        case "private_date": return .date
        case "private_email": return .email
        case "private_person": return .privatePerson
        case "private_phone": return .phone
        case "private_url": return .url
        case "secret": return .secret
        default: return nil
        }
    }

    private static func utf16Offset(in text: String, scalarOffset: Int) -> Int {
        let clamped = max(0, min(scalarOffset, text.unicodeScalars.count))
        let scalarIndex = text.unicodeScalars.index(
            text.unicodeScalars.startIndex,
            offsetBy: clamped
        )
        guard let stringIndex = String.Index(scalarIndex, within: text) else {
            return text.utf16.count
        }
        return stringIndex.utf16Offset(in: text)
    }

    private static func preview(text: String, startUTF16: Int, endUTF16: Int) -> String {
        let start = String.Index(utf16Offset: startUTF16, in: text)
        let end = String.Index(utf16Offset: endUTF16, in: text)
        return String(text[start..<end].prefix(48))
    }

    private static func merge(_ spans: [DetectedSpan]) -> [DetectedSpan] {
        let sorted = spans.sorted {
            if $0.startUTF16 != $1.startUTF16 { return $0.startUTF16 < $1.startUTF16 }
            return $0.endUTF16 < $1.endUTF16
        }
        guard var current = sorted.first else { return [] }
        var merged: [DetectedSpan] = []

        for span in sorted.dropFirst() {
            if span.startUTF16 <= current.endUTF16 {
                let preferredCategory: PrivacyCategory
                if current.category == .secret || span.category == .secret {
                    preferredCategory = .secret
                } else if current.confidence >= span.confidence {
                    preferredCategory = current.category
                } else {
                    preferredCategory = span.category
                }
                current = DetectedSpan(
                    startUTF16: min(current.startUTF16, span.startUTF16),
                    endUTF16: max(current.endUTF16, span.endUTF16),
                    category: preferredCategory,
                    confidence: max(current.confidence, span.confidence),
                    textPreview: current.textPreview,
                    replacement: preferredCategory.replacementToken
                )
            } else {
                merged.append(current)
                current = span
            }
        }
        merged.append(current)
        return merged
    }

    private static func redact(text: String, using spans: [DetectedSpan]) -> String {
        var output = text
        for span in spans.sorted(by: { $0.startUTF16 > $1.startUTF16 }) {
            let start = String.Index(utf16Offset: span.startUTF16, in: output)
            let end = String.Index(utf16Offset: span.endUTF16, in: output)
            output.replaceSubrange(start..<end, with: span.replacement)
        }
        return output
    }

    private static func summary(for spans: [DetectedSpan]) -> String {
        guard !spans.isEmpty else { return "No sensitive spans detected." }
        let counts = Dictionary(grouping: spans, by: \.category).mapValues(\.count)
        return counts.keys.sorted(by: { $0.rawValue < $1.rawValue }).map { category in
            let count = counts[category] ?? 0
            let label = category.displayName.lowercased()
            return "\(count) \(label)"
        }.joined(separator: ", ")
    }

    private static func loadBiases(_ calibrationURL: URL?) throws -> [String: TransitionBiases] {
        guard let calibrationURL else {
            return ["default": .default]
        }
        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: calibrationURL)) as? [String: Any]
        let points = payload?["operating_points"] as? [String: Any] ?? [:]
        var result: [String: TransitionBiases] = [:]
        for (name, rawPoint) in points {
            let point = rawPoint as? [String: Any]
            let biases = point?["biases"] as? [String: Any] ?? [:]
            result[name] = TransitionBiases(raw: biases)
        }
        if result["default"] == nil {
            result["default"] = .default
        }
        return result
    }
}

private struct DecodedTokenSpan {
    let label: String
    let tokenStart: Int
    let tokenEnd: Int
}

private struct TransitionBiases: Sendable {
    let backgroundStay: Float
    let backgroundToStart: Float
    let endToBackground: Float
    let endToStart: Float
    let insideToContinue: Float
    let insideToEnd: Float

    static let `default` = TransitionBiases(raw: [:])

    init(raw: [String: Any]) {
        backgroundStay = Self.float(raw["transition_bias_background_stay"])
        backgroundToStart = Self.float(raw["transition_bias_background_to_start"])
        endToBackground = Self.float(raw["transition_bias_end_to_background"])
        endToStart = Self.float(raw["transition_bias_end_to_start"])
        insideToContinue = Self.float(raw["transition_bias_inside_to_continue"])
        insideToEnd = Self.float(raw["transition_bias_inside_to_end"])
    }

    private static func float(_ value: Any?) -> Float {
        if let value = value as? Float {
            return value
        }
        if let value = value as? Double {
            return Float(value)
        }
        if let value = value as? NSNumber {
            return value.floatValue
        }
        return 0
    }
}

private extension Array {
    subscript(safe range: Range<Int>) -> [Element] {
        let lower = Swift.max(0, Swift.min(count, range.lowerBound))
        let upper = Swift.max(lower, Swift.min(count, range.upperBound))
        return Array(self[lower..<upper])
    }
}
