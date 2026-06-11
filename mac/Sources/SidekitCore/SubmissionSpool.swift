import Foundation

/// How one send attempt ended, as classified by the network adapter:
/// `.sent` — accepted (2xx, or 409 duplicate-signup);
/// `.retryable` — transient (offline, timeout, 5xx, unconfigured build) — keep queued;
/// `.rejected` — the backend refused it (other 4xx) — a strike toward dropping it.
public enum SendResult: Sendable, Equatable {
    case sent, retryable, rejected
}

/// The one network port. The adapter (SidekitNet's Supabase sender) is a dumb pipe:
/// the submission already knows its table and body.
public protocol SubmissionSending: Sendable {
    func send(_ submission: RemoteSubmission) async -> SendResult
}

/// One queued outbound write, persisted so it survives quit/offline (spec §6).
public struct SpooledSubmission: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var submission: RemoteSubmission
    /// Times the backend rejected it (4xx). At 3, the entry is dropped as poison.
    public var rejections: Int

    public init(id: UUID = UUID(), submission: RemoteSubmission, rejections: Int = 0) {
        self.id = id
        self.submission = submission
        self.rejections = rejections
    }
}

/// Loads and saves the outbox; the adapter backs this with outbox.json.
public protocol SpoolPersisting: Sendable {
    func load() -> [SpooledSubmission]
    func save(_ entries: [SpooledSubmission])
}

/// A tiny persistent outbox (spec §5/§6): every submission is saved first, then sent.
/// Failures stay queued for the next launch; UI never blocks or shows network errors.
@MainActor
public final class SubmissionSpool {
    /// Outbox bound — the oldest entry is evicted past this, so it can never grow unbounded.
    public static let capacity = 50
    /// Rejection strikes before a poison entry is dropped (spec §6).
    public static let maxRejections = 3

    public private(set) var pending: [SpooledSubmission]
    private let persistence: SpoolPersisting
    private let sender: SubmissionSending
    /// Sink for rare diagnostics (the poison drop). The app wires this to `Diag.log`;
    /// the default is silent. Main-actor because the spool only calls it from its walk.
    private let log: @MainActor (String) -> Void
    /// The one in-flight queue walk, if any. Entries enqueued during a walk land behind
    /// its cursor and are processed by that same walk; `flush()` awaits it, so callers
    /// always observe their entry's real disposition (drives an honest toast).
    private var flushTask: Task<Void, Never>?

    public init(persistence: SpoolPersisting, sender: SubmissionSending,
                log: @escaping @MainActor (String) -> Void = { _ in }) {
        self.persistence = persistence
        self.sender = sender
        self.log = log
        self.pending = persistence.load()
    }

    /// Queue-then-send. Returns true when the submission went out right now (drives the
    /// "Thanks!" vs "Saved — will send when you're online" toast).
    @discardableResult
    public func enqueue(_ submission: RemoteSubmission) async -> Bool {
        if pending.count >= Self.capacity { pending.removeFirst() }
        let entry = SpooledSubmission(submission: submission)
        pending.append(entry)
        persistence.save(pending)
        await flush()
        return !pending.contains { $0.id == entry.id }
    }

    /// Re-attempt everything still queued. Called once at every app launch.
    public func retryAll() async {
        await flush()
    }

    /// Ensure a walk is running and wait for it to finish.
    private func flush() async {
        if let task = flushTask {
            await task.value // the running walk will reach entries appended behind it
            return
        }
        let task = Task {
            await self.walk()
            // Cleared inside the task: no window where a finished walk looks in-flight.
            self.flushTask = nil
        }
        flushTask = task
        await task.value
    }

    /// Walk the queue once, by entry id (entries can be added/removed across awaits).
    private func walk() async {
        var index = 0
        while index < pending.count {
            let entry = pending[index]
            switch await sender.send(entry.submission) {
            case .sent:
                pending.removeAll { $0.id == entry.id }
            case .retryable:
                if let i = pending.firstIndex(where: { $0.id == entry.id }) { index = i + 1 }
            case .rejected:
                if let i = pending.firstIndex(where: { $0.id == entry.id }) {
                    pending[i].rejections += 1
                    if pending[i].rejections >= Self.maxRejections {
                        log("spool: dropping \(entry.submission.table) entry after \(Self.maxRejections) rejections (spec §6 poison rule)")
                        pending.remove(at: i)
                    } else {
                        index = i + 1
                    }
                }
            }
            persistence.save(pending)
        }
    }
}

/// Bytes ⇄ outbox, tolerant like the other codecs: corrupt/empty → empty queue.
public enum SpoolCodec {
    public static func encode(_ entries: [SpooledSubmission]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(entries)) ?? Data("[]".utf8)
    }

    public static func decode(_ data: Data) -> [SpooledSubmission] {
        (try? JSONDecoder().decode([SpooledSubmission].self, from: data)) ?? []
    }
}
