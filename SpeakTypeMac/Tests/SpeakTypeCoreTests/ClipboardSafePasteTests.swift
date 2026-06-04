import Testing
@testable import SpeakTypeCore

// Records every clipboard op (and the injected delay) in order, so tests can assert the
// save→set→paste→delay→restore sequence. Ported from the C# ClipboardPasteServiceTests.
final class FakeClipboard: SystemClipboard {
    var ops: [String] = []
    var currentText: String?
    var pasteSucceeds = true

    func getText() -> String? { ops.append("GetText"); return currentText }
    func setText(_ text: String) { ops.append("SetText:\(text)") }
    func clear() { ops.append("Clear") }
    func sendPaste() -> Bool { ops.append("SendPaste"); return pasteSucceeds }
}

struct ClipboardSafePasteTests {
    // No-op delay that logs its ordering.
    private func makeSUT(_ clip: FakeClipboard) -> ClipboardSafePaste {
        ClipboardSafePaste(clipboard: clip, sleep: { _ in clip.ops.append("Delay") })
    }

    @Test func successfulPasteRunsFullSequenceInOrder() {
        let clip = FakeClipboard()
        clip.currentText = "ORIGINAL"

        let outcome = makeSUT(clip).paste("OURTEXT")

        #expect(outcome == .pasted)
        #expect(clip.ops == ["GetText", "SetText:OURTEXT", "SendPaste", "Delay", "SetText:ORIGINAL"])
    }

    @Test func restoreHappensAfterTheDelay() {
        let clip = FakeClipboard()
        clip.currentText = "ORIGINAL"

        _ = makeSUT(clip).paste("OURTEXT")

        let paste = clip.ops.firstIndex(of: "SendPaste")!
        let delay = clip.ops.firstIndex(of: "Delay")!
        let restore = clip.ops.firstIndex(of: "SetText:ORIGINAL")!
        #expect(paste < delay && delay < restore)
    }

    @Test func originalWasNilClearsOnRestore() {
        let clip = FakeClipboard()
        clip.currentText = nil

        let outcome = makeSUT(clip).paste("OURTEXT")

        #expect(outcome == .pasted)
        #expect(clip.ops.last == "Clear")                                   // restore empties, not re-sets
        #expect(clip.ops.filter { $0.hasPrefix("SetText:") }.count == 1)    // only our text was set
    }

    @Test func blockedPasteLeavesOurTextOnClipboard() {
        let clip = FakeClipboard()
        clip.currentText = "ORIGINAL"
        clip.pasteSucceeds = false // OS blocked the keystroke

        let outcome = makeSUT(clip).paste("OURTEXT")

        #expect(outcome == .leftOnClipboard)
        #expect(clip.ops.contains("SetText:OURTEXT"))    // our words still safe on the clipboard
        #expect(!clip.ops.contains("Delay"))
        #expect(!clip.ops.contains("SetText:ORIGINAL"))  // never restored over our text
        #expect(!clip.ops.contains("Clear"))
    }
}
