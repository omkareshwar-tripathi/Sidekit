import Foundation

/// A single scratchpad note: plain text plus timestamps. Pure value type — the store owns the
/// collection and mutation rules; persistence is a separate port.
public struct Note: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var body: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), body: String = "", createdAt: Date, updatedAt: Date) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// First non-empty line, trimmed — the sidebar's display title. Empty when the note has no
    /// text yet (the UI substitutes a placeholder like "New note").
    public var title: String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}
