/// A `DictationSink` decorator that logs every delivered transcript to the dictation trail. It
/// forwards `deliver` to an inner sink, records the text plus the inner sink's outcome via an
/// injected closure, then returns that outcome unchanged. The recording is a closure (not a
/// store reference) so the wiring stays testable with no app types — mirrors `RoutingSink`'s style.
///
/// No-speech cycles never reach a sink (the coordinator short-circuits them), so only real
/// dictations are logged — which is the intended behavior.
public final class HistoryRecordingSink: DictationSink {
    private let inner: DictationSink
    private let record: (String, DictationOutcome) -> Void

    public init(inner: DictationSink, record: @escaping (String, DictationOutcome) -> Void) {
        self.inner = inner
        self.record = record
    }

    public func deliver(_ text: String) -> DictationOutcome {
        let outcome = inner.deliver(text)
        record(text, outcome)
        return outcome
    }
}
