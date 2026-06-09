import Foundation

/// What a shelved item is. Files are the primary citizen; text/image snippets are first-class
/// too. The original source path isn't kept — the payload store owns the bytes (a copy), located
/// by `ShelfItem.storedRelativePath`.
public enum ShelfItemKind: String, Sendable, Codable {
    case file
    case folder
    case text
    case image
}

/// One item parked on the Shelf. Pure value type — `ShelfStore` owns the collection and mutation
/// rules; the bytes live in the payload store (a later adapter brick). `addedAt` drives expiry.
public struct ShelfItem: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let kind: ShelfItemKind
    public var displayName: String
    public let byteSize: Int64
    public let addedAt: Date
    /// Where the copied bytes live inside the app-managed store (relative to its root).
    public let storedRelativePath: String

    public init(id: UUID = UUID(), kind: ShelfItemKind, displayName: String, byteSize: Int64,
                addedAt: Date, storedRelativePath: String) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.byteSize = byteSize
        self.addedAt = addedAt
        self.storedRelativePath = storedRelativePath
    }
}
