import Foundation
import WhisperKit

/// WhisperKit ASR on the Neural Engine. Loaded lazily; unloaded by the pipeline when idle.
actor Transcriber {
    private var kit: WhisperKit?
    private var loadedSize: String?

    static var modelsDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SimpleWisper/whisperkit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var isLoaded: Bool { kit != nil }

    func load(size: String) async throws {
        if loadedSize == size, kit != nil { return }
        await unload()
        let config = WhisperKitConfig(
            model: "openai_whisper-\(size)",
            downloadBase: Self.modelsDir,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: true
        )
        kit = try await WhisperKit(config)
        loadedSize = size
    }

    func unload() async {
        await kit?.unloadModels()
        kit = nil
        loadedSize = nil
    }

    func transcribe(_ audio: [Float], size: String) async throws -> String {
        // Too short or too quiet to be speech.
        guard Double(audio.count) >= Recorder.sampleRate * 0.25 else { return "" }
        let rms = sqrt(audio.reduce(0) { $0 + $1 * $1 } / Float(audio.count))
        guard rms >= 0.004 else { return "" }

        try await load(size: size)
        let options = DecodingOptions(language: "en", temperature: 0, skipSpecialTokens: true, withoutTimestamps: true)
        let results = try await kit!.transcribe(audioArray: audio, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
