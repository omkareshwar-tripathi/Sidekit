import Testing
import Foundation
@testable import AudiobookCore

struct PortsTests {
    @Test func fakeAudioRecordsCalls() {
        let a = FakeAudioOutput()
        a.load("x.caf"); a.play(); a.setRate(1.5); a.seek(to: 42); a.pause()
        #expect(a.loaded == "x.caf")
        #expect(a.playCount == 1 && a.pauseCount == 1)
        #expect(a.rate == 1.5)
        #expect(a.seekedTo == 42)
    }

    @Test func fakeClockOnlyTicksWhileRunning() {
        let c = FakeClock()
        var total = 0.0
        c.tick(1)                         // not started → ignored
        c.start { total += $0 }
        c.tick(1); c.tick(2)              // running → 3
        c.stop()
        c.tick(5)                         // stopped → ignored
        #expect(total == 3)
    }
}
