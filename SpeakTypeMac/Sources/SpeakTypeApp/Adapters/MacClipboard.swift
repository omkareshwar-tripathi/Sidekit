import AppKit
import ApplicationServices
import SpeakTypeCore

/// `SystemClipboard` adapter: `NSPasteboard` for text, and a synthesized ⌘V keystroke via
/// `CGEvent` for paste. The ⌘V needs the Accessibility permission — if it isn't granted,
/// `sendPaste()` returns false so the clipboard-safe flow leaves the text for a manual paste
/// rather than silently dropping the user's words.
final class MacClipboard: SystemClipboard {
    private let pasteboard = NSPasteboard.general
    private static let vKeyCode: CGKeyCode = 0x09 // 'v'

    func getText() -> String? { pasteboard.string(forType: .string) }

    func setText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func clear() { pasteboard.clearContents() }

    func sendPaste() -> Bool {
        guard AXIsProcessTrusted() else { return false } // no Accessibility → keystroke can't land
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
