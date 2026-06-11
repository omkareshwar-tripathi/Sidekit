/// User-configurable settings for the dictation pipeline. Minimal for the MVP — the
/// hotkey is hard-coded (hold Fn) and the model is WhisperKit's default, so the only knob
/// the coordinator reads today is filler removal. Persistence and a settings UI are later
/// bricks.
public struct Settings: Sendable, Equatable {
    /// Strip disfluencies / discourse markers from the transcript before pasting.
    public var fillerRemoval: Bool

    public init(fillerRemoval: Bool = true) {
        self.fillerRemoval = fillerRemoval
    }
}
