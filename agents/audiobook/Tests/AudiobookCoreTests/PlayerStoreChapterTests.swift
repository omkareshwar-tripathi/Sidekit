import Testing
import Foundation
@testable import AudiobookCore

private func makeStore() -> PlayerStore {
    PlayerStore(book: SampleLibrary.books[0], audio: FakeAudioOutput(), clock: FakeClock())
}

struct PlayerStoreChapterTests {
    @Test func nextChapterJumpsToNextStart() {
        let s = makeStore()               // chapters at 0,60,120
        #expect(s.nextChapter() == .applied)
        #expect(s.state.position == 60)
        #expect(s.state.currentChapter == 1)
    }

    @Test func previousChapterJumpsToPriorStart() {
        let s = makeStore()
        s.goToChapter(3)                  // position 120
        #expect(s.previousChapter() == .applied)
        #expect(s.state.position == 60)
    }

    @Test func nextChapterAtLastIsNoOp() {
        let s = makeStore()
        s.goToChapter(3)
        #expect(s.nextChapter() == .applied)
        #expect(s.state.currentChapter == 2)   // unchanged (last)
    }

    @Test func goToChapterIsOneBased() {
        let s = makeStore()
        #expect(s.goToChapter(2) == .applied)
        #expect(s.state.position == 60)
        #expect(s.state.currentChapter == 1)
    }

    @Test func goToChapterOutOfRangeRejected() {
        let s = makeStore()
        if case .rejected = s.goToChapter(9) {} else { Issue.record("expected rejected") }
        if case .rejected = s.goToChapter(0) {} else { Issue.record("expected rejected") }
    }
}
