import Foundation

/// Minimal append-only file logger for on-device diagnostics. Writes to
/// ~/Library/Logs/SpeakType.log (reliable, unlike NSLog→unified-log for a GUI app).
enum Diag {
    private static let lock = NSLock()
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SpeakType.log")

    static func log(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        let line = Data("\(Date()) \(message)\n".utf8)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? line.write(to: url)
        } else if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }
}
