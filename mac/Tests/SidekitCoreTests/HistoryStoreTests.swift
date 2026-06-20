import Testing
import Foundation
@testable import SidekitCore

@MainActor
struct HistoryStoreTests {

    private func entry(_ text: String) -> DictationHistoryEntry {
        DictationHistoryEntry(date: Date(), text: text, outcome: .pasted)
    }

    @Test func addPrependsNewestFirst() {
        let store = HistoryStore()
        store.add(entry("first"))
        store.add(entry("second"))
        #expect(store.entries.map(\.text) == ["second", "first"])
    }

    @Test func capTrimsToFiftyDroppingOldest() {
        let store = HistoryStore()
        for i in 1...51 { store.add(entry("\(i)")) }
        #expect(store.entries.count == HistoryStore.maxEntries)
        #expect(store.entries.first?.text == "51") // newest kept
        #expect(store.entries.last?.text == "2")   // "1" (oldest) dropped
    }

    @Test func initTrimsSeedToCap() {
        let seed = (1...60).map { entry("\($0)") }
        let store = HistoryStore(entries: seed)
        #expect(store.entries.count == HistoryStore.maxEntries)
    }
}
