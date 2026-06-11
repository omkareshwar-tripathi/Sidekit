import Testing
import Foundation
@testable import SidekitCore

struct ShelfManifestTests {
    // Whole-second dates: the manifest serializes ISO-8601 without fractional seconds.
    private let t0 = Date(timeIntervalSince1970: 1_786_000_000)

    private func item(name: String = "shot.png", addedAt: Date,
                      path: String = "u1/shot.png") -> ShelfItem {
        ShelfItem(kind: .file, displayName: name, byteSize: 7, addedAt: addedAt,
                  storedRelativePath: path)
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func emptyShelfStillProducesValidManifest() throws {
        let root = try decode(ShelfManifest.json(items: [], retention: .default, now: t0))
        #expect(root["schema"] as? Int == 1)
        #expect((root["items"] as? [Any])?.isEmpty == true)
        #expect(root["updatedAt"] as? String != nil)
    }

    @Test func entryCarriesAllAgentFacingFields() throws {
        let it = item(addedAt: t0)
        let root = try decode(ShelfManifest.json(items: [it], retention: .default, now: t0))
        let entry = try #require((root["items"] as? [[String: Any]])?.first)
        #expect(entry["id"] as? String == it.id.uuidString)
        #expect(entry["kind"] as? String == "file")
        #expect(entry["name"] as? String == "shot.png")
        #expect(entry["bytes"] as? Int == 7)
        #expect(entry["path"] as? String == "u1/shot.png")
        // expiresAt = addedAt + 48h (the default retention)
        let expires = try #require(entry["expiresAt"] as? String)
        let parsed = try #require(ISO8601DateFormatter().date(from: expires))
        #expect(parsed == t0.addingTimeInterval(48 * 3600))
    }

    @Test func itemsAreNewestFirst() throws {
        let old = item(name: "old", addedAt: t0)
        let new = item(name: "new", addedAt: t0.addingTimeInterval(60))
        let root = try decode(ShelfManifest.json(items: [old, new], retention: .default, now: t0))
        let names = (root["items"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        #expect(names == ["new", "old"])
    }

    @Test func neverExpireWritesExplicitNull() throws {
        let root = try decode(ShelfManifest.json(items: [item(addedAt: t0)],
                                                 retention: ShelfRetentionPolicy(ttl: nil), now: t0))
        let entry = try #require((root["items"] as? [[String: Any]])?.first)
        // The key must be PRESENT with a JSON null — agents rely on it (spec §2.2).
        #expect(entry.keys.contains("expiresAt"))
        #expect(entry["expiresAt"] is NSNull)
    }

    @Test func outputIsDeterministic() {
        let items = [item(addedAt: t0)]
        let a = ShelfManifest.json(items: items, retention: .default, now: t0)
        let b = ShelfManifest.json(items: items, retention: .default, now: t0)
        #expect(a == b)
    }

    @Test func instructionsEmbedTheAdvertisedPath() {
        let prompt = ShelfManifest.instructions(path: "~/.sidekit/shelf")
        #expect(prompt.contains("~/.sidekit/shelf"))
        #expect(prompt.contains("manifest.json"))
        #expect(prompt.contains("Read-only"))
    }

    @Test func agentsNoteIsTokenLean() {
        // Budget guard (spec §1): the note agents read into context stays tiny.
        #expect(ShelfManifest.agentsNote.count < 400)
        #expect(ShelfManifest.agentsNote.contains("manifest.json"))
    }
}
