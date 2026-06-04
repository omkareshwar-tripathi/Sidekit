import Foundation

/// Minimal append-only file logger for on-device diagnostics. Writes to
/// ~/Library/Logs/SpeakType.log (reliable, unlike NSLog→unified-log for a GUI app).
///
/// Opt-in: silent by default so normal runs leave no log. Enable it to trace the dictation
/// pipeline when something misbehaves, either way:
///   • GUI launch (`open SpeakType.app`):  defaults write com.speaktype.mac SpeakTypeDebug -bool YES
///   • terminal launch (run the binary):   SPEAKTYPE_DEBUG=1
/// Disable again with `defaults delete com.speaktype.mac SpeakTypeDebug`.
enum Diag {
    private static let lock = NSLock()
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SpeakType.log")

    /// Read once at launch. `defaults` covers the GUI app (`open` drops the shell environment);
    /// the env var covers running the executable straight from a terminal.
    static let enabled = UserDefaults.standard.bool(forKey: "SpeakTypeDebug")
        || ProcessInfo.processInfo.environment["SPEAKTYPE_DEBUG"] != nil

    static func log(_ message: String) {
        guard enabled else { return }
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
