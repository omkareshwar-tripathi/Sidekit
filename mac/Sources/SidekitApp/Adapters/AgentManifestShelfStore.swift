import Foundation
import SidekitCore

/// `ShelfPersisting` decorator that keeps the agent-facing files in the payload folder in sync
/// with every index save (spec 2026-06-12 §2.2): `manifest.json` on each `save`, `AGENTS.md`
/// once if missing. Both are derived state — a failed write is Diag-logged and healed by the
/// next save, never fatal.
///
/// `@unchecked Sendable`: `retention` is read/written only on the main actor (saves are
/// synchronous on the caller, same discipline as `JSONShelfStore`); the rest is immutable.
final class AgentManifestShelfStore: ShelfPersisting, @unchecked Sendable {
    private let inner: ShelfPersisting
    private let folder: URL
    private let now: () -> Date
    /// Drives each entry's `expiresAt`; updated by `ShelfModel.setRetentionTTL`.
    var retention: ShelfRetentionPolicy = .default

    init(inner: ShelfPersisting, folder: URL, now: @escaping () -> Date = { Date() }) {
        self.inner = inner
        self.folder = folder
        self.now = now
    }

    func load() -> [ShelfItem] { inner.load() }

    func save(_ items: [ShelfItem]) {
        inner.save(items)
        writeAgentFiles(items)
    }

    /// Also called at startup (fresh install; heals a manual delete) and on retention changes
    /// (so `expiresAt` doesn't go stale) — see `ShelfModel`.
    func writeAgentFiles(_ items: [ShelfItem]) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try ShelfManifest.json(items: items, retention: retention, now: now())
                .write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
            let agents = folder.appendingPathComponent("AGENTS.md")
            if !FileManager.default.fileExists(atPath: agents.path) {
                try Data(ShelfManifest.agentsNote.utf8).write(to: agents, options: .atomic)
            }
        } catch {
            Diag.log("shelf: agent files write failed (\(error))")
        }
    }
}
