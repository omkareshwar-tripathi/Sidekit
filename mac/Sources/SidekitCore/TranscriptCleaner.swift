import Foundation

/// Pure, side-effect-free cleanup of a raw Whisper transcript — a faithful port of the
/// C# `TranscriptCleaner`. Stages run in a fixed order: optional filler removal, always-on
/// debris fixups, trimming, and a hallucination/empty filter. A non-empty result always
/// ends in a single trailing space; terminal punctuation is never forced.
public struct TranscriptCleaner: Sendable {
    public init() {}

    /// Cleans `raw`. When `removeFillers` is true, disfluencies and boundary discourse
    /// markers are stripped. Returns "" for empty input or a known silence-hallucination;
    /// otherwise the trimmed text plus a single trailing space.
    public func clean(_ raw: String, removeFillers: Bool = true) -> String {
        var text = raw
        if removeFillers {
            text = Self.removeFillers(text)
        }
        text = Self.fixups(text)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || Self.isHallucination(trimmed) {
            return ""
        }
        return trimmed + " "
    }

    // Always-removable disfluencies, even when bare (no surrounding commas).
    private static let always = "um|uh|er|ah|hmm|mm"
    // Discourse markers — removed only at a comma/sentence boundary, so genuine uses survive.
    private static let phrase = "you know|I mean|sort of|kind of"
    private static let any = always + "|" + phrase

    private static func removeFillers(_ input: String) -> String {
        var t = input
        // 1. Filler immediately before a sentence terminator: ", um." → "."
        t = replace(t, #"\s*,\s*(?:\#(any))\b\s*([.!?])"#, withTemplate: "$1")
        // 2. Comma-bounded interior filler: "x, um, y" → "x y".
        t = replace(t, #"\s*,\s*(?:\#(any))\b\s*,\s*"#, withTemplate: " ")
        // 3. Filler at the very start, with a comma, re-capitalizing the next letter.
        t = replace(t, #"^\s*(?:\#(any))\b\s*,\s*(\p{L})"#) { $0[1].uppercased() }
        // 3b. Same, after terminal punctuation.
        t = replace(t, #"([.!?]\s+)(?:\#(any))\b\s*,\s*(\p{L})"#) { $0[1] + $0[2].uppercased() }
        // 4. ALWAYS-word at the start with an optional comma, re-capitalizing next.
        t = replace(t, #"^\s*(?:\#(always))\b,?\s*(\p{L})"#) { $0[1].uppercased() }
        // 4b. Same, after terminal punctuation.
        t = replace(t, #"([.!?]\s+)(?:\#(always))\b,?\s*(\p{L})"#) { $0[1] + $0[2].uppercased() }
        // 5. Bare interior ALWAYS-word: "I think um it" → "I think it".
        t = replace(t, #"\s+(?:\#(always))\b"#, withTemplate: "")
        // 6. A string that is only an ALWAYS word plus trailing punctuation ("Uh.") → empty.
        t = replace(t, #"^\s*(?:\#(always))\b[,.!?\s]*$"#, withTemplate: "")
        // 6b. Pure-filler ALWAYS leftover at the start with no following letter.
        t = replace(t, #"^\s*(?:\#(always))\b,?\s*"#, withTemplate: "")
        return t
    }

    private static func fixups(_ input: String) -> String {
        var t = input
        t = replace(t, #",(\s*,)+"#, withTemplate: ",")   // collapse multiple commas
        t = replace(t, #" +,"#, withTemplate: ",")          // space before comma
        t = replace(t, #" {2,}"#, withTemplate: " ")        // collapse spaces
        t = replace(t, #"^[,\s]+"#, withTemplate: "")       // leading debris
        t = replace(t, #"\bi\b"#, withTemplate: "I")        // lone "i" → "I"
        return t
    }

    // Exact tokens / short phrases Whisper emits for non-speech audio; noise only when the
    // whole output is one of them.
    private static let hallucinations = ["[BLANK_AUDIO]", "you", "Thank you."]
    private static func isHallucination(_ trimmed: String) -> Bool {
        hallucinations.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    // MARK: - Regex helpers (case-insensitive, like the C# RegexOptions.IgnoreCase)

    private static func replace(_ text: String, _ pattern: String, withTemplate template: String) -> String {
        let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    /// Closure-based replace for the re-capitalizing passes (NSRegularExpression templates
    /// can't upper-case). `groups[0]` is the whole match; `groups[1...]` are the captures —
    /// same indexing as .NET's `Match.Groups`. Matches are computed on the original string
    /// and replaced together, matching .NET `Regex.Replace` semantics.
    private static func replace(_ text: String, _ pattern: String, using transform: ([String]) -> String) -> String {
        let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = ""
        var lastEnd = 0
        for m in matches {
            result += ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            result += transform(groups)
            lastEnd = m.range.location + m.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }
}
