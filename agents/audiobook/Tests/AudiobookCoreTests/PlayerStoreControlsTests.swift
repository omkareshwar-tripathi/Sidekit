import Testing
import Foundation
@testable import AudiobookCore

private func makeStore() -> (PlayerStore, FakeAudioOutput, FakeClock) {
    let a = FakeAudioOutput(); let c = FakeClock()
    return (PlayerStore(book: SampleLibrary.books[0], audio: a, clock: c), a, c)
}

struct PlayerStoreControlsTests {
    @Test func setSpeedWithinRangeApplies() {
        let (s, audio, _) = makeStore()
        #expect(s.setSpeed(1.5) == .applied)
        #expect(s.state.speed == 1.5)
        #expect(audio.rate == 1.5)
    }

    @Test func setSpeedOutOfRangeRejected() {
        let (s, _, _) = makeStore()
        if case .rejected = s.setSpeed(4.0) {} else { Issue.record("expected rejected") }
        #expect(s.state.speed == 1.0)
    }

    @Test func sleepTimerMinutesFiresAndPauses() {
        let (s, _, clock) = makeStore()
        s.play()
        #expect(s.setSleepTimer(minutes: 1) == .applied)   // fireAt = 60
        #expect(s.state.sleepTimer?.fireAt == 60)
        clock.tick(59); #expect(s.state.isPlaying == true)
        clock.tick(2)
        #expect(s.state.isPlaying == false)
        #expect(s.state.sleepTimer == nil)
    }

    @Test func sleepTimerEndOfChapterTargetsNextChapter() {
        let (s, _, _) = makeStore()                         // at 0, chapters 0,60,120
        #expect(s.setSleepTimerEndOfChapter() == .applied)
        #expect(s.state.sleepTimer?.fireAt == 60)
        #expect(s.state.sleepTimer?.mode == .endOfChapter)
    }

    @Test func cancelSleepTimerClears() {
        let (s, _, _) = makeStore()
        s.setSleepTimer(minutes: 5)
        #expect(s.cancelSleepTimer() == .applied)
        #expect(s.state.sleepTimer == nil)
    }

    @Test func switchBookFuzzyMatchResetsState() {
        let (s, audio, _) = makeStore()
        s.skipForward(seconds: 30)
        #expect(s.switchBook(title: "art of war") == .applied)  // fuzzy → "The Art of War"
        #expect(s.state.currentBook.id == "art-of-war")
        #expect(s.state.position == 0)
        #expect(audio.loaded == "book-b.caf")
    }

    @Test func switchBookNoMatchRejected() {
        let (s, _, _) = makeStore()
        if case .rejected = s.switchBook(title: "nonexistent") {} else { Issue.record("expected rejected") }
        #expect(s.state.currentBook.id == "meditations")
    }
}
