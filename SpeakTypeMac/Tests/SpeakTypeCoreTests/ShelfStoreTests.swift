import Testing
import Foundation
@testable import SpeakTypeCore

@MainActor
struct ShelfStoreTests {

    private func makeSUT(seed: [ShelfItem] = [],
                        retention: ShelfRetentionPolicy = .default) -> (ShelfStore, FakeShelfPersistence) {
        let persistence = FakeShelfPersistence(seed)
        let store = ShelfStore(persistence: persistence, retention: retention, now: FakeDates().next)
        return (store, persistence)
    }

    private func makeSUTWithPayloads(seed: [ShelfItem] = [],
                                     retention: ShelfRetentionPolicy = .default) -> (ShelfStore, FakeShelfPayloadStore) {
        let payloads = FakeShelfPayloadStore()
        let store = ShelfStore(persistence: FakeShelfPersistence(seed), payloads: payloads,
                               retention: retention, now: FakeDates().next)
        return (store, payloads)
    }

    private func item(_ name: String, at seconds: TimeInterval) -> ShelfItem {
        ShelfItem(kind: .file, displayName: name, byteSize: 1,
                  addedAt: Date(timeIntervalSinceReferenceDate: seconds), storedRelativePath: name)
    }

    @discardableResult
    private func add(_ store: ShelfStore, _ name: String, kind: ShelfItemKind = .file) -> ShelfItem {
        store.add(kind: kind, displayName: name, byteSize: 10, storedRelativePath: "\(name)/payload")
    }

    // MARK: - add

    @Test func addInsertsItemAtTopAndPersists() {
        let (store, persistence) = makeSUT()
        let item = add(store, "a")
        #expect(store.items.first?.id == item.id)
        #expect(store.items.count == 1)
        #expect(persistence.saveCount == 1)
    }

    @Test func addStampsAddedAtFromClock() {
        let (store, _) = makeSUT()
        let item = add(store, "a") // FakeDates: first call → 1s
        #expect(item.addedAt == Date(timeIntervalSinceReferenceDate: 1))
    }

    @Test func addReturnsItemCarryingItsMetadata() {
        let (store, _) = makeSUT()
        let item = store.add(kind: .text, displayName: "snippet", byteSize: 42, storedRelativePath: "x/y")
        #expect(item.kind == .text)
        #expect(item.displayName == "snippet")
        #expect(item.byteSize == 42)
        #expect(item.storedRelativePath == "x/y")
    }

    @Test func addsAreOrderedNewestFirst() {
        let (store, _) = makeSUT()
        let a = add(store, "a") // older
        let b = add(store, "b") // newer → top
        #expect(store.items.first?.id == b.id)
        #expect(store.items.last?.id == a.id)
    }

    // MARK: - record — stage an already-copied payload

    @Test func recordStagesPayloadMetadataOnTop() {
        let (store, _) = makeSUT()
        let item = store.record(StoredPayload(kind: .image, displayName: "Shot.png", byteSize: 99,
                                              storedRelativePath: "abc/Shot.png"))
        #expect(item.kind == .image)
        #expect(item.displayName == "Shot.png")
        #expect(item.byteSize == 99)
        #expect(item.storedRelativePath == "abc/Shot.png")
        #expect(store.items.first?.id == item.id) // staged on top
    }

    // MARK: - remove

    @Test func removeDeletesByIdAndPersists() {
        let (store, persistence) = makeSUT()
        let a = add(store, "a")
        let b = add(store, "b")
        store.remove(a.id)
        #expect(!store.items.contains { $0.id == a.id })
        #expect(store.items.map(\.id) == [b.id])
        #expect(persistence.lastSaved.map(\.id) == [b.id])
    }

    @Test func removeUnknownIdIsNoop() {
        let (store, persistence) = makeSUT()
        add(store, "a")
        let before = persistence.saveCount
        store.remove(UUID())
        #expect(store.items.count == 1)
        #expect(persistence.saveCount == before)
    }

    // MARK: - clearAll

    @Test func clearAllEmptiesAndPersists() {
        let (store, persistence) = makeSUT()
        add(store, "a")
        add(store, "b")
        store.clearAll()
        #expect(store.items.isEmpty)
        #expect(persistence.lastSaved.isEmpty)
    }

