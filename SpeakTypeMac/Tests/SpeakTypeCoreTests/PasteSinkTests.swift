import Testing
@testable import SpeakTypeCore

// PasteSink is the default DictationSink: it forwards the cleaned transcript to the
// Pasting port and maps the paste result onto a DictationOutcome.
struct PasteSinkTests {
    @Test func forwardsTextAndMapsPasted() {
        let paste = FakePaste()
        paste.outcome = .pasted
        let sink = PasteSink(paste: paste)

        let outcome = sink.deliver("hello world")

        #expect(outcome == .pasted)
        #expect(paste.pasted == ["hello world"])
    }

    @Test func mapsLeftOnClipboard() {
        let paste = FakePaste()
        paste.outcome = .leftOnClipboard
        let sink = PasteSink(paste: paste)

        #expect(sink.deliver("x") == .leftOnClipboard)
    }
}
