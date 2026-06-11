import Foundation
import SidekitCore

/// Canonical on-disk locations for Sidekit's app data, plus the one-time migration from the
/// app's former "SpeakType" locations. Resolved from the real user directories;
/// `migrateLegacyDataIfNeeded()` runs once at launch (`SidekitApp.init`), before any store
/// touches disk, so a returning SpeakType user keeps their notes / history / shelf / log.
enum AppPaths {
    /// `~/Library/Application Support/Sidekit/` — the support dir shared by notes/history/shelf.
    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sidekit", isDirectory: true)
    }

    /// `~/Library/Logs/Sidekit.log` — the diagnostics log (see `Diag`).
    static var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Sidekit.log")
    }

    /// Relocate data left by the pre-rebrand "SpeakType" app, once. No-op on a clean install or
    /// after the first migrated launch (see `DataMigration`).
    static func migrateLegacyDataIfNeeded() {
        let fm = FileManager.default
        let legacySupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakType", isDirectory: true)
        let legacyLog = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SpeakType.log")
        let moved = DataMigration.migrate(legacySupport: legacySupport, currentSupport: applicationSupport,
                                          legacyLog: legacyLog, currentLog: logFile, fileManager: fm)
        if !moved.isEmpty { Diag.log("migrated legacy SpeakType data: \(moved.joined(separator: ", "))") }
    }
}