    // MARK: - load

    @Test func loadsSeededItemsNewestFirst() {
        let older = ShelfItem(kind: .file, displayName: "old", byteSize: 1,
                              addedAt: Date(timeIntervalSinceReferenceDate: 1), storedRelativePath: "old")
        let newer = ShelfItem(kind: .file, displayName: "new", byteSize: 1,
                              addedAt: Date(timeIntervalSinceReferenceDate: 2), storedRelativePath: "new")
        let (store, _) = makeSUT(seed: [older, newer]) // seeded oldest-first
        #expect(store.items.map(\.displayName) == ["new", "old"]) // normalized newest-first
    }

    // MARK: - retention policy

    @Test func retentionDefaultIs48Hours() {
        #expect(ShelfRetentionPolicy.default.ttl == .seconds(48 * 3600))
    }

    // MARK: - pruneExpired

    private let ttl100 = ShelfRetentionPolicy(ttl: .seconds(100))

    @Test func pruneExpiredRemovesItemsOlderThanTTLAndPersists() {
        let (store, persistence) = makeSUT(seed: [item("old", at: 0)], retention: ttl100)
        let before = persistence.saveCount
        let removed = store.pruneExpired(now: Date(timeIntervalSinceReferenceDate: 101)) // age 101 > 100
        #expect(removed.map(\.displayName) == ["old"])
        #expect(store.items.isEmpty)
        #expect(persistence.saveCount == before + 1)
    }

    @Test func pruneExpiredKeepsItemsWithinTTLAndDoesNotPersist() {
        let (store, persistence) = makeSUT(seed: [item("fresh", at: 50)], retention: ttl100)
        let before = persistence.saveCount
        let removed = store.pruneExpired(now: Date(timeIntervalSinceReferenceDate: 101)) // age 51 < 100
        #expect(removed.isEmpty)
        #expect(store.items.map(\.displayName) == ["fresh"])
        #expect(persistence.saveCount == before) // no mutation → no save
    }

    @Test func pruneExpiredRemovesOnlyTheExpiredOnes() {
        let (store, _) = makeSUT(seed: [item("old", at: 0), item("fresh", at: 50)], retention: ttl100)
        let removed = store.pruneExpired(now: Date(timeIntervalSinceReferenceDate: 101))
        #expect(removed.map(\.displayName) == ["old"])
        #expect(store.items.map(\.displayName) == ["fresh"])
    }

    @Test func pruneExpiredIsExclusiveAtExactlyTTL() {
        let (store, _) = makeSUT(seed: [item("edge", at: 0)], retention: ttl100)
        let removed = store.pruneExpired(now: Date(timeIntervalSinceReferenceDate: 100)) // age == 100, not > 100
        #expect(removed.isEmpty)
        #expect(store.items.map(\.displayName) == ["edge"])
    }

    // MARK: - payload deletion (bytes never outlive their index entry)

    @Test func removeDeletesTheItemsPayload() {
        let (store, payloads) = makeSUTWithPayloads()
        let a = add(store, "a")
        add(store, "b")
        store.remove(a.id)
        #expect(payloads.deleted.map(\.id) == [a.id]) // only a's bytes deleted
    }

    @Test func removeUnknownIdDeletesNoPayload() {
        let (store, payloads) = makeSUTWithPayloads()
        add(store, "a")
        store.remove(UUID())
        #expect(payloads.deleted.isEmpty)
    }

    @Test func clearAllDeletesEveryPayload() {
        let (store, payloads) = makeSUTWithPayloads()
        let a = add(store, "a")
        let b = add(store, "b")
        store.clearAll()
        #expect(Set(payloads.deleted.map(\.id)) == Set([a.id, b.id]))
    }

    @Test func pruneExpiredDeletesOnlyTheExpiredPayloads() {
        let (store, payloads) = makeSUTWithPayloads(seed: [item("old", at: 0), item("fresh", at: 50)],
                                                    retention: ttl100)
        store.pruneExpired(now: Date(timeIntervalSinceReferenceDate: 101))
        #expect(payloads.deleted.map(\.displayName) == ["old"])
    }
}
