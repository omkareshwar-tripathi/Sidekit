import Foundation

/// Generates text with an on-device model. `load()` is idempotent; `unload()` frees the
/// weights (the RAM-guest rule, spec §5). Generation honors task cancellation.
public protocol TextGenerating: Sendable {
    func load() async throws
    func unload() async
    func generate(system: String, user: String, temperature: Float) async throws -> String
}

/// Owns the model files on disk (download / presence / removal — spec §6). Detached from
/// loading so download consent, progress, and Settings-removal stay explicit.
public protocol ModelProvisioning: Sendable {
    var isDownloaded: Bool { get }
    func download(progress: @escaping @Sendable (Double) -> Void) async throws
    func remove() throws
}

/// One-shot idle timer for the unload window. `start` replaces any pending timer.
public protocol IntelligenceIdleTimer: AnyObject {
    func start(after seconds: Double, _ fire: @escaping @Sendable () -> Void)
    func cancel()
}
