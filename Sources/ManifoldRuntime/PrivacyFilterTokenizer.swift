// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct TokenOffset: Codable, Equatable, Sendable {
    let start: Int
    let end: Int
}

struct PrivacyFilterEncoding: Equatable, Sendable {
    let inputIDs: [Int]
    let attentionMask: [Int]
    let offsets: [TokenOffset]
}

enum PrivacyFilterTokenizerError: Error, Equatable {
    case invalidTokenizerJSON
    case invalidRegex(String)
    case missingToken(String)
    case invalidMaxLength
}

final class PrivacyFilterBPETokenizer: @unchecked Sendable {
    private let vocab: [String: Int]
    private let mergeRanks: [Pair: Int]
    private let splitRegex: NSRegularExpression
    private let byteEncoder: [String]
    let padTokenID: Int

    init(tokenizerJSONURL: URL) throws {
        let data = try Data(contentsOf: tokenizerJSONURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let model = root?["model"] as? [String: Any],
            let rawVocab = model["vocab"] as? [String: Any],
            let rawMerges = model["merges"] as? [Any],
            let preTokenizer = root?["pre_tokenizer"] as? [String: Any]
        else {
            throw PrivacyFilterTokenizerError.invalidTokenizerJSON
        }

        vocab = try Self.parseVocab(rawVocab)
        mergeRanks = try Self.parseMergeRanks(rawMerges)
        padTokenID = Self.parsePadTokenID(root: root) ?? 199_999
        byteEncoder = Self.makeByteEncoder()

        let pattern = try Self.parseSplitPattern(preTokenizer)
        do {
            splitRegex = try NSRegularExpression(pattern: pattern)
        } catch {
            throw PrivacyFilterTokenizerError.invalidRegex(pattern)
        }
    }

    func encode(
        _ text: String,
        maxLength: Int? = nil,
        padding: Bool = false,
        truncation: Bool = true
    ) throws -> PrivacyFilterEncoding {
        if let maxLength, maxLength < 0 {
            throw PrivacyFilterTokenizerError.invalidMaxLength
        }

        var inputIDs: [Int] = []
        var offsets: [TokenOffset] = []
        for segment in pretokenize(text) {
            let pieces = try bytePairEncode(segment)
            inputIDs.append(contentsOf: pieces.map(\.id))
            offsets.append(contentsOf: pieces.map(\.offset))
        }

        if let maxLength, inputIDs.count > maxLength {
            guard truncation else {
                throw PrivacyFilterTokenizerError.invalidMaxLength
            }
            inputIDs = Array(inputIDs.prefix(maxLength))
            offsets = Array(offsets.prefix(maxLength))
        }

        var attentionMask = Array(repeating: 1, count: inputIDs.count)
        if padding, let maxLength {
            while inputIDs.count < maxLength {
                inputIDs.append(padTokenID)
                attentionMask.append(0)
                offsets.append(TokenOffset(start: 0, end: 0))
            }
        }

        return PrivacyFilterEncoding(
            inputIDs: inputIDs,
            attentionMask: attentionMask,
            offsets: offsets
        )
    }

    private func pretokenize(_ text: String) -> [PretokenizedSegment] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = splitRegex.matches(in: text, range: fullRange)
        var segments: [PretokenizedSegment] = []
        var previousEnd = text.startIndex

        for match in matches {
            guard let range = Range(match.range, in: text) else {
                continue
            }
            if previousEnd < range.lowerBound {
                segments.append(makeSegment(text: text, range: previousEnd..<range.lowerBound))
            }
            segments.append(makeSegment(text: text, range: range))
            previousEnd = range.upperBound
        }

        if previousEnd < text.endIndex {
            segments.append(makeSegment(text: text, range: previousEnd..<text.endIndex))
        }
        return segments.filter { !$0.text.isEmpty }
    }

    private func makeSegment(text: String, range: Range<String.Index>) -> PretokenizedSegment {
        PretokenizedSegment(
            text: String(text[range]),
            scalarStart: scalarOffset(in: text, at: range.lowerBound)
        )
    }

    private func bytePairEncode(_ segment: PretokenizedSegment) throws -> [EncodedPiece] {
        var symbols = byteLevelSymbols(for: segment)
        if symbols.isEmpty {
            return []
        }

        while let best = bestMerge(in: symbols) {
            var merged: [BPESymbol] = []
            var index = 0
            while index < symbols.count {
                if index < symbols.count - 1 {
                    let pair = Pair(left: symbols[index].text, right: symbols[index + 1].text)
                    if pair == best {
                        merged.append(
                            BPESymbol(
                                text: symbols[index].text + symbols[index + 1].text,
                                offset: TokenOffset(
                                    start: symbols[index].offset.start,
                                    end: symbols[index + 1].offset.end
                                )
                            )
                        )
                        index += 2
                        continue
                    }
                }
                merged.append(symbols[index])
                index += 1
            }
            symbols = merged
        }

        return try symbols.map { symbol in
            guard let id = vocab[symbol.text] else {
                throw PrivacyFilterTokenizerError.missingToken(symbol.text)
            }
            return EncodedPiece(id: id, offset: symbol.offset)
        }
    }

