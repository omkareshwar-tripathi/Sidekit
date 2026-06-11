import Testing
@testable import SidekitCore

struct ScreenshotGateTests {
    private func gate(capacity: Int = 32) -> ScreenshotGate {
        ScreenshotGate(payloadRootPath: "/Users/o/Library/Application Support/Sidekit/Shelf",
                       capacity: capacity)
    }

    @Test func admitsANewScreenshotExactlyOnce() {
        var g = gate()
        #expect(g.admit("/Users/o/Desktop/Screenshot 1.png") == true)
        #expect(g.admit("/Users/o/Desktop/Screenshot 1.png") == false)
    }

    @Test func refusesHiddenFleetingFiles() {
        var g = gate()
        #expect(g.admit("/Users/o/Desktop/.Screenshot 1.png") == false)
    }

    @Test func refusesOurOwnPayloadCopies() {
        var g = gate()
        let stored = "/Users/o/Library/Application Support/Sidekit/Shelf/u1/Screenshot 1.png"
        #expect(g.admit(stored) == false)
    }

    @Test func payloadRootMatchIsPrefixSafe() {
        // A sibling like …/ShelfOther must not match …/Shelf (same rule as the payload store).
        var g = gate()
        #expect(g.admit("/Users/o/Library/Application Support/Sidekit/ShelfOther/x.png") == true)
    }

    @Test func capacityEvictsOldestFirstSoItCanLandAgain() {
        var g = gate(capacity: 2)
        #expect(g.admit("/d/a.png") == true)
        #expect(g.admit("/d/b.png") == true)
        #expect(g.admit("/d/c.png") == true)  // evicts a.png from memory
        #expect(g.admit("/d/a.png") == true)  // forgotten → admissible again
        #expect(g.admit("/d/c.png") == false) // still remembered
    }
}
