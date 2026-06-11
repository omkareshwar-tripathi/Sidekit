import Testing
import Foundation
@testable import SidekitCore

/// Tests for the one-time legacy "SpeakType" → "Sidekit" data relocation. All run against a
/// throwaway temp workspace so they never touch the real `~/Library` locations.
struct DataMigrationTests {
    private func makeTempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidekit-migration-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func movesLegacySupportDirIncludingNestedShelf() throws {
        let fm = FileManager.default
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let legacy = root.appendingPathComponent("SpeakType", isDirectory: true)
        let current = root.appendingPathComponent("Sidekit", isDirectory: true)
        try fm.createDirectory(at: legacy.appendingPathComponent("Shelf/abc", isDirectory: true),
                               withIntermediateDirectories: true)
        try Data("notes".utf8).write(to: legacy.appendingPathComponent("notes.json"))
        try Data("payload".utf8).write(to: legacy.appendingPathComponent("Shelf/abc/p.txt"))

        let moved = DataMigration.migrate(
            legacySupport: legacy, currentSupport: current,
            legacyLog: root.appendingPathComponent("SpeakType.log"),
            currentLog: root.appendingPathComponent("Sidekit.log"), fileManager: fm)

        #expect(moved.contains("support"))
        #expect(fm.fileExists(atPath: current.appendingPathComponent("notes.json").path))
        #expect(fm.fileExists(atPath: current.appendingPathComponent("Shelf/abc/p.txt").path))
        #expect(!fm.fileExists(atPath: legacy.path))   // legacy dir consumed by the move
    }

    @Test func doesNotClobberWhenCurrentSupportAlreadyExists() throws {
        let fm = FileManager.default
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let legacy = root.appendingPathComponent("SpeakType", isDirectory: true)
        let current = root.appendingPathComponent("Sidekit", isDirectory: true)
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("notes.json"))
        try fm.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: current.appendingPathComponent("notes.json"))

        let moved = DataMigration.migrate(
            legacySupport: legacy, currentSupport: current,
            legacyLog: root.appendingPathComponent("a.log"),
            currentLog: root.appendingPathComponent("b.log"), fileManager: fm)

        #expect(!moved.contains("support"))
        let kept = try Data(contentsOf: current.appendingPathComponent("notes.json"))
        #expect(String(decoding: kept, as: UTF8.self) == "new")  // current data preserved
        #expect(fm.fileExists(atPath: legacy.path))              // legacy left untouched
    }

    @Test func noOpOnCleanInstall() {
        let fm = FileManager.default
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let current = root.appendingPathComponent("Sidekit", isDirectory: true)

        let moved = DataMigration.migrate(
            legacySupport: root.appendingPathComponent("SpeakType", isDirectory: true),
            currentSupport: current,
            legacyLog: root.appendingPathComponent("SpeakType.log"),
            currentLog: root.appendingPathComponent("Sidekit.log"), fileManager: fm)

        #expect(moved.isEmpty)
        #expect(!fm.fileExists(atPath: current.path))  // nothing conjured into existence
    }

    @Test func movesLegacyLogWhenCurrentAbsent() throws {
        let fm = FileManager.default
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let legacyLog = root.appendingPathComponent("SpeakType.log")
        let currentLog = root.appendingPathComponent("Sidekit.log")
        try Data("log".utf8).write(to: legacyLog)

        let moved = DataMigration.migrate(
            legacySupport: root.appendingPathComponent("SpeakType", isDirectory: true),
            currentSupport: root.appendingPathComponent("Sidekit", isDirectory: true),
            legacyLog: legacyLog, currentLog: currentLog, fileManager: fm)

        #expect(moved.contains("log"))
        #expect(fm.fileExists(atPath: currentLog.path))
        #expect(!fm.fileExists(atPath: legacyLog.path))
    }

    @Test func secondRunIsIdempotentNoOp() throws {
        let fm = FileManager.default
        let root = makeTempRoot(); defer { try? fm.removeItem(at: root) }
        let legacy = root.appendingPathComponent("SpeakType", isDirectory: true)
        let current = root.appendingPathComponent("Sidekit", isDirectory: true)
        let legacyLog = root.appendingPathComponent("SpeakType.log")
        let currentLog = root.appendingPathComponent("Sidekit.log")
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("n".utf8).write(to: legacy.appendingPathComponent("notes.json"))

        _ = DataMigration.migrate(legacySupport: legacy, currentSupport: current,
                                  legacyLog: legacyLog, currentLog: currentLog, fileManager: fm)
        let second = DataMigration.migrate(legacySupport: legacy, currentSupport: current,
                                           legacyLog: legacyLog, currentLog: currentLog, fileManager: fm)

        #expect(second.isEmpty)  // already migrated → nothing more to do
        #expect(fm.fileExists(atPath: current.appendingPathComponent("notes.json").path))
    }
}
