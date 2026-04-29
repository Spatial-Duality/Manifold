// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import MLX

actor MLXPrivacyBackend: PrivacyBackend {
    let kind: PrivacyBackendKind = .mlx

    private let runtimeManager: PrivacyRuntimeManager
    private var loadedRuntime: LoadedMLXPrivacyRuntime?
    private var loadedVersion: String?

    init(runtimeManager: PrivacyRuntimeManager) {
        self.runtimeManager = runtimeManager
    }

    func install() async throws -> PrivacyModelInfo {
        let installed = try await runtimeManager.install(runtimeID: PrivacyRuntimeManager.mlxRuntimeID)
        await unload()
        loadedVersion = installed?.manifest.version
        return await modelInfo()
    }

    func uninstall() async throws {
        await unload()
        try await runtimeManager.uninstall(runtimeID: PrivacyRuntimeManager.mlxRuntimeID)
        loadedVersion = nil
    }

    func load() async throws {
        guard PrivacyRuntimeHardware.supportsMLX else {
            throw PrivacyBackendError.unavailable(kind, "Privacy Preflight requires Apple Silicon.")
        }
        guard let runtime = try await runtimeManager.installedRuntime() else {
            throw PrivacyBackendError.unavailable(kind, "MLX MXFP8 model pack is not installed.")
        }
        guard runtime.isRunnable else {
            throw PrivacyBackendError.unavailable(kind, "Installed model pack is missing required MLX/tokenizer/decoder files.")
        }
        if loadedRuntime != nil, loadedVersion == runtime.manifest.version {
            return
        }

        let tokenizer = try PrivacyFilterBPETokenizer(tokenizerJSONURL: runtime.tokenizerURL)
        let decoder = try PrivacyFilterDecoder(
            configURL: runtime.configURL,
            calibrationURL: runtime.viterbiCalibrationURL
        )
        let model = try MLXOpenAIPrivacyFilter(
            modelURL: runtime.modelURL,
            configURL: runtime.configURL
        )
        loadedRuntime = LoadedMLXPrivacyRuntime(
            model: model,
            tokenizer: tokenizer,
            decoder: decoder,
            version: runtime.manifest.version
        )
        loadedVersion = runtime.manifest.version
    }

    func unload() async {
        loadedRuntime = nil
    }

    func modelInfo() async -> PrivacyModelInfo {
        guard PrivacyRuntimeHardware.supportsMLX else {
            return PrivacyModelInfo(
                modelVersion: "unavailable",
                available: false,
                loaded: false,
                note: "Privacy Preflight requires Apple Silicon."
            )
        }
        do {
            guard let runtime = try await runtimeManager.installedRuntime() else {
                return PrivacyModelInfo(
                    modelVersion: "not-installed",
                    available: false,
                    loaded: false,
                    note: "Download the MLX MXFP8 model pack to enable model-backed scans."
                )
            }
            return PrivacyModelInfo(
                modelVersion: runtime.manifest.version,
                available: runtime.isRunnable,
                loaded: loadedRuntime != nil && loadedVersion == runtime.manifest.version,
                note: runtime.isRunnable
                    ? "Verified MLX MXFP8 model pack is installed."
                    : "Installed model pack is incomplete."
            )
        } catch {
            return PrivacyModelInfo(
                modelVersion: loadedVersion ?? "verification-failed",
                available: false,
                loaded: false,
                note: error.localizedDescription
            )
        }
    }

    func scan(_ request: PrivacyScanRequest) async throws -> PrivacyScanResult {
        let started = Date()
        try await load()
        guard let runtime = loadedRuntime else {
            throw PrivacyBackendError.unavailable(kind, "MLX runtime failed to load.")
        }

        let encoding = try runtime.tokenizer.encode(
            request.text,
            maxLength: nil,
            padding: false,
            truncation: true
        )
        guard !encoding.inputIDs.isEmpty else {
            return PrivacyScanResult(
                spans: [],
                redactedText: request.text,
                findingsSummary: runtime.decoder.findingsSummary(for: []),
                backend: kind,
                modelVersion: runtime.version,
                elapsedMs: Int(Date().timeIntervalSince(started) * 1_000),
                cacheHit: false
            )
        }

        var spans: [DetectedSpan] = []
        let chunkStarts = Self.chunkStarts(
            tokenCount: encoding.inputIDs.count,
            sequenceLength: runtime.model.sequenceLength
        )
        let allowedCategories = Set(request.categories)
        for chunkStart in chunkStarts {
            let chunk = Self.makeChunk(
                encoding: encoding,
                start: chunkStart,
                sequenceLength: runtime.model.sequenceLength
            )
            let logits = try runtime.model.predictLogits(
                inputIDs: chunk.inputIDs,
                attentionMask: chunk.attentionMask
            )
            let validLogits = Array(logits.prefix(chunk.validLength))
            let predictions = try runtime.decoder.constrainedViterbi(
                logits: validLogits,
                operatingPoint: request.operatingPoint
            )
            spans += runtime.decoder.decodeSpans(
                predictions: predictions,
                offsets: Array(chunk.offsets.prefix(chunk.validLength)),
                text: request.text,
                allowedCategories: allowedCategories
            )
        }

        let finalSpans = Self.merge(spans)
        let redacted = runtime.decoder.redactedText(request.text, spans: finalSpans)
        return PrivacyScanResult(
            spans: finalSpans,
            redactedText: redacted,
            findingsSummary: runtime.decoder.findingsSummary(for: finalSpans),
            backend: kind,
            modelVersion: runtime.version,
            elapsedMs: Int(Date().timeIntervalSince(started) * 1_000),
            cacheHit: false
        )
    }

    private static func chunkStarts(tokenCount: Int, sequenceLength: Int) -> [Int] {
        guard tokenCount > sequenceLength else { return [0] }
        let overlap = max(0, min(16, sequenceLength / 4))
        let step = max(1, sequenceLength - overlap)
        var starts: [Int] = []
        var start = 0
        while start < tokenCount {
            starts.append(start)
            if start + sequenceLength >= tokenCount {
                break
            }
            start += step
        }
        return starts
    }

    private static func makeChunk(
        encoding: PrivacyFilterEncoding,
        start: Int,
        sequenceLength: Int
    ) -> MLXPrivacyChunk {
        let end = min(encoding.inputIDs.count, start + sequenceLength)
        let validLength = max(0, end - start)
        let inputIDs = Array(encoding.inputIDs[start..<end])
        let attentionMask = Array(repeating: 1, count: validLength)
        let offsets = Array(encoding.offsets[start..<end])
        return MLXPrivacyChunk(
            inputIDs: inputIDs,
            attentionMask: attentionMask,
            offsets: offsets,
            validLength: validLength
        )
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
}

private struct MLXPrivacyChunk {
    let inputIDs: [Int]
    let attentionMask: [Int]
    let offsets: [TokenOffset]
    let validLength: Int
}

private final class LoadedMLXPrivacyRuntime {
    let model: MLXOpenAIPrivacyFilter
    let tokenizer: PrivacyFilterBPETokenizer
    let decoder: PrivacyFilterDecoder
    let version: String

    init(
        model: MLXOpenAIPrivacyFilter,
        tokenizer: PrivacyFilterBPETokenizer,
        decoder: PrivacyFilterDecoder,
        version: String
    ) {
        self.model = model
        self.tokenizer = tokenizer
        self.decoder = decoder
        self.version = version
    }
}

private enum MLXPrivacyModelError: Error, LocalizedError {
    case missingTensor(String)
    case invalidConfig(String)
    case invalidLogits([Int])

    var errorDescription: String? {
        switch self {
        case .missingTensor(let key):
            return "MLX Privacy Filter tensor is missing: \(key)"
        case .invalidConfig(let message):
            return "Invalid MLX Privacy Filter config: \(message)"
        case .invalidLogits(let shape):
            return "MLX Privacy Filter logits have invalid shape \(shape)"
        }
    }
}

private final class MLXOpenAIPrivacyFilter {
    let sequenceLength: Int

    private let config: MLXPrivacyConfig
    private let weights: [String: MLXArray]
    private let invFrequency: MLXArray
    private let ropeAttentionScaling: Float
    private let quantizationMode: QuantizationMode

    init(modelURL: URL, configURL: URL) throws {
        config = try JSONDecoder().decode(MLXPrivacyConfig.self, from: Data(contentsOf: configURL))
        guard config.modelType == "openai_privacy_filter" else {
            throw MLXPrivacyModelError.invalidConfig("Expected openai_privacy_filter, got \(config.modelType)")
        }
        guard config.quantization.mode == "mxfp8" else {
            throw MLXPrivacyModelError.invalidConfig("Expected MXFP8 quantization, got \(config.quantization.mode)")
        }
        try Self.validate(config)
        quantizationMode = .mxfp8
        weights = try loadArrays(url: modelURL)
        sequenceLength = min(
            config.maxPositionEmbeddings,
            max(1, config.defaultContextLength ?? 4_096),
            4_096
        )
        let rope = Self.makeInvFrequency(config: config)
        invFrequency = rope.invFrequency
        ropeAttentionScaling = rope.attentionScaling
        try validateRequiredTensors()
    }

    func predictLogits(inputIDs: [Int], attentionMask: [Int]) throws -> [[Float]] {
        let batch = 1
        let length = inputIDs.count
        let input = MLXArray(inputIDs, [batch, length])
        let mask = MLXArray(attentionMask, [batch, length])

        var hidden = try embedding(input)
        let attentionMask = makeBidirectionalSlidingWindowMask(length: length, attentionMask: mask)
        for layer in 0..<config.numHiddenLayers {
            hidden = try encoderLayer(layer, hidden, attentionMask: attentionMask)
        }
        hidden = try rmsNorm(hidden, key: "model.norm.weight")
        let logits = try quantizedLinear("score", hidden)
        let rows = logits[0].asArray(Float.self)
        let shape = logits.shape
        guard shape.count == 3, shape[0] == 1, shape[1] == length, shape[2] > 0 else {
            throw MLXPrivacyModelError.invalidLogits(shape)
        }
        let labelCount = shape[2]
        return stride(from: 0, to: rows.count, by: labelCount).map { offset in
            Array(rows[offset..<(offset + labelCount)])
        }
    }

    private func encoderLayer(_ index: Int, _ hidden: MLXArray, attentionMask: MLXArray?) throws -> MLXArray {
        let prefix = "model.layers.\(index)"
        var x = try rmsNorm(hidden, key: "\(prefix).input_layernorm.weight")
        x = hidden + (try attention(prefix: "\(prefix).self_attn", x: x, mask: attentionMask))
        let residual = x
        x = try rmsNorm(x, key: "\(prefix).post_attention_layernorm.weight")
        return residual + (try mlp(prefix: "\(prefix).mlp", x: x))
    }

    private func attention(prefix: String, x: MLXArray, mask: MLXArray?) throws -> MLXArray {
        let batch = x.shape[0]
        let length = x.shape[1]
        var query = try quantizedLinear("\(prefix).q_proj", x)
            .reshaped(batch, length, config.numAttentionHeads, config.headDim)
            .swappedAxes(1, 2)
        var key = try quantizedLinear("\(prefix).k_proj", x)
            .reshaped(batch, length, config.numKeyValueHeads, config.headDim)
            .swappedAxes(1, 2)
        let value = try quantizedLinear("\(prefix).v_proj", x)
            .reshaped(batch, length, config.numKeyValueHeads, config.headDim)
            .swappedAxes(1, 2)

        query = applyRoPE(query)
        key = applyRoPE(key)
        let output = MLXFast.scaledDotProductAttention(
            queries: query,
            keys: key,
            values: value,
            scale: 1 / sqrt(Float(config.headDim)),
            mask: mask,
            sinks: try tensor("\(prefix).sinks")
        )
        let merged = output.swappedAxes(1, 2)
            .reshaped(batch, length, config.numAttentionHeads * config.headDim)
        return try quantizedLinear("\(prefix).o_proj", merged)
    }

    private func mlp(prefix: String, x: MLXArray) throws -> MLXArray {
        let routerLogits = try quantizedLinear("\(prefix).router", x.asType(.float32))
        let indices = argPartition(routerLogits, kth: -config.numExpertsPerToken, axis: -1)[
            .ellipsis,
            (-config.numExpertsPerToken)...
        ]
        let expertLogits = takeAlong(routerLogits, indices, axis: -1)
        let expertWeights = softmax(expertLogits, axis: -1, precise: true) / Float(config.numExpertsPerToken)
        let expertOutput = try switchGLU(prefix: "\(prefix).experts", x: x, indices: indices)
        let weighted = expertOutput * expertWeights.expandedDimensions(axis: -1)
        return sum(weighted, axis: -2) * Float(config.numExpertsPerToken)
    }

    private func switchGLU(prefix: String, x: MLXArray, indices: MLXArray) throws -> MLXArray {
        let expanded = expandedDimensions(x, axes: [-2, -3])
        let up = try switchLinear("\(prefix).up_proj", x: expanded, indices: indices)
        let gate = try switchLinear("\(prefix).gate_proj", x: expanded, indices: indices)
        let activated = gptOssSwiGLU(xLinear: up, xGlu: gate)
        return try switchLinear("\(prefix).down_proj", x: activated, indices: indices)
            .squeezed(axis: -2)
    }

    private func gptOssSwiGLU(xLinear: MLXArray, xGlu: MLXArray) -> MLXArray {
        let limit = Float(7)
        let alpha = Float(1.702)
        let clippedGlu = clip(xGlu, max: limit)
        let clippedLinear = clip(xLinear, min: -limit, max: limit)
        return (clippedGlu * sigmoid(clippedGlu * alpha)) * (clippedLinear + Float(1))
    }

    private func embedding(_ inputIDs: MLXArray) throws -> MLXArray {
        let weight = try tensor("model.embed_tokens.weight")
        guard let scales = weights["model.embed_tokens.scales"] else {
            return weight[inputIDs]
        }
        let shape = inputIDs.shape
        let flatIDs = inputIDs.flattened()
        let out = dequantized(
            weight[flatIDs],
            scales: scales[flatIDs],
            biases: nil,
            groupSize: config.quantization.groupSize,
            bits: config.quantization.bits,
            mode: quantizationMode,
            dtype: .float16
        )
        return out.reshaped(shape + [config.hiddenSize])
    }

    private func quantizedLinear(_ prefix: String, _ x: MLXArray) throws -> MLXArray {
        let weight = try tensor("\(prefix).weight")
        var output: MLXArray
        if let scales = weights["\(prefix).scales"] {
            output = quantizedMM(
                x,
                weight,
                scales: scales,
                biases: nil,
                transpose: true,
                groupSize: config.quantization.groupSize,
                bits: config.quantization.bits,
                mode: quantizationMode
            )
        } else {
            output = matmul(x, weight.transposed())
        }
        if let bias = weights["\(prefix).bias"] {
            output = output + bias
        }
        return output
    }

    private func switchLinear(_ prefix: String, x: MLXArray, indices: MLXArray) throws -> MLXArray {
        let output = gatherQuantizedMM(
            x,
            try tensor("\(prefix).weight"),
            scales: try tensor("\(prefix).scales"),
            biases: nil,
            rhsIndices: indices,
            transpose: true,
            groupSize: config.quantization.groupSize,
            bits: config.quantization.bits,
            mode: quantizationMode,
            sortedIndices: false
        )
        guard let bias = weights["\(prefix).bias"] else {
            return output
        }
        return output + bias[indices].expandedDimensions(axis: -2)
    }

    private func rmsNorm(_ x: MLXArray, key: String) throws -> MLXArray {
        try MLX.rmsNorm(x, weight: tensor(key), eps: config.rmsNormEps)
    }

    private func applyRoPE(_ x: MLXArray) -> MLXArray {
        let length = x.shape[x.shape.count - 2]
        let positions = MLXArray(0..<length).asType(.float32)
        let frequencies = positions.expandedDimensions(axis: 1) * invFrequency.expandedDimensions(axis: 0)
        let cosines = (cos(frequencies) * ropeAttentionScaling).asType(x.dtype)
            .expandedDimensions(axes: [0, 1])
        let sines = (sin(frequencies) * ropeAttentionScaling).asType(x.dtype)
            .expandedDimensions(axes: [0, 1])

        let first = x[.ellipsis, .stride(from: 0, by: 2)]
        let second = x[.ellipsis, .stride(from: 1, by: 2)]
        let rotatedFirst = first * cosines - second * sines
        let rotatedSecond = second * cosines + first * sines
        return stacked([rotatedFirst, rotatedSecond], axis: -1).reshaped(x.shape)
    }

    private func makeBidirectionalSlidingWindowMask(length: Int, attentionMask: MLXArray) -> MLXArray? {
        if length <= 1 {
            return nil
        }
        let positions = MLXArray(0..<length)
        let distance = abs(positions.expandedDimensions(axis: 0) - positions.expandedDimensions(axis: 1))
        var allowed = distance .<= config.slidingWindow
        let keyAllowed = attentionMask.asType(.bool)
        allowed = allowed.expandedDimensions(axes: [0, 1])
            .&& keyAllowed.expandedDimensions(axes: [1, 2])
        return MLX.where(
            allowed,
            MLXArray(Float(0)),
            MLXArray(Float(-1.0e9))
        )
    }

    private func tensor(_ key: String) throws -> MLXArray {
        guard let value = weights[key] else {
            throw MLXPrivacyModelError.missingTensor(key)
        }
        return value
    }

    private static func validate(_ config: MLXPrivacyConfig) throws {
        guard config.vocabSize > 0 else {
            throw MLXPrivacyModelError.invalidConfig("vocab_size must be greater than zero")
        }
        guard config.hiddenSize > 0 else {
            throw MLXPrivacyModelError.invalidConfig("hidden_size must be greater than zero")
        }
        guard config.intermediateSize > 0 else {
            throw MLXPrivacyModelError.invalidConfig("intermediate_size must be greater than zero")
        }
        guard config.numHiddenLayers > 0 else {
            throw MLXPrivacyModelError.invalidConfig("num_hidden_layers must be greater than zero")
        }
        guard config.numAttentionHeads > 0 else {
            throw MLXPrivacyModelError.invalidConfig("num_attention_heads must be greater than zero")
        }
        guard config.numKeyValueHeads > 0 else {
            throw MLXPrivacyModelError.invalidConfig("num_key_value_heads must be greater than zero")
        }
        guard config.numLocalExperts > 0 else {
            throw MLXPrivacyModelError.invalidConfig("num_local_experts must be greater than zero")
        }
        guard config.numExpertsPerToken > 0,
              config.numExpertsPerToken <= config.numLocalExperts else {
            throw MLXPrivacyModelError.invalidConfig("num_experts_per_tok must be between 1 and num_local_experts")
        }
        guard config.headDim > 0 else {
            throw MLXPrivacyModelError.invalidConfig("head_dim must be greater than zero")
        }
        guard config.hiddenSize == config.numAttentionHeads * config.headDim else {
            throw MLXPrivacyModelError.invalidConfig("hidden_size must equal num_attention_heads * head_dim")
        }
        guard config.numAttentionHeads.isMultiple(of: config.numKeyValueHeads) else {
            throw MLXPrivacyModelError.invalidConfig("num_attention_heads must be divisible by num_key_value_heads")
        }
        guard config.slidingWindow > 0 else {
            throw MLXPrivacyModelError.invalidConfig("sliding_window must be greater than zero")
        }
        guard config.rmsNormEps > 0 else {
            throw MLXPrivacyModelError.invalidConfig("rms_norm_eps must be greater than zero")
        }
        guard config.padTokenID >= 0, config.padTokenID < config.vocabSize else {
            throw MLXPrivacyModelError.invalidConfig("pad_token_id must be within the vocabulary")
        }
        guard config.maxPositionEmbeddings > 0 else {
            throw MLXPrivacyModelError.invalidConfig("max_position_embeddings must be greater than zero")
        }
        guard config.defaultContextLength == nil || config.defaultContextLength! > 0 else {
            throw MLXPrivacyModelError.invalidConfig("default_n_ctx must be greater than zero")
        }
        guard config.quantization.groupSize > 0 else {
            throw MLXPrivacyModelError.invalidConfig("quantization.group_size must be greater than zero")
        }
        guard config.quantization.bits > 0 else {
            throw MLXPrivacyModelError.invalidConfig("quantization.bits must be greater than zero")
        }
        guard config.ropeParameters.ropeTheta > 0 else {
            throw MLXPrivacyModelError.invalidConfig("rope_theta must be greater than zero")
        }
        guard config.ropeParameters.factor > 0 else {
            throw MLXPrivacyModelError.invalidConfig("rope factor must be greater than zero")
        }
        guard config.ropeParameters.originalMaxPositionEmbeddings > 0 else {
            throw MLXPrivacyModelError.invalidConfig("original_max_position_embeddings must be greater than zero")
        }
    }

    private func validateRequiredTensors() throws {
        var required = [
            "model.embed_tokens.weight",
            "model.embed_tokens.scales",
            "model.norm.weight",
            "score.weight",
            "score.scales",
            "score.bias",
        ]
        for index in 0..<config.numHiddenLayers {
            let layer = "model.layers.\(index)"
            required += [
                "\(layer).input_layernorm.weight",
                "\(layer).post_attention_layernorm.weight",
                "\(layer).self_attn.q_proj.weight",
                "\(layer).self_attn.q_proj.scales",
                "\(layer).self_attn.q_proj.bias",
                "\(layer).self_attn.k_proj.weight",
                "\(layer).self_attn.k_proj.scales",
                "\(layer).self_attn.k_proj.bias",
                "\(layer).self_attn.v_proj.weight",
                "\(layer).self_attn.v_proj.scales",
                "\(layer).self_attn.v_proj.bias",
                "\(layer).self_attn.o_proj.weight",
                "\(layer).self_attn.o_proj.scales",
                "\(layer).self_attn.o_proj.bias",
                "\(layer).self_attn.sinks",
                "\(layer).mlp.router.weight",
                "\(layer).mlp.router.scales",
                "\(layer).mlp.router.bias",
                "\(layer).mlp.experts.up_proj.weight",
                "\(layer).mlp.experts.up_proj.scales",
                "\(layer).mlp.experts.up_proj.bias",
                "\(layer).mlp.experts.gate_proj.weight",
                "\(layer).mlp.experts.gate_proj.scales",
                "\(layer).mlp.experts.gate_proj.bias",
                "\(layer).mlp.experts.down_proj.weight",
                "\(layer).mlp.experts.down_proj.scales",
                "\(layer).mlp.experts.down_proj.bias",
            ]
        }
        for key in required where weights[key] == nil {
            throw MLXPrivacyModelError.missingTensor(key)
        }
    }

    private static func makeInvFrequency(config: MLXPrivacyConfig) -> (invFrequency: MLXArray, attentionScaling: Float) {
        guard config.ropeParameters.ropeType == "yarn" else {
            let half = MLXArray(0..<(config.headDim / 2)).asType(.float32)
            let exponent = (half * Float(2)) / Float(config.headDim)
            let posFreqs = pow(MLXArray(Float(config.ropeParameters.ropeTheta)), exponent)
            return (MLXArray(Float(1)) / posFreqs, 1)
        }

        let rope = config.ropeParameters
        let dim = config.headDim
        let factor = rope.factor
        let betaFast = rope.betaFast ?? 32
        let betaSlow = rope.betaSlow ?? 1
        let attentionFactor = rope.attentionFactor
            ?? Self.yarnMScale(factor, mscale: rope.mscale ?? 1)

        func correctionDim(_ rotations: Float) -> Float {
            Float(dim) * log(Float(rope.originalMaxPositionEmbeddings) / (rotations * 2 * Float.pi))
                / (2 * log(rope.ropeTheta))
        }

        var low = correctionDim(betaFast)
        var high = correctionDim(betaSlow)
        if rope.truncate ?? true {
            low = floor(low)
            high = ceil(high)
        }
        low = max(low, 0)
        high = min(high, Float(dim - 1))

        let half = MLXArray(0..<(dim / 2)).asType(.float32)
        let exponent = (half * Float(2)) / Float(dim)
        let posFreqs = pow(MLXArray(Float(rope.ropeTheta)), exponent)
        let invFreqExtrapolation = MLXArray(Float(1)) / posFreqs
        let invFreqInterpolation = MLXArray(Float(1)) / (Float(factor) * posFreqs)
        let denominator = high == low ? Float(0.001) : high - low
        let ramp = clip((half - low) / denominator, min: Float(0), max: Float(1))
        let extrapolationFactor = MLXArray(Float(1)) - ramp
        let invFrequency = invFreqInterpolation * (MLXArray(Float(1)) - extrapolationFactor)
            + invFreqExtrapolation * extrapolationFactor
        return (invFrequency, attentionFactor)
    }

    private static func yarnMScale(_ scale: Float, mscale: Float = 1) -> Float {
        scale <= 1 ? 1 : 0.1 * mscale * log(scale) + 1
    }
}

private struct MLXPrivacyConfig: Decodable {
    let modelType: String
    let vocabSize: Int
    let hiddenSize: Int
    let intermediateSize: Int
    let numHiddenLayers: Int
    let numAttentionHeads: Int
    let numKeyValueHeads: Int
    let numLocalExperts: Int
    let numExpertsPerToken: Int
    let headDim: Int
    let slidingWindow: Int
    let rmsNormEps: Float
    let padTokenID: Int
    let maxPositionEmbeddings: Int
    let defaultContextLength: Int?
    let quantization: MLXPrivacyQuantization
    let ropeParameters: MLXPrivacyRopeParameters

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case vocabSize = "vocab_size"
        case hiddenSize = "hidden_size"
        case intermediateSize = "intermediate_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case numLocalExperts = "num_local_experts"
        case numExpertsPerToken = "num_experts_per_tok"
        case headDim = "head_dim"
        case slidingWindow = "sliding_window"
        case rmsNormEps = "rms_norm_eps"
        case padTokenID = "pad_token_id"
        case maxPositionEmbeddings = "max_position_embeddings"
        case defaultContextLength = "default_n_ctx"
        case quantization
        case ropeParameters = "rope_parameters"
    }
}

private struct MLXPrivacyQuantization: Decodable {
    let groupSize: Int
    let bits: Int
    let mode: String

    enum CodingKeys: String, CodingKey {
        case groupSize = "group_size"
        case bits
        case mode
    }
}

private struct MLXPrivacyRopeParameters: Decodable {
    let ropeType: String
    let ropeTheta: Float
    let factor: Float
    let originalMaxPositionEmbeddings: Int
    let betaFast: Float?
    let betaSlow: Float?
    let attentionFactor: Float?
    let mscale: Float?
    let truncate: Bool?

    enum CodingKeys: String, CodingKey {
        case ropeType = "rope_type"
        case ropeTheta = "rope_theta"
        case factor
        case originalMaxPositionEmbeddings = "original_max_position_embeddings"
        case betaFast = "beta_fast"
        case betaSlow = "beta_slow"
        case attentionFactor = "attention_factor"
        case mscale
        case truncate
    }
}
