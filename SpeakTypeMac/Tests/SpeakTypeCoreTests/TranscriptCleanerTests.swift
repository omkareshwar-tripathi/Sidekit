import Testing
@testable import SpeakTypeCore

struct TranscriptCleanerTests {
    private let cleaner = TranscriptCleaner()

    @Test func trimsAndAppendsTrailingSpace() {
        #expect(cleaner.clean("  hello  ") == "hello ")
    }

    @Test func collapsesInternalWhitespaceRuns() {
        #expect(cleaner.clean("hello\n\tworld   there") == "hello world there ")
    }

    @Test func blankInputBecomesEmpty() {
        #expect(cleaner.clean("   \n\t ") == "")
        #expect(cleaner.clean("") == "")
    }
}
