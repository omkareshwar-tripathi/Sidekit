import Testing
@testable import SpeakTypeCore

struct HistoryRecordingSinkTests {

    @Test func deliverForwardsToInnerAndReturnsItsOutcome() {
        let inner = FakeSink()
        inner.outcome = .addedToNote
        var recorded: [(String, DictationOutcome)] = []
        let sink = HistoryRecordingSink(inner: inner) { recorded.append(($0, $1)) }

        let outcome = sink.deliver("hello world")

        #expect(inner.delivered == ["hello world"])
        #expect(outcome == .addedToNote)
    }

    @Test func recordsExactlyOnceWithTextAndInnerOutcome() {
        let inner = FakeSink()
        inner.outcome = .leftOnClipboard
        var recorded: [(String, DictationOutcome)] = []
        let sink = HistoryRecordingSink(inner: inner) { recorded.append(($0, $1)) }

        _ = sink.deliver("note this")

        #expect(recorded.count == 1)
        #expect(recorded.first?.0 == "note this")
        #expect(recorded.first?.1 == .leftOnClipboard)
    }
}
