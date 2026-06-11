import Foundation

/// `DictationOutcome` lives in `DictationCoordinator.swift`. `Codable` is added here (not on the
/// original) so the coordinator stays untouched; Swift can't synthesize `Codable` in a cross-file
/// extension, so the (de)coding is spelled out by stable case name.
extension DictationOutcome: Codable {
    public init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        switch name {
        case "pasted": self = .pasted
        case "leftOnClipboard": self = .leftOnClipboard
        case "addedToNote": self = .addedToNote
        case "noSpeech": self = .noSpeech
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown outcome \(name)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        let name: String
        switch self {
        case .pasted: name = "pasted"
        case .leftOnClipboard: name = "leftOnClipboard"
        case .addedToNote: name = "addedToNote"
        case .noSpeech: name = "noSpeech"
        }
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

/// One logged dictation: when it happened, the cleaned text, and where it went. Pure value type —
/// `HistoryStore` owns the collection and the cap; persistence is a separate port. Mirrors `Note`.
public struct DictationHistoryEntry: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let outcome: DictationOutcome

    public init(id: UUID = UUID(), date: Date, text: String, outcome: DictationOutcome) {
        self.id = id
        self.date = date
        self.text = text
        self.outcome = outcome
    }
}
