import AppKit
import ApplicationServices
import SidekitCore

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
        let trusted = AXIsProcessTrusted()
        guard trusted else { Diag.log("paste: not trusted → leave on clipboard"); return false }
        // Only synthesize ⌘V when an editable field is actually focused. macOS can't tell us whether
        // a paste landed, so without this we'd report "Pasted" even when the keystroke goes nowhere.
        // No editable target → return false so the caller leaves the text on the clipboard ("Copied…").
        guard hasEditableFocus() else { Diag.log("paste: no editable focus → leave on clipboard"); return false }
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

    /// True when the system-wide focused UI element looks editable — its `AXValue` is settable, or its
    /// role is a known text role. Lets `sendPaste` avoid a no-op ⌘V into a non-text target (Finder,
    /// desktop, a button), so the user gets an honest "Copied to clipboard" instead of a false "Pasted".
    private func hasEditableFocus() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return false }
        let axElement = element as! AXUIElement

        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(axElement, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }
        var role: AnyObject?
        if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role) == .success,
           let roleStr = role as? String {
            return roleStr == (kAXTextFieldRole as String)
                || roleStr == (kAXTextAreaRole as String)
                || roleStr == (kAXComboBoxRole as String)
        }
        return false
    }
}
