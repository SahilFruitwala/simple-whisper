import AVFoundation
import Foundation

/// Headless pipeline check: decode a file to 16 kHz mono, transcribe, normalize, exit.
enum SelfTest {
    static func run(path: String) -> Never {
        Task {
            do {
                let audio = try loadAudio(URL(fileURLWithPath: path))
                print("audio: \(String(format: "%.2f", Double(audio.count) / Recorder.sampleRate))s")
                let transcriber = Transcriber()
                let normalizer = Normalizer()
                let size = Settings.shared.whisperModel

                var t = Date()
                try await transcriber.load(size: size)
                print("whisper \(size) load: \(elapsed(t))")
                t = Date()
                try await normalizer.load()
                print("s1-mini load: \(elapsed(t))")

                t = Date()
                let raw = try await transcriber.transcribe(audio, size: size)
                print("whisper (\(elapsed(t))): \(raw)")
                t = Date()
                let text = try await normalizer.normalize(raw, styling: "semi-formal", structure: "prose", context: "general")
                print("s1-mini (\(elapsed(t))): \(text)")
                exit(0)
            } catch {
                print("FAILED: \(error)")
                exit(1)
            }
        }
        dispatchMain()
    }

    private static func elapsed(_ start: Date) -> String {
        String(format: "%.2fs", Date().timeIntervalSince(start))
    }

    private static func loadAudio(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Recorder.sampleRate, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: file.processingFormat, to: out)!
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let capacity = AVAudioFrameCount(Double(input.frameLength) * Recorder.sampleRate / file.processingFormat.sampleRate) + 1024
        let buffer = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: capacity)!
        var fed = false
        converter.convert(to: buffer, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
