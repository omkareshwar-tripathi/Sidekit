import Foundation

/// The RAM-guest state machine (spec 2026-06-12 §5): a model loads on demand, stays warm
/// for an idle window, then unloads — never resident. Two role-specific engines (spec §1:
/// Gemma polishes, Qwen drafts) but only ONE is ever warm — switching roles unloads the
/// other first. Pure over the ports; the UI mirrors `state` + the result/error callbacks.
/// @MainActor like the app models it feeds; engine work runs off-main behind the async port.
/// Owned for the app's lifetime by the Intelligence feature — not designed to be created
/// per-use (dropping the only reference mid-cycle would strand a loaded engine until
/// memory pressure evicts it).
@MainActor
public final class IntelligenceSession {
    public enum State: Equatable, Sendable {
        case needsModel
        case downloading(Double)
        case ready       // downloaded, no weights in RAM
        case loading
        case warm        // one model's weights in RAM, idle
        case generating
    }

    public private(set) var state: State {
        didSet { if state != oldValue { onStateChanged?(state) } }
    }
    public var onStateChanged: ((State) -> Void)?
    public var onResult: ((String) -> Void)?
    public var onError: ((String) -> Void)?

    private let polishEngine: any TextGenerating
    private let draftEngine: any TextGenerating
    private let provisioner: any ModelProvisioning
    private let idle: any IntelligenceIdleTimer
    private let idleSeconds: Double
    /// Which engine is warm; nil ↔ state ready/needsModel.
    private var warmRole: IntelligenceRole?
    private var generationTask: Task<Void, Never>?
    private var housekeepingTask: Task<Void, Never>?

    public init(polishEngine: any TextGenerating,
                draftEngine: any TextGenerating,
                provisioner: any ModelProvisioning,
                idle: any IntelligenceIdleTimer,
                idleSeconds: Double = 180) {
        self.polishEngine = polishEngine
        self.draftEngine = draftEngine
        self.provisioner = provisioner
        self.idle = idle
        self.idleSeconds = idleSeconds
        self.state = provisioner.isDownloaded ? .ready : .needsModel
    }

    private func engine(for role: IntelligenceRole) -> any TextGenerating {
        role == .polish ? polishEngine : draftEngine
    }

    /// One-time download of BOTH models (spec §6). Returns the task so callers/tests can await it.
    @discardableResult
    public func requestDownload() -> Task<Void, Never>? {
        guard state == .needsModel else { return nil }
        state = .downloading(0.0)
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.provisioner.download { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(fraction)
                    }
                }
                self.state = .ready
            } catch {
                self.state = .needsModel
                // Spec §6 distinguishes plain offline from an interrupted/failed download.
                let offline = (error as? URLError)?.code == .notConnectedToInternet
                self.onError?(offline
                    ? "You're offline — the one-time model download needs internet."
                    : "Download interrupted — Retry")
            }
        }
        generationTask = task
        return task
    }

    /// Run one chip (spec §3/§5): validate → swap/load the chip's model if needed →
    /// generate → sanitize → deliver. Returns the task so callers/tests can await it.
    @discardableResult
    public func run(chip: IntelligenceChip, tone: IntelligenceTone, input: String) -> Task<Void, Never>? {
        guard state == .ready || state == .warm else { return nil }
        let text: String
        switch IntelligencePrompt.check(input) {
        case .empty: return nil
        case .tooLong: onError?(IntelligencePrompt.tooLongMessage); return nil
        case .ok(let trimmed): text = trimmed
        }
        idle.cancel()
        let role = chip.role
        let prompt = IntelligencePrompt.build(chip: chip, tone: tone)
        let task = Task { [weak self] in
            guard let self else { return }
            if let warm = self.warmRole, warm != role {
                // Role switch: the warm model leaves before the other arrives (spec §5).
                self.state = .loading
                self.warmRole = nil
                await self.engine(for: warm).unload()
            }
            if self.warmRole == nil {
                self.state = .loading
                do {
                    try await self.engine(for: role).load()
                    self.warmRole = role
                } catch {
                    self.state = .ready
                    self.onError?("Model files look damaged — download again.")
                    return
                }
            }
            self.state = .generating
            do {
                let raw = try await self.engine(for: role).generate(
                    system: prompt.system, user: text, temperature: prompt.temperature)
                let clean = IntelligencePrompt.sanitize(raw)
                self.state = .warm
                if clean.isEmpty { self.onError?("Couldn't draft that — try again.") }
                else { self.onResult?(clean) }
            } catch is CancellationError {
                // The user (or memory pressure) asked to stop. If pressure already evicted
                // the model, keep the state it set; otherwise stay warm, silently.
                if self.warmRole != nil { self.state = .warm }
            } catch {
                self.state = .warm
                self.onError?("Couldn't draft that — try again.")
            }
            if self.warmRole != nil { self.scheduleIdleUnload() }
        }
        generationTask = task
        return task
    }

    /// Stop the in-flight generation; the warm model stays warm (spec §5).
    public func cancelGeneration() { generationTask?.cancel() }

    /// System memory pressure: the guest leaves immediately (spec §5).
    public func memoryPressure() {
        switch state {
        case .warm:
            unloadNow(to: .ready)
        case .generating:
            generationTask?.cancel()
            onError?("Paused to free memory — try again in a moment.")
            unloadNow(to: .ready)
        default: break
        }
    }

    /// Settings removed the model files (spec §6).
    public func modelRemoved() {
        idle.cancel()
        unloadNow(to: .needsModel)
    }

    /// Await all in-flight internal work — for tests.
    /// Yields once so any main-actor Tasks enqueued by an idle-timer fire (or other
    /// synchronous triggers) get to run and set housekeepingTask before we await it.
    public func settle() async {
        await Task.yield()
        await generationTask?.value
        await housekeepingTask?.value
    }

    private func scheduleIdleUnload() {
        idle.start(after: idleSeconds) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.state == .warm else { return }
                self.unloadNow(to: .ready)
            }
        }
    }

    private func unloadNow(to target: State) {
        let warm = warmRole
        warmRole = nil
        state = target
        housekeepingTask = Task { [polishEngine, draftEngine] in
            switch warm {
            case .polish: await polishEngine.unload()
            case .draft: await draftEngine.unload()
            case nil:    // belt & braces (e.g. modelRemoved while nothing is warm)
                await polishEngine.unload()
                await draftEngine.unload()
            }
        }
    }
}
