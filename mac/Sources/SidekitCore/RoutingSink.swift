/// Decides where a finished, cleaned transcript goes (spec §3): if Sidekit is the focused app,
/// the text is **appended to the active note**; otherwise it falls back to the paste-at-cursor
/// sink, exactly as before. The focus check and the note-append are injected closures, so the
/// routing decision is unit-testable with no AppKit and no real notes store.
public final class RoutingSink: DictationSink {
    private let isAppFocused: () -> Bool
    private let appendToNote: (String) -> Void
    private let pasteSink: DictationSink

    public init(isAppFocused: @escaping () -> Bool,
                appendToNote: @escaping (String) -> Void,
                pasteSink: DictationSink) {
        self.isAppFocused = isAppFocused
        self.appendToNote = appendToNote
        self.pasteSink = pasteSink
    }

    public func deliver(_ text: String) -> DictationOutcome {
        guard isAppFocused() else { return pasteSink.deliver(text) }
        appendToNote(text)
        return .addedToNote
    }
}
