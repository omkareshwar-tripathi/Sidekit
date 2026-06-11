import Foundation

/// System clipboard + paste primitives the clipboard-safe flow depends on (the native
/// `NSPasteboard` + `CGEvent` ⌘V adapter implements this in the app target).
public protocol SystemClipboard: AnyObject {
    /// Current clipboard text, or nil if it holds no text.
    func getText() -> String?
    /// Replace the clipboard contents with `text`.
    func setText(_ text: String)
    /// Empty the clipboard (used to restore when the original held no text).
    func clear()
    /// Synthesize ⌘V into the focused app. Returns false if the OS blocked the keystroke,
    /// so the caller can leave the text on the clipboard rather than restore over it.
    func sendPaste() -> Bool
}

/// Clipboard-safe paste — a port of the C# `ClipboardPasteService`. Saves the current
/// clipboard text, sets ours (so the user's words are never lost), synthesizes ⌘V, waits
/// briefly so the target app can read the clipboard, then restores the original. If the
/// keystroke is blocked, leaves our text on the clipboard and restores nothing.
public final class ClipboardSafePaste: Pasting {
    // Gives the target app time to read the clipboard after ⌘V before we restore.
    private static let restoreDelay: Duration = .milliseconds(150)

    private let clipboard: SystemClipboard
    private let sleep: (Duration) -> Void

    /// - Parameter sleep: injected so tests don't actually wait. NOTE: the default blocks
    ///   the calling thread; the coordinator runs paste on the main actor, so a real paste
    ///   briefly (~150 ms) pauses the menu bar. Acceptable for the MVP; offload later if perceptible.
    public init(clipboard: SystemClipboard, sleep: @escaping (Duration) -> Void = ClipboardSafePaste.threadSleep) {
        self.clipboard = clipboard
        self.sleep = sleep
    }

    public func paste(_ text: String) -> PasteOutcome {
        let original = clipboard.getText() // save first
        clipboard.setText(text)            // set ours (kept on clipboard in both branches)

        guard clipboard.sendPaste() else {
            // OS blocked the keystroke — leave our text rather than restore over it.
            return .leftOnClipboard
        }

        sleep(Self.restoreDelay)

        if let original {
            clipboard.setText(original)
        } else {
            clipboard.clear()
        }
        return .pasted
    }

    /// Default blocking sleep (public so it can serve as the init's default argument).
    public static func threadSleep(_ duration: Duration) {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        Thread.sleep(forTimeInterval: seconds)
    }
}
