import Testing
@testable import SpeakTypeCore

struct RoutingSinkTests {

    @Test func focusedAppendsToNoteAndReportsAddedToNote() {
        var appended: [String] = []
        let paste = FakeSink()
        let sink = RoutingSink(
            isAppFocused: { true },
            appendToNote: { appended.append($0) },
            pasteSink: paste)

        let outcome = sink.deliver("hello world")

        #expect(appended == ["hello world"])
        #expect(outcome == .addedToNote)
        #expect(paste.delivered.isEmpty) // did not fall back to paste
    }

    @Test func unfocusedDelegatesToPasteSinkAndReturnsItsOutcome() {
        var appended: [String] = []
        let paste = FakeSink()
        paste.outcome = .leftOnClipboard
        let sink = RoutingSink(
            isAppFocused: { false },
            appendToNote: { appended.append($0) },
            pasteSink: paste)

        let outcome = sink.deliver("hello world")

        #expect(paste.delivered == ["hello world"])
        #expect(outcome == .leftOnClipboard)
        #expect(appended.isEmpty) // did not touch notes
    }
}
