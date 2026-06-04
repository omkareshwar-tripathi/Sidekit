import Testing
@testable import SpeakTypeCore

@MainActor
struct DictationCoordinatorTests {

    // Builds a coordinator over fresh fakes and returns them all for assertions.
    private func makeSUT() -> (
        DictationCoordinator, FakeAudioCapture, FakeTranscriber, FakePaste, FakeClock, FakeAutoStopTimer
    ) {
        let audio = FakeAudioCapture()
        let transcriber = FakeTranscriber()
        let paste = FakePaste()
        let clock = FakeClock()
        let timer = FakeAutoStopTimer()
        let sut = DictationCoordinator(
            audio: audio, transcriber: transcriber, paste: paste,
            clock: clock, autoStop: timer
        )
        return (sut, audio, transcriber, paste, clock, timer)
    }

    @Test func pressedStartsRecordingAndArmsAutoStop() {
        let (sut, audio, _, _, _, timer) = makeSUT()
        sut.pressed()
        #expect(sut.currentState == .recording)
        #expect(audio.startCount == 1)
        #expect(timer.startedDelay == .seconds(60))
    }

    @Test func pressedWhileBusyIsIgnored() {
        let (sut, audio, _, _, _, _) = makeSUT()
        sut.pressed()
        sut.pressed() // second press while recording
        #expect(audio.startCount == 1)
    }

    @Test func shortHoldIsDiscardedWithoutOutcome() async {
        let (sut, audio, transcriber, _, clock, timer) = makeSUT()
        var completions: [DictationOutcome] = []
        sut.onCompleted = { completions.append($0) }

        clock.ticksMs = 0
        sut.pressed()
        clock.ticksMs = 200 // held 200 ms < 300 ms guard
        await sut.released()

        #expect(sut.currentState == .idle)
        #expect(audio.stopCount == 1)        // mic released
        #expect(transcriber.callCount == 0)  // never transcribed
        #expect(completions.isEmpty)         // no outcome for a tap
        #expect(timer.cancelCount == 1)
    }

    @Test func normalHoldTranscribesCleansAndPastes() async {
        let (sut, _, transcriber, paste, clock, _) = makeSUT()
        transcriber.result = "  hello   world  "
        var outcome: DictationOutcome?
        sut.onCompleted = { outcome = $0 }

        clock.ticksMs = 0
        sut.pressed()
        clock.ticksMs = 500 // held 500 ms
        await sut.released()

        #expect(outcome == .pasted)
        #expect(paste.pasted == ["hello world "]) // cleaned + trailing space
        #expect(transcriber.callCount == 1)
        #expect(sut.currentState == .idle)
    }

    @Test func noSpeechSkipsTranscriptionAndReportsNoSpeech() async {
        let (sut, audio, transcriber, _, clock, _) = makeSUT()
        audio.nextCapture = CapturedAudio(samples: [], hasSpeech: false)
        var outcome: DictationOutcome?
        sut.onCompleted = { outcome = $0 }

        sut.pressed()
        clock.ticksMs = 500
        await sut.released()

        #expect(outcome == .noSpeech)
        #expect(transcriber.callCount == 0)
    }

    @Test func emptyTranscriptIsNoSpeech() async {
        let (sut, _, transcriber, paste, clock, _) = makeSUT()
        transcriber.result = "   " // cleans to ""
        var outcome: DictationOutcome?
        sut.onCompleted = { outcome = $0 }

        sut.pressed()
        clock.ticksMs = 500
        await sut.released()

        #expect(outcome == .noSpeech)
        #expect(paste.pasted.isEmpty)
    }

    @Test func blockedPasteLeavesTextOnClipboard() async {
        let (sut, _, _, paste, clock, _) = makeSUT()
        paste.outcome = .leftOnClipboard
        var outcome: DictationOutcome?
        sut.onCompleted = { outcome = $0 }

        sut.pressed()
        clock.ticksMs = 500
        await sut.released()

        #expect(outcome == .leftOnClipboard)
        #expect(paste.pasted.count == 1)
    }

    @Test func autoStopRunsTheCycle() async {
        let (sut, _, transcriber, _, clock, _) = makeSUT()
        var outcome: DictationOutcome?
        sut.onCompleted = { outcome = $0 }

        clock.ticksMs = 0
        sut.pressed()
        clock.ticksMs = 60_000
        await sut.autoStopFired()

        #expect(outcome == .pasted)
        #expect(transcriber.callCount == 1)
        #expect(sut.currentState == .idle)
    }

    @Test func releasedWhenNotRecordingIsNoop() async {
        let (sut, audio, _, _, _, _) = makeSUT()
        await sut.released() // idle — lost the race / never pressed
        #expect(audio.stopCount == 0)
        #expect(sut.currentState == .idle)
    }

    @Test func emitsStateSequenceForANormalCycle() async {
        let (sut, _, _, _, clock, _) = makeSUT()
        var states: [DictationState] = []
        sut.onStateChanged = { states.append($0) }

        sut.pressed()
        clock.ticksMs = 500
        await sut.released()

        #expect(states == [.recording, .transcribing, .pasting, .idle])
    }
}