    private func byteLevelSymbols(for segment: PretokenizedSegment) -> [BPESymbol] {
        var symbols: [BPESymbol] = []
        var scalarOffset = segment.scalarStart
        for scalar in segment.text.unicodeScalars {
            for byte in String(scalar).utf8 {
                symbols.append(
                    BPESymbol(
                        text: byteEncoder[Int(byte)],
                        offset: TokenOffset(start: scalarOffset, end: scalarOffset + 1)
                    )
                )
            }
            scalarOffset += 1
        }
        return symbols
    }

    private func bestMerge(in symbols: [BPESymbol]) -> Pair? {
        guard symbols.count > 1 else {
            return nil
        }
        var selected: Pair?
        var selectedRank = Int.max
        for index in 0..<(symbols.count - 1) {
            let pair = Pair(left: symbols[index].text, right: symbols[index + 1].text)
            guard let rank = mergeRanks[pair], rank < selectedRank else {
                continue
            }
            selected = pair
            selectedRank = rank
        }
        return selected
    }

    private func scalarOffset(in text: String, at index: String.Index) -> Int {
        guard let scalarIndex = index.samePosition(in: text.unicodeScalars) else {
            return text.distance(from: text.startIndex, to: index)
        }
        return text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: scalarIndex)
    }

    private static func parseVocab(_ rawVocab: [String: Any]) throws -> [String: Int] {
        var vocab: [String: Int] = [:]
        vocab.reserveCapacity(rawVocab.count)
        for (token, rawID) in rawVocab {
            if let id = rawID as? Int {
                vocab[token] = id
            } else if let number = rawID as? NSNumber {
                vocab[token] = number.intValue
            } else {
                throw PrivacyFilterTokenizerError.invalidTokenizerJSON
            }
        }
        return vocab
    }

    private static func parseMergeRanks(_ rawMerges: [Any]) throws -> [Pair: Int] {
        var ranks: [Pair: Int] = [:]
        ranks.reserveCapacity(rawMerges.count)
        for (rank, rawMerge) in rawMerges.enumerated() {
            if let pair = rawMerge as? [String], pair.count == 2 {
                ranks[Pair(left: pair[0], right: pair[1])] = rank
            } else if let merge = rawMerge as? String {
                let pieces = merge.split(separator: " ", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else {
                    throw PrivacyFilterTokenizerError.invalidTokenizerJSON
                }
                ranks[Pair(left: pieces[0], right: pieces[1])] = rank
            } else {
                throw PrivacyFilterTokenizerError.invalidTokenizerJSON
            }
        }
        return ranks
    }

    private static func parsePadTokenID(root: [String: Any]?) -> Int? {
        guard let addedTokens = root?["added_tokens"] as? [[String: Any]] else {
            return nil
        }
        let rawID = addedTokens.first { token in
            token["content"] as? String == "<|endoftext|>"
        }?["id"]
        if let id = rawID as? Int {
            return id
        }
        return (rawID as? NSNumber)?.intValue
    }

    private static func parseSplitPattern(_ preTokenizer: [String: Any]) throws -> String {
        guard
            let pretokenizers = preTokenizer["pretokenizers"] as? [[String: Any]],
            let split = pretokenizers.first(where: { $0["type"] as? String == "Split" }),
            let pattern = split["pattern"] as? [String: Any],
            let regex = pattern["Regex"] as? String
        else {
            throw PrivacyFilterTokenizerError.invalidTokenizerJSON
        }
        return regex
    }

    private static func makeByteEncoder() -> [String] {
        var bytes = Array(33...126) + Array(161...172) + Array(174...255)
        var codePoints = bytes
        var next = 0
        for byte in 0...255 where !bytes.contains(byte) {
            bytes.append(byte)
            codePoints.append(256 + next)
            next += 1
        }

        var encoder = Array(repeating: "", count: 256)
        for (byte, codePoint) in zip(bytes, codePoints) {
            encoder[byte] = String(UnicodeScalar(codePoint)!)
        }
        return encoder
    }
}

private struct PretokenizedSegment {
    let text: String
    let scalarStart: Int
}

private struct BPESymbol {
    let text: String
    let offset: TokenOffset
}

private struct EncodedPiece {
    let id: Int
    let offset: TokenOffset
}

private struct Pair: Hashable {
    let left: String
    let right: String
}
