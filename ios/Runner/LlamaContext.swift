import Foundation

// MARK: - LlamaContext

/// Thread-safe wrapper around a single llama.cpp model + context pair.
/// All inference runs on a dedicated `DispatchQueue` so the main thread
/// is never blocked.
final class LlamaContext {

    // ── Private state ────────────────────────────────────────────────────────
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var sparams = llama_sampler_chain_default_params()
    private var sampler: OpaquePointer?

    private let queue = DispatchQueue(label: "atlas.llama.inference", qos: .userInitiated)
    private var isCancelled = false

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /// Load a GGUF model from disk.
    /// - Parameter path: Absolute path to the `.gguf` file in Documents/.
    /// - Returns: Number of context tokens the model was initialised with.
    /// - Throws: `LlamaError` if loading fails.
    func loadModel(path: String) throws -> Int {
        guard FileManager.default.fileExists(atPath: path) else {
            throw LlamaError.modelNotFound(path)
        }

        // Model params
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = 99          // Offload everything to Metal

        guard let loadedModel = llama_model_load_from_file(path, mparams) else {
            throw LlamaError.loadFailed("llama_model_load_from_file returned nil")
        }
        model = loadedModel

        // Context params
        var cparams = llama_context_default_params()
        cparams.n_ctx  = 8192
        cparams.n_batch = 512
        cparams.flash_attn = true

        guard let loadedCtx = llama_init_from_model(loadedModel, cparams) else {
            llama_model_free(loadedModel)
            model = nil
            throw LlamaError.loadFailed("llama_init_from_model returned nil")
        }
        ctx = loadedCtx

        // Sampler chain: greedy + temperature
        sparams = llama_sampler_chain_default_params()
        sampler = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.2))
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        return Int(cparams.n_ctx)
    }

    func unloadModel() {
        isCancelled = true
        if let s = sampler { llama_sampler_free(s); sampler = nil }
        if let c = ctx     { llama_free(c);          ctx = nil    }
        if let m = model   { llama_model_free(m);    model = nil  }
    }

    // ── Inference ─────────────────────────────────────────────────────────────

    /// Generate tokens asynchronously, streaming each to `onToken`.
    /// - Parameters:
    ///   - prompt: Raw text prompt (caller applies chat template externally).
    ///   - maxTokens: Hard cap on generated tokens.
    ///   - temperature: Sampling temperature (overrides sampler default).
    ///   - onToken: Called on each produced text piece; return `false` to stop.
    ///   - onComplete: Called when generation finishes (cancelled or EOS).
    func generate(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        onToken: @escaping (String) -> Bool,
        onComplete: @escaping (Error?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.isCancelled = false
            do {
                try self._generate(
                    prompt: prompt,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    onToken: onToken
                )
                onComplete(nil)
            } catch {
                onComplete(error)
            }
        }
    }

    func cancel() {
        isCancelled = true
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private func _generate(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        onToken: (String) -> Bool
    ) throws {
        guard let model, let ctx, let sampler else {
            throw LlamaError.notLoaded
        }

        // Update temperature on the sampler chain
        // (chain index 0 = temp; re-add if needed — simpler to rebuild)
        llama_sampler_free(self.sampler)
        var sp = llama_sampler_chain_default_params()
        let newSampler = llama_sampler_chain_init(sp)
        llama_sampler_chain_add(newSampler, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(newSampler, llama_sampler_init_greedy())
        self.sampler = newSampler

        // Tokenise prompt
        let nPrompt = -llama_tokenize(model, prompt, Int32(prompt.utf8.count), nil, 0, true, true)
        var tokens = [llama_token](repeating: 0, count: Int(nPrompt))
        guard llama_tokenize(model, prompt, Int32(prompt.utf8.count), &tokens, nPrompt, true, true) >= 0 else {
            throw LlamaError.tokenizeFailed
        }

        // Build batch from prompt tokens
        var batch = llama_batch_init(max(512, Int32(tokens.count)), 0, 1)
        defer { llama_batch_free(batch) }

        for (i, token) in tokens.enumerated() {
            _batchAdd(&batch, id: token, pos: Int32(i), seqIds: [0], logits: false)
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1   // Enable logits for last token

        if llama_decode(ctx, batch) != 0 {
            throw LlamaError.decodeFailed("Prompt decode failed")
        }

        var nCur = batch.n_tokens
        var generated = 0

        while generated < maxTokens && !isCancelled {
            let newTokenId = llama_sampler_sample(self.sampler, ctx, nCur - 1)

            if llama_token_is_eog(model, newTokenId) { break }

            // Detokenise to string
            var piece = [CChar](repeating: 0, count: 256)
            let nChars = llama_token_to_piece(model, newTokenId, &piece, 256, 0, true)
            if nChars < 0 { break }
            let tokenStr = String(bytes: piece.prefix(Int(nChars)).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""

            let cont = onToken(tokenStr)
            if !cont { break }

            // Prepare next batch (single token)
            llama_batch_clear(&batch)
            _batchAdd(&batch, id: newTokenId, pos: nCur, seqIds: [0], logits: true)
            nCur += 1

            if llama_decode(ctx, batch) != 0 { break }
            generated += 1
        }

        llama_kv_self_clear(ctx)
    }

    private func _batchAdd(
        _ batch: inout llama_batch,
        id: llama_token,
        pos: Int32,
        seqIds: [llama_seq_id],
        logits: Bool
    ) {
        let n = Int(batch.n_tokens)
        batch.token[n]    = id
        batch.pos[n]      = pos
        batch.n_seq_id[n] = Int32(seqIds.count)
        for (i, seqId) in seqIds.enumerated() {
            batch.seq_id[n]![i] = seqId
        }
        batch.logits[n]   = logits ? 1 : 0
        batch.n_tokens += 1
    }
}

// MARK: - LlamaError

enum LlamaError: LocalizedError {
    case modelNotFound(String)
    case loadFailed(String)
    case notLoaded
    case tokenizeFailed
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let p): return "Model file not found: \(p)"
        case .loadFailed(let m):   return "Model load failed: \(m)"
        case .notLoaded:           return "No model loaded"
        case .tokenizeFailed:      return "Tokenisation failed"
        case .decodeFailed(let m): return "Decode failed: \(m)"
        }
    }
}
