import Testing
@testable import SpeakTypeCore

struct TranscriptCleanerTests {
    private let cleaner = TranscriptCleaner()

    // --- Minimal whitespace behavior ---

    @Test func trimsAndAppendsTrailingSpace() {
        #expect(cleaner.clean("  hello  ") == "hello ")
    }

    @Test func collapsesMultipleSpaces() {
        #expect(cleaner.clean("hello   world   there") == "hello world there ")
    }

    // --- Filler removal ON (ported verbatim from C# Clean_with_filler_removal_on) ---

    @Test(arguments: [
        ("Um, I think, you know, we should ship it.", "I think we should ship it. "),
        ("I mean it.", "I mean it. "),
        ("do you know the answer?", "do you know the answer? "),
        ("i like pizza", "I like pizza "),
        ("Um, we should ship it.", "We should ship it. "),
        ("Uh, you know, it works.", "It works. "),
        ("We should ship it, you know.", "We should ship it. "),
        ("You know, it works.", "It works. "),
        ("I think um it works.", "I think it works. "),
        ("I think, um, it works.", "I think it works. "),
        ("I sort of like it.", "I sort of like it. "),
        ("Uh.", ""),
    ])
    func cleanWithFillerRemovalOn(raw: String, expected: String) {
        #expect(cleaner.clean(raw) == expected)
    }

    // --- Each filler pass guarded (ported from C# Clean_guards_each_filler_pass) ---

    @Test(arguments: [
        ("It is, sort of, fine.", "It is fine. "),
        ("I get it, kind of.", "I get it. "),
        ("Kind of, it works.", "It works. "),
        ("It works. Um, then we ship.", "It works. Then we ship. "),
        ("It works. Um then we ship.", "It works. Then we ship. "),
        ("I think, um.", "I think. "),
        ("Um 2024 was rough.", "2024 was rough. "),
        ("I think um er it works.", "I think it works. "),
    ])
    func cleanGuardsEachFillerPass(raw: String, expected: String) {
        #expect(cleaner.clean(raw) == expected)
    }

    // --- Filler removal OFF (ported from C# Clean_with_filler_removal_off) ---

    @Test(arguments: [
        ("Um, I think, you know, we should ship it.", "Um, I think, you know, we should ship it. "),
        ("i like pizza", "I like pizza "),
    ])
    func cleanWithFillerRemovalOff(raw: String, expected: String) {
        #expect(cleaner.clean(raw, removeFillers: false) == expected)
    }

    // --- Hallucinations / empty (ported from C# Clean_drops_hallucinations_and_empty) ---

    @Test(arguments: ["[BLANK_AUDIO]", "", "   ", "Thank you.", "you", "You"])
    func dropsHallucinationsAndEmpty(raw: String) {
        #expect(cleaner.clean(raw) == "")
    }
}
