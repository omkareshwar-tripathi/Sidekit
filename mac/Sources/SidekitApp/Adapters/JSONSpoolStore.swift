import Foundation
import SidekitCore

/// On-disk persistence for the submission outbox, at
/// `~/Library/Application Support/Sidekit/outbox.json` — how a failed send survives
/// quit/offline until the next launch retries it. Same tolerant/atomic pattern as the
/// other JSON stores. `@unchecked Sendable`: `url` is immutable, no shared mutable state.
final class JSONSpoolStore: SpoolPersisting, @unchecked Sendable {
    private let url = AppPaths.applicationSupport.appendingPathComponent("outbox.json")

    func load() -> [SpooledSubmission] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else {
            Diag.log("outbox: could not read \(url.lastPathComponent)")
            return []
        }
        return SpoolCodec.decode(data)
    }

    func save(_ entries: [SpooledSubmission]) {
        let data = SpoolCodec.encode(entries)
        do {
            try writeAtomically(data)
        } catch {
            do { try writeAtomically(data) }
            catch { Diag.log("outbox: save failed twice — keeping in memory (\(error))") }
        }
    }

    private func writeAtomically(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
