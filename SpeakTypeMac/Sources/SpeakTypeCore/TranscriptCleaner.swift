/// Minimal transcript cleanup: trims, collapses internal whitespace runs, and appends a
/// single trailing space so consecutive dictations don't run together (matches the C#
/// cleaner's trailing-space behavior). Returns "" for blank input, which the coordinator
/// treats as no-speech.
///
/// NOTE: full filler-word removal (the 136-line C# `TranscriptCleaner`) is deferred to a
/// follow-on brick (MAC-2b); the MVP dictation path doesn't need it.
public struct TranscriptCleaner: Sendable {
    public init() {}

    public func clean(_ raw: String) -> String {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? "" : collapsed + " "
    }
}
