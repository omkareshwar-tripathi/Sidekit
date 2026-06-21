import Testing
import Foundation
@testable import AudiobookCore

private func makeStore() -> (PlayerStore, FakeAudioOutput, FakeClock) {
    let audio = FakeAudioOutput(); let clock = FakeClock()
    let store = PlayerStore(book: SampleLibrary.books[0], audio: audio, clock: clock)
    return (store, audio, clock)
}

struct PlayerStoreTransportTests {
    @Test func playStartsAudioAndClock() {
        let (s, audio, clock) = makeStore()
        #expect(s.play() == .applied)
        #expect(s.state.isPlaying == true)
        #expect(audio.isPlaying == true)
        #expect(clock.running == true)
    }

    @Test func pauseStopsAudioAndClock() {
        let (s, audio, clock) = makeStore()
        s.play(); #expect(s.pause() == .applied)
        #expect(s.state.isPlaying == false)
        #expect(audio.isPlaying == false)
        #expect(clock.running == false)
    }

    @Test func positionAdvancesByDeltaTimesSpeedWhilePlaying() {
        let (s, _, clock) = makeStore()
        s.play()
        clock.tick(10)               // speed 1.0 → +10
        #expect(s.state.position == 10)
    }

    @Test func skipForwardMovesPositionAndSeeksAudio() {
        let (s, audio, _) = makeStore()
        #expect(s.skipForward(seconds: 30) == .applied)
        #expect(s.state.position == 30)
        #expect(audio.seekedTo == 30)
    }

    @Test func skipBackwardClampsAtZero() {
        let (s, _, _) = makeStore()
        s.skipForward(seconds: 20)
        #expect(s.skipBackward(seconds: 50) == .applied)
        #expect(s.state.position == 0)
    }

    @Test func positionClampsAtDurationAndPauses() {
        let (s, _, clock) = makeStore() // duration 180
        s.play()
        clock.tick(500)
        #expect(s.state.position == 180)
        #expect(s.state.isPlaying == false)
    }
}
