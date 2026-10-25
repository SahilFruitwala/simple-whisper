import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Cleanup stage using S1-mini by Superwhisper, run with MLX.
actor Normalizer {
    static let repo = "mlx-community/S1-mini-MLX-8bit"
    static let systemPrompt =
        "You are a text normalizer for speech-to-text transcripts. The input begins "
        + "with a control line specifying the styling, structure, and context settings; "
        + "clean the transcript to match those settings and output only the cleaned text."

    private var container: ModelContainer?

    var isLoaded: Bool { container != nil }

    func load() async throws {
        guard container == nil else { return }
        Memory.cacheLimit = 64 * 1024 * 1024
        container = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: Self.repo)
        )
    }

    func unload() {
        container = nil
        Memory.clearCache()
    }

    func normalize(_ transcript: String, styling: String, structure: String, context: String) async throws -> String {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        try await load()

        let control = "[Styling: \(styling)] [Structure: \(structure)] [Context: \(context)]"
        let prompt =
            "<|im_start|>system\n\(Self.systemPrompt)<|im_end|>\n"
            + "<|im_start|>user\n\(control)\n\(raw)<|im_end|>\n"
            + "<|im_start|>assistant\n<think>\n\n</think>\n\n"

        let output = try await container!.perform(values: prompt) { context, prompt in
            let tokens = context.tokenizer.encode(text: prompt, addSpecialTokens: false)
            let inputTokens = max(1, context.tokenizer.encode(text: raw, addSpecialTokens: false).count)
            let params = GenerateParameters(maxTokens: Int(1.3 * Double(inputTokens)) + 32, temperature: 0)
            let input = LMInput(tokens: MLXArray(tokens))
            var text = ""
            for await event in try generate(input: input, parameters: params, context: context) {
                if case .chunk(let chunk) = event { text += chunk }
            }
            return text
        }
        return Self.stripThink(output)
    }

    static func stripThink(_ text: String) -> String {
        var out = text
        if let range = out.range(of: "</think>") { out = String(out[range.upperBound...]) }
        return out.replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
