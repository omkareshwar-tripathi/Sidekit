import Foundation
import SidekitCore

/// On-disk persistence for the identity state, at
/// `~/Library/Application Support/Sidekit/identity.json`. Mirrors `JSONHistoryStore`:
/// tolerant load (missing/corrupt → fresh state, logged), atomic write with one retry.
/// `@unchecked Sendable`: `url` is immutable and there's no mutable shared state.
final class JSONIdentityStore: IdentityPersisting, @unchecked Sendable {
    private let url = AppPaths.applicationSupport.appendingPathComponent("identity.json")

    func load() -> IdentityState {
        guard FileManager.default.fileExists(atPath: url.path) else { return IdentityState() }
        guard let data = try? Data(contentsOf: url) else {
            Diag.log("identity: could not read \(url.lastPathComponent)")
            return IdentityState()
        }
        return IdentityCodec.decode(data)
    }

    func save(_ state: IdentityState) {
        let data = IdentityCodec.encode(state)
        do {
            try writeAtomically(data)
        } catch {
            do { try writeAtomically(data) }
            catch { Diag.log("identity: save failed twice — keeping in memory (\(error))") }
        }
    }

    private func writeAtomically(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
