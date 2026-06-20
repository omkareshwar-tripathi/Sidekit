import Foundation
import HuggingFace
import SidekitCore

/// Owns the model files (spec §6): HF hub snapshot of the single shared model into the
/// app's own folder, presence check, and Settings removal. One download action handles
/// one repo, with progress 0…1. AppKit-free; the app injects its root (AppPaths) and
/// logger (Diag).
public final class ModelDownloader: ModelProvisioning, @unchecked Sendable {
    /// The single shared model (spec §1 round 3): Qwen2.5-1.5B serves polish AND draft.
    public static let modelRepoID = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    private static let repoIDs = [modelRepoID]

    /// `…/Application Support/Sidekit/Intelligence` in the app; the selftest uses the same.
    public let root: URL
    private let log: @Sendable (String) -> Void

    public init(root: URL, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.root = root
        self.log = log
    }

    // MARK: - Snapshot resolution

    /// The revision folder holding this repo's complete snapshot (config.json present), or nil.
    ///
    /// API drift note: The on-disk layout is HF Python-compatible:
    ///   `<root>/models--<namespace>--<name>/snapshots/<commit>/config.json`
    /// `HubCache(cacheDirectory:)` gives us the cache object; `snapshotsDirectory` + first
    /// subdirectory + config.json probe completes the check. We use `resolveRevision` (reads
    /// the `refs/main` file) when available; otherwise fall back to the first snapshot dir
    /// that contains `config.json`.
    public func snapshotDirectory(for repoID: String) -> URL? {
        guard let repoName = Repo.ID(rawValue: repoID) else { return nil }
        let cache = HubCache(cacheDirectory: root)
        let snapshotsDir = cache.snapshotsDirectory(repo: repoName, kind: .model)

        // Fast path: resolve via refs/main (written by swift-huggingface after download).
        if let commit = cache.resolveRevision(repo: repoName, kind: .model, ref: "main") {
            let candidate = snapshotsDir.appendingPathComponent(commit)
            let config = candidate.appendingPathComponent("config.json")
            if FileManager.default.fileExists(atPath: config.path) {
                return candidate
            }
        }

        // Fallback: enumerate snapshot subdirectories for any that have config.json.
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        return entries.first { dir in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
            guard isDir.boolValue else { return false }
            return FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("config.json").path)
        }
    }

    // MARK: - ModelProvisioning

    /// Snapshot complete — a partial download lacks config.json and the load path
    /// then reports "damaged" → re-download (spec §6).
    public var isDownloaded: Bool {
        Self.repoIDs.allSatisfy { snapshotDirectory(for: $0) != nil }
    }

    /// Downloads the single shared model; progress 0…1 (spec §6).
    ///
    /// Each repo contributes 1/count of the range; per-file progress from the hub client
    /// is mapped into that slice: `base + fraction * (1/count)`.
    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let count = Double(Self.repoIDs.count)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let client = HubClient(cache: HubCache(cacheDirectory: root))
        for (index, repoID) in Self.repoIDs.enumerated() {
            guard let repoName = Repo.ID(rawValue: repoID) else { continue }
            let base = Double(index) / count
            log("downloading \(repoID)…")
            _ = try await client.downloadSnapshot(
                of: repoName,
                kind: .model,
                revision: "main"
            ) { @MainActor p in
                progress(base + p.fractionCompleted / count)
            }
            log("downloaded \(repoID)")
        }
        progress(1.0)
    }

    public func remove() throws {
        try FileManager.default.removeItem(at: root)
        log("models removed")
    }
}
