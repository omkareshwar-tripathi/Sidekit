import Foundation

/// One-time, best-effort relocation of the app's on-disk data from its legacy "SpeakType"
/// locations to the current "Sidekit" ones, run once at launch (see `AppPaths`).
///
/// Pure given its inputs — every URL and the `FileManager` are injected — so it's unit-tested
/// against temp directories. Each move happens only when the source exists and the destination
/// does **not**, so it never clobbers current data and is idempotent across launches. Failures
/// are swallowed (a rename must never block startup); the returned labels let the caller log
/// what moved.
public enum DataMigration {
    /// Relocate the legacy app-support directory and log file into place if needed.
    /// - Returns: labels of what moved (`"support"`, `"log"`); empty when nothing moved.
    @discardableResult
    public static func migrate(legacySupport: URL, currentSupport: URL,
                               legacyLog: URL, currentLog: URL,
                               fileManager fm: FileManager = .default) -> [String] {
        var moved: [String] = []
        if relocate(legacySupport, to: currentSupport, using: fm) { moved.append("support") }
        if relocate(legacyLog, to: currentLog, using: fm) { moved.append("log") }
        return moved
    }

    /// Move `from`→`to` exactly when `from` exists and `to` does not. Best-effort: any failure
    /// (permissions, a race) is swallowed and reported as "not moved".
    private static func relocate(_ from: URL, to: URL, using fm: FileManager) -> Bool {
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return false }
        do {
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: from, to: to)
            return true
        } catch {
            return false
        }
    }
}
