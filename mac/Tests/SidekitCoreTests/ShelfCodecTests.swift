import Testing
import Foundation
@testable import SidekitCore

struct ShelfCodecTests {

    private func sample() -> [ShelfItem] {
        [
            ShelfItem(kind: .file, displayName: "report.pdf", byteSize: 1234,
                      addedAt: Date(timeIntervalSinceReferenceDate: 10), storedRelativePath: "a/report.pdf"),
            ShelfItem(kind: .text, displayName: "snippet", byteSize: 12,
                      addedAt: Date(timeIntervalSinceReferenceDate: 20), storedRelativePath: "b/snippet.txt"),
        ]
    }

    @Test func roundTripsItemsExactly() {
        let items = sample()
        #expect(ShelfCodec.decode(ShelfCodec.encode(items)) == items)
    }

    @Test func decodeToleratesGarbage() {
        #expect(ShelfCodec.decode(Data("not json".utf8)) == [])
    }

    @Test func decodeEmptyDataIsEmptyList() {
        #expect(ShelfCodec.decode(Data()) == [])
    }

    @Test func encodeEmptyListIsDecodableToEmpty() {
        #expect(ShelfCodec.decode(ShelfCodec.encode([])) == [])
    }
}
