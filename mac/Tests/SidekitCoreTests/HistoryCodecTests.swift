import Testing
import Foundation
@testable import SidekitCore

struct HistoryCodecTests {

    @Test func roundTripsEntries() {
        let entries = [
            DictationHistoryEntry(date: Date(timeIntervalSinceReferenceDate: 1), text: "one", outcome: .pasted),
            DictationHistoryEntry(date: Date(timeIntervalSinceReferenceDate: 2), text: "two", outcome: .addedToNote),
        ]
        let decoded = HistoryCodec.decode(HistoryCodec.encode(entries))
        #expect(decoded == entries)
    }

    @Test func decodeOfCorruptDataIsEmpty() {
        #expect(HistoryCodec.decode(Data("not json".utf8)).isEmpty)
    }
}
