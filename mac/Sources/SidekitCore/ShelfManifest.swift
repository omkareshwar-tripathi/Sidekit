import Foundation

/// Pure codec for the agent-facing Shelf contract (spec 2026-06-12 §2): the `manifest.json`
/// bytes, the static `AGENTS.md` body, and the clipboard prompt. No I/O — the persistence
/// decorator owns the files; this owns only `[ShelfItem]` + retention → bytes. Mirrors
/// `ShelfCodec`. Output is deterministic (sorted keys, ISO-8601 dates, injected `now`) so
/// repeated writes of an unchanged shelf are byte-identical.
///
/// All agent-facing strings are token-budgeted (user decision): agents read them into
/// context on every use, so keep them short — don't "improve" the wording.
public enum ShelfManifest {
    public static let schema = 1

    /// The static `AGENTS.md` placed beside the manifest (spec §2.3).
    public static let agentsNote = """
    # Sidekit Shelf
    Files the user parked in Sidekit. Read-only: do not add, edit, or delete anything here.
    List items: read `manifest.json` (newest first; each `path` is relative to this folder).
    Items expire (`expiresAt`) — re-read `manifest.json` before each use.
    """

    /// The paste-ready prompt behind the footer's copy action (spec §2.4). `path` is the
    /// advertised folder — `~/.sidekit/shelf` normally, the real folder when no symlink.
    public static func instructions(path: String) -> String {
        "The Sidekit Shelf is at \(path). Read manifest.json there to list items "
        + "(newest first; `path` is relative to that folder), then read the files you need. Read-only."
    }

    /// The `manifest.json` bytes for the current shelf. `expiresAt` is computed from the
    /// retention TTL at write time; "never expire" writes an explicit `null` (key always present).
    public static func json(items: [ShelfItem], retention: ShelfRetentionPolicy, now: Date) -> Data {
        let ttl = retention.ttl.map { Double($0.components.seconds) }
        let entries = items.sorted { $0.addedAt > $1.addedAt }.map { item in
            Entry(id: item.id.uuidString, kind: item.kind.rawValue, name: item.displayName,
                  addedAt: item.addedAt,
                  expiresAt: ttl.map { item.addedAt.addingTimeInterval($0) },
                  bytes: item.byteSize, path: item.storedRelativePath)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(Root(schema: schema, updatedAt: now, items: entries))) ?? Data()
    }

    private struct Root: Encodable {
        let schema: Int
        let updatedAt: Date
        let items: [Entry]
    }

    private struct Entry: Encodable {
        let id: String
        let kind: String
        let name: String
        let addedAt: Date
        let expiresAt: Date?
        let bytes: Int64
        let path: String

        // Hand-written so a nil `expiresAt` encodes as an explicit JSON null — synthesized
        // Encodable would drop the key, and agents rely on its presence (spec §2.2).
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(kind, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(addedAt, forKey: .addedAt)
            try c.encode(expiresAt, forKey: .expiresAt) // Optional encodes nil as null
            try c.encode(bytes, forKey: .bytes)
            try c.encode(path, forKey: .path)
        }
        private enum CodingKeys: String, CodingKey {
            case id, kind, name, addedAt, expiresAt, bytes, path
        }
    }
}
