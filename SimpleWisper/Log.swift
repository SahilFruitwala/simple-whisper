import Foundation
import os

/// Logs to the unified log and to ~/Library/Logs/SimpleWisper.log for easy debugging.
let log = AppLog()

final class AppLog {
    private let logger = Logger(subsystem: "com.simplewisper.app", category: "app")
    private let queue = DispatchQueue(label: "simplewisper.log")
    private let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SimpleWisper.log")

    func info(_ message: String) { write("INFO", message); logger.info("\(message, privacy: .public)") }
    func error(_ message: String) { write("ERROR", message); logger.error("\(message, privacy: .public)") }

    private func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(level) \(message)\n"
        queue.async { [url] in
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
