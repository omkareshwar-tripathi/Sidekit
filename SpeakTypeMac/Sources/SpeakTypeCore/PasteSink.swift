/// The default `DictationSink`: pastes the transcript at the cursor in the frontmost app
/// (the original behavior), mapping the paste result onto a `DictationOutcome`. The routing
/// sink that prefers an in-app note (UI-9) wraps this for the "not focused on us" case.
public final class PasteSink: DictationSink {
    private let paste: Pasting

    public init(paste: Pasting) {
        self.paste = paste
    }

    public func deliver(_ text: String) -> DictationOutcome {
        switch paste.paste(text) {
        case .pasted: return .pasted
        case .leftOnClipboard: return .leftOnClipboard
        }
    }
}
