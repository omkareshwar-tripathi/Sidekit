import Testing
import Foundation
@testable import SidekitCore

struct NotesCodecTests {

    @Test func roundTripPreservesNotesExactly() {
        // Sub-second timestamps on purpose: the round-trip must not truncate them.
        let notes = [
            Note(body: "first note\nsecond line",
                 createdAt: Date(timeIntervalSinceReferenceDate: 100.123456),
                 updatedAt: Date(timeIntervalSinceReferenceDate: 200.987654)),
            Note(body: "",
                 createdAt: Date(timeIntervalSinceReferenceDate: 300.5),
                 updatedAt: Date(timeIntervalSinceReferenceDate: 300.5)),
        ]
        #expect(NotesCodec.decode(NotesCodec.encode(notes)) == notes)
    }

    @Test func decodesCorruptDataAsEmpty() {
        #expect(NotesCodec.decode(Data("this is not json".utf8)) == [])
    }

    @Test func decodesEmptyDataAsEmpty() {
        #expect(NotesCodec.decode(Data()) == [])
    }

    @Test func emptyListRoundTrips() {
        #expect(NotesCodec.decode(NotesCodec.encode([])) == [])
    }
}
