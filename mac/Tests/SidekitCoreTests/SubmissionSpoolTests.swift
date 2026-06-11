import Testing
import Foundation
@testable import SidekitCore

@MainActor
struct SubmissionSpoolTests {

    private let signup = RemoteSubmission.signup(email: "a@b.co", appVersion: "1")
    private let bug = RemoteSubmission.feedback(kind: .bug, message: "m", email: nil,
                                                appVersion: "1", osVersion: "15")

    private func makeSUT(seed: [SpooledSubmission] = []) -> (SubmissionSpool, FakeSpoolPersistence, FakeSender) {
        let persistence = FakeSpoolPersistence(seed)
        let sender = FakeSender()
        return (SubmissionSpool(persistence: persistence, sender: sender), persistence, sender)
    }

    @Test func enqueueSendsImmediatelyAndEmptiesTheSpool() async {
        let (spool, persistence, sender) = makeSUT()
        let deliveredNow = await spool.enqueue(signup)
        #expect(deliveredNow)
        #expect(spool.pending.isEmpty)
        #expect(sender.sent == [signup])
        #expect(persistence.stored.isEmpty) // success persisted too
    }

    @Test func retryableKeepsTheEntryQueued() async {
        let (spool, persistence, sender) = makeSUT()
        sender.results = [.retryable]
        let deliveredNow = await spool.enqueue(bug)
        #expect(!deliveredNow)
        #expect(spool.pending.count == 1)
        #expect(persistence.stored.count == 1) // survives a relaunch
    }

    @Test func retryAllFlushesAQueuedEntry() async {
        let (first, persistence, firstSender) = makeSUT()
        firstSender.results = [.retryable]
        _ = await first.enqueue(signup)
        // "Relaunch": a fresh spool loads the persisted outbox and retries at launch.
        let (second, _, secondSender) = makeSUT(seed: persistence.stored)
        await second.retryAll()
        #expect(secondSender.sent == [signup])
        #expect(second.pending.isEmpty)
    }

    @Test func rejectedEntryIsDroppedAfterThreeStrikes() async {
        let (spool, _, sender) = makeSUT()
        sender.results = [.rejected]
        _ = await spool.enqueue(bug)               // strike 1
        #expect(spool.pending.first?.rejections == 1)
        sender.results = [.rejected]
        await spool.retryAll()                     // strike 2
        #expect(spool.pending.first?.rejections == 2)
        sender.results = [.rejected]
        await spool.retryAll()                     // strike 3 — dropped (poison payload)
        #expect(spool.pending.isEmpty)
    }

    @Test func capacityDropsTheOldestEntry() async {
        let (spool, _, sender) = makeSUT()
        sender.defaultResult = .retryable // nothing ever goes out — the queue only grows
        _ = await spool.enqueue(signup) // the oldest — should be evicted
        for _ in 0..<SubmissionSpool.capacity { _ = await spool.enqueue(bug) }
        #expect(spool.pending.count == SubmissionSpool.capacity)
        #expect(spool.pending.first?.submission == bug) // signup evicted
    }

    @Test func mixedFlushKeepsOnlyTheRetryable() async {
        let seed = [SpooledSubmission(submission: signup), SpooledSubmission(submission: bug)]
        let (spool, persistence, sender) = makeSUT(seed: seed)
        sender.results = [.sent, .retryable]
        await spool.retryAll()
        #expect(spool.pending.map(\.submission) == [bug])
        #expect(persistence.stored.map(\.submission) == [bug])
    }

    @Test func spoolCodecRoundTripsAndToleratesCorruptData() throws {
        let entries = [SpooledSubmission(submission: signup, rejections: 2)]
        #expect(SpoolCodec.decode(SpoolCodec.encode(entries)) == entries)
        #expect(SpoolCodec.decode(Data("garbage".utf8)) == [])
    }
}
