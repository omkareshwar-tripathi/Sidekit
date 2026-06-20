import Foundation
import SidekitCore

/// Task.sleep-backed one-shot idle timer (spec §5: warm → unload after the idle window).
final class SystemIntelligenceIdleTimer: IntelligenceIdleTimer {
    private var task: Task<Void, Never>?

    func start(after seconds: Double, _ fire: @escaping @Sendable () -> Void) {
        cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            fire()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// System memory pressure → the session's guest-leaves-now rule (spec §5).
@MainActor
final class MemoryPressureSource {
    private let source: DispatchSourceMemoryPressure

    init(onPressure: @escaping @MainActor () -> Void) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical],
                                                         queue: .main)
        source.setEventHandler {
            Diag.log("intelligence: memory pressure")
            MainActor.assumeIsolated { onPressure() }
        }
        source.activate()
    }
}
