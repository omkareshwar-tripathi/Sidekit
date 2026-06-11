# Sign-up Soft Gate + Dictation-First Feedback — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the spec `docs/superpowers/specs/2026-06-11-sidekit-signup-feedback-design.md` — a skippable email welcome sheet, a one-box dictation-first feedback window, and a Supabase insert-only backend with an offline retry spool.

**Architecture:** Ports-and-adapters, matching the repo. Pure tested core in `SidekitCore` (identity state + welcome rule, submission payloads, retry spool). A new small library target `SidekitNet` holds the one network adapter (`SupabaseSubmissionSender`) so a `SubmissionSelftest` dev executable can verify it headlessly against a local stand-in server (same precedent as `ModelSelftest`). `SidekitApp` adds JSON persistence adapters, the welcome sheet, the feedback box window, and wiring.

**Tech Stack:** Swift 6 / SwiftPM, swift-testing (`@Test` / `#expect`), SwiftUI + AppKit `NSPanel`, `URLSession`, Supabase REST (PostgREST).

**Conventions (from the codebase — follow them):**
- Core stores: `@MainActor public final class` + a `…Persisting` port; codecs are pure `enum` with tolerant decode (corrupt → fresh).
- Adapters: mirror `JSONHistoryStore` (atomic write, one retry, `Diag.log` on failure).
- Tests: `@MainActor struct XTests` with `makeSUT` helpers; fakes appended to `Tests/SidekitCoreTests/Fakes.swift`.
- All commands run from `mac/`. Full suite: `swift test` (currently 60 passing).
- Domain `Skill:` lines are `none` (Swift — the dotnet skills don't apply, per CLAUDE.md §6).

---

## Task 1 (SHIP-1): Identity core — state, welcome rule, email check, codec

`Skill:` none (domain) · superpowers:test-driven-development

**Files:**
- Create: `mac/Sources/SidekitCore/Identity.swift`
- Create: `mac/Tests/SidekitCoreTests/IdentityTests.swift`
- Modify: `mac/Tests/SidekitCoreTests/Fakes.swift` (append `FakeIdentityPersistence`)

- [ ] **Step 1: Write the failing tests**

Append to `Fakes.swift`:

```swift
/// In-memory IdentityPersisting: seeds the store on load and records what it saved.
final class FakeIdentityPersistence: IdentityPersisting, @unchecked Sendable {
    var stored: IdentityState
    private(set) var saveCount = 0
    init(_ initial: IdentityState = IdentityState()) { stored = initial }
    func load() -> IdentityState { stored }
    func save(_ state: IdentityState) { saveCount += 1; stored = state }
}
```

Create `IdentityTests.swift`:

```swift
import Testing
import Foundation
@testable import SidekitCore

@MainActor
struct IdentityTests {

    private func makeSUT(seed: IdentityState = IdentityState()) -> (IdentityStore, FakeIdentityPersistence) {
        let persistence = FakeIdentityPersistence(seed)
        return (IdentityStore(persistence: persistence), persistence)
    }

    // MARK: - EmailCheck

    @Test func plausibleEmailsPass() {
        #expect(EmailCheck.isPlausible("a@b.co"))
        #expect(EmailCheck.isPlausible("  user.name+tag@sub.example.com  ")) // trimmed
    }

    @Test func implausibleEmailsFail() {
        #expect(!EmailCheck.isPlausible(""))
        #expect(!EmailCheck.isPlausible("plainaddress"))
        #expect(!EmailCheck.isPlausible("a@b"))            // no dot in domain
        #expect(!EmailCheck.isPlausible("@b.co"))          // empty local part
        #expect(!EmailCheck.isPlausible("a@.co"))          // empty domain label
        #expect(!EmailCheck.isPlausible("a@b."))           // empty trailing label
        #expect(!EmailCheck.isPlausible("a b@c.do"))       // inner whitespace
        #expect(!EmailCheck.isPlausible("a@@b.co"))        // two @
    }

    // MARK: - Soft-gate welcome rule (spec §2): show on launch 1; if skipped, once more at launch ≥5; never after.

    @Test func welcomeLifecycleAcrossLaunches() {
        let (store, _) = makeSUT()
        store.recordLaunch()                       // launch 1
        #expect(store.shouldShowWelcome)
        store.welcomeShown()                       // shown, user skipped
        #expect(!store.shouldShowWelcome)          // not again this session
        store.recordLaunch()                       // 2
        store.recordLaunch()                       // 3
        store.recordLaunch()                       // 4
        #expect(!store.shouldShowWelcome)
        store.recordLaunch()                       // 5 — the one re-ask
        #expect(store.shouldShowWelcome)
        store.welcomeShown()
        store.recordLaunch()                       // 6+ — never again
        #expect(!store.shouldShowWelcome)
    }

    @Test func welcomeNeverShowsOnceEmailIsSet() {
        let (store, _) = makeSUT()
        store.recordLaunch()
        #expect(store.setEmail("you@example.com"))
        #expect(!store.shouldShowWelcome)
        store.recordLaunch() // any later launch
        #expect(!store.shouldShowWelcome)
    }

    @Test func ruleSurvivesPersistenceRoundTrip() {
        let (first, persistence) = makeSUT()
        first.recordLaunch()        // 1
        first.welcomeShown()        // skipped
        // "Relaunch": a fresh store loads the saved state.
        let (second, _) = makeSUT(seed: persistence.stored)
        second.recordLaunch()       // 2
        #expect(!second.shouldShowWelcome)
    }

    // MARK: - setEmail / clearEmail

    @Test func setEmailTrimsLowercasesAndPersists() {
        let (store, persistence) = makeSUT()
        #expect(store.setEmail("  You@Example.COM "))
        #expect(store.state.email == "you@example.com")
        #expect(persistence.stored.email == "you@example.com")
    }

    @Test func setEmailRejectsImplausibleWithoutSaving() {
        let (store, persistence) = makeSUT()
        #expect(!store.setEmail("nope"))
        #expect(store.state.email == nil)
        #expect(persistence.saveCount == 0)
    }

    @Test func clearEmailRemovesAndPersists() {
        let (store, persistence) = makeSUT(seed: IdentityState(email: "a@b.co"))
        store.clearEmail()
        #expect(store.state.email == nil)
        #expect(persistence.stored.email == nil)
    }

    // MARK: - Codec

    @Test func codecRoundTrips() {
        let state = IdentityState(email: "a@b.co", launchCount: 7, welcomeAutoShows: 2)
        #expect(IdentityCodec.decode(IdentityCodec.encode(state)) == state)
    }

    @Test func codecToleratesCorruptData() {
        #expect(IdentityCodec.decode(Data("not json".utf8)) == IdentityState())
        #expect(IdentityCodec.decode(Data()) == IdentityState())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mac && swift test --filter IdentityTests`
Expected: compile FAILURE — `IdentityState` / `IdentityStore` / `EmailCheck` / `IdentityCodec` not defined.

- [ ] **Step 3: Write the implementation**

Create `mac/Sources/SidekitCore/Identity.swift`:

```swift
import Foundation

/// Who this install belongs to, and where the soft-gate welcome stands (spec §2,
/// 2026-06-11 sign-up + feedback design). One small value persisted as identity.json.
public struct IdentityState: Sendable, Equatable, Codable {
    /// Normalized (trimmed, lowercased) sign-up email; nil until the user provides one.
    public var email: String?
    /// Total launches recorded (drives the 5th-launch re-ask).
    public var launchCount: Int
    /// How many times the welcome sheet auto-appeared (lifetime cap: 2).
    public var welcomeAutoShows: Int

    public init(email: String? = nil, launchCount: Int = 0, welcomeAutoShows: Int = 0) {
        self.email = email
        self.launchCount = launchCount
        self.welcomeAutoShows = welcomeAutoShows
    }
}

/// The "looks like an email" check (spec §2): one @, non-empty local part, dotted domain
/// with non-empty labels, no whitespace. Deliberately minimal — there is no verification.
public enum EmailCheck {
    public static func isPlausible(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return false }
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { !$0.isEmpty }
    }
}

/// Loads and saves the identity state. The store calls `load()` once at init and
/// `save(_:)` after every mutation; the adapter backs this with identity.json.
public protocol IdentityPersisting: Sendable {
    func load() -> IdentityState
    func save(_ state: IdentityState)
}

/// Owns the identity state and the soft-gate rule: the welcome sheet auto-shows on the
/// first launch; if skipped, once more on the 5th-or-later launch; never a third time,
/// and never once an email is set.
@MainActor
public final class IdentityStore {
    public private(set) var state: IdentityState
    private let persistence: IdentityPersisting

    public init(persistence: IdentityPersisting) {
        self.persistence = persistence
        self.state = persistence.load()
    }

    /// Call exactly once per app launch, before reading `shouldShowWelcome`.
    public func recordLaunch() {
        state.launchCount += 1
        persistence.save(state)
    }

    public var shouldShowWelcome: Bool {
        guard state.email == nil else { return false }
        if state.welcomeAutoShows == 0 { return true }
        return state.welcomeAutoShows == 1 && state.launchCount >= 5
    }

    /// Call when the sheet actually appears (counts toward the lifetime cap of 2).
    public func welcomeShown() {
        state.welcomeAutoShows += 1
        persistence.save(state)
    }

    /// Normalize and store a plausible email; returns false (no save) otherwise.
    @discardableResult
    public func setEmail(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard EmailCheck.isPlausible(normalized) else { return false }
        state.email = normalized
        persistence.save(state)
        return true
    }

    /// Local-only removal (spec §2: no delete call to the backend).
    public func clearEmail() {
        state.email = nil
        persistence.save(state)
    }
}

/// Bytes ⇄ IdentityState, tolerant like the other codecs: corrupt/empty → fresh state.
public enum IdentityCodec {
    public static func encode(_ state: IdentityState) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(state)) ?? Data("{}".utf8)
    }

    public static func decode(_ data: Data) -> IdentityState {
        (try? JSONDecoder().decode(IdentityState.self, from: data)) ?? IdentityState()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mac && swift test --filter IdentityTests`
Expected: PASS (10 tests). Then `swift test` — full suite green, no regressions.

- [ ] **Step 5: Commit**

```bash
git add mac/Sources/SidekitCore/Identity.swift mac/Tests/SidekitCoreTests/IdentityTests.swift mac/Tests/SidekitCoreTests/Fakes.swift
git commit -m "feat(mac): identity core — soft-gate welcome rule, email check, codec (SHIP-1)"
```

---

## Task 2 (SHIP-2): Submission payloads — kinds, JSON bodies, validation

`Skill:` none (domain) · superpowers:test-driven-development

**Files:**
- Create: `mac/Sources/SidekitCore/RemoteSubmission.swift`
- Create: `mac/Tests/SidekitCoreTests/RemoteSubmissionTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `RemoteSubmissionTests.swift`:

```swift
import Testing
import Foundation
@testable import SidekitCore

struct RemoteSubmissionTests {

    @Test func signupTargetsSignupsTableWithExpectedBody() throws {
        let s = RemoteSubmission.signup(email: "a@b.co", appVersion: "1.0 (12)")
        #expect(s.table == "signups")
        let object = try #require(JSONSerialization.jsonObject(with: s.jsonBody()) as? [String: String])
        #expect(object == ["email": "a@b.co", "app_version": "1.0 (12)", "platform": "mac"])
    }

    @Test func feedbackTargetsFeedbackTableWithExpectedBody() throws {
        let s = RemoteSubmission.feedback(kind: .bug, message: "it broke", email: "a@b.co",
                                          appVersion: "1.0 (12)", osVersion: "macOS 15.5.0")
        #expect(s.table == "feedback")
        let object = try #require(JSONSerialization.jsonObject(with: s.jsonBody()) as? [String: String])
        #expect(object == ["type": "bug", "message": "it broke", "email": "a@b.co",
                           "app_version": "1.0 (12)", "os_version": "macOS 15.5.0"])
    }

    @Test func anonymousFeedbackOmitsEmailKey() throws {
        let s = RemoteSubmission.feedback(kind: .other, message: "hi", email: nil,
                                          appVersion: "1.0", osVersion: "macOS 15.5.0")
        let object = try #require(JSONSerialization.jsonObject(with: s.jsonBody()) as? [String: String])
        #expect(object["email"] == nil)
        #expect(object["type"] == "other")
    }

    @Test func feedbackMessageValidationTrimsAndBounds() {
        #expect(RemoteSubmission.validateFeedbackMessage("  hello \n") == "hello")
        #expect(RemoteSubmission.validateFeedbackMessage("   \n ") == nil)        // blank
        #expect(RemoteSubmission.validateFeedbackMessage("") == nil)
        let max = String(repeating: "x", count: RemoteSubmission.feedbackMessageLimit)
        #expect(RemoteSubmission.validateFeedbackMessage(max) == max)             // exactly at cap
        #expect(RemoteSubmission.validateFeedbackMessage(max + "x") == nil)       // over cap
    }

    @Test func submissionsAreCodableForTheSpool() throws {
        let all: [RemoteSubmission] = [
            .signup(email: "a@b.co", appVersion: "1"),
            .feedback(kind: .feature, message: "m", email: nil, appVersion: "1", osVersion: "15"),
        ]
        let data = try JSONEncoder().encode(all)
        #expect(try JSONDecoder().decode([RemoteSubmission].self, from: data) == all)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mac && swift test --filter RemoteSubmissionTests`
Expected: compile FAILURE — `RemoteSubmission` not defined.

- [ ] **Step 3: Write the implementation**

Create `mac/Sources/SidekitCore/RemoteSubmission.swift`:

```swift
import Foundation

/// The optional feedback tag (spec §3): the 🐞/💡 chips; untagged lands as `.other`.
/// Raw values match the `feedback.type` check constraint in Supabase.
public enum FeedbackKind: String, Sendable, Equatable, Codable {
    case bug, feature, other
}

/// One outbound write — the only data Sidekit ever sends anywhere (spec §1 decision 5).
/// Knows its target table and its exact JSON body, so the network adapter stays a dumb pipe
/// and the wire format is unit-tested here. Codable so the spool can persist it.
public enum RemoteSubmission: Sendable, Equatable, Codable {
    case signup(email: String, appVersion: String)
    case feedback(kind: FeedbackKind, message: String, email: String?,
                  appVersion: String, osVersion: String)

    /// Hard cap on a feedback message (mirrors the DB check constraint).
    public static let feedbackMessageLimit = 4000

    /// Trimmed message if sendable (non-blank, within the cap), else nil.
    public static func validateFeedbackMessage(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= feedbackMessageLimit else { return nil }
        return trimmed
    }

    /// The PostgREST table this submission inserts into.
    public var table: String {
        switch self {
        case .signup: return "signups"
        case .feedback: return "feedback"
        }
    }

    /// The exact insert body. Keys match the table columns (spec §4).
    public func jsonBody() -> Data {
        var object: [String: String]
        switch self {
        case let .signup(email, appVersion):
            object = ["email": email, "app_version": appVersion, "platform": "mac"]
        case let .feedback(kind, message, email, appVersion, osVersion):
            object = ["type": kind.rawValue, "message": message,
                      "app_version": appVersion, "os_version": osVersion]
            if let email { object["email"] = email }
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data("{}".utf8)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mac && swift test --filter RemoteSubmissionTests`
Expected: PASS (5 tests). Then `swift test` — full suite green.

- [ ] **Step 5: Commit**

```bash
git add mac/Sources/SidekitCore/RemoteSubmission.swift mac/Tests/SidekitCoreTests/RemoteSubmissionTests.swift
git commit -m "feat(mac): remote submission payloads + validation (SHIP-2)"
```

---

## Task 3 (SHIP-3): SubmissionSpool — persistent outbox with retry

`Skill:` none (domain) · superpowers:test-driven-development

**Files:**
- Create: `mac/Sources/SidekitCore/SubmissionSpool.swift`
- Create: `mac/Tests/SidekitCoreTests/SubmissionSpoolTests.swift`
- Modify: `mac/Tests/SidekitCoreTests/Fakes.swift` (append `FakeSpoolPersistence`, `FakeSender`)

- [ ] **Step 1: Write the failing tests**

Append to `Fakes.swift`:

```swift
/// In-memory SpoolPersisting: seeds the spool on load and records what it saved.
final class FakeSpoolPersistence: SpoolPersisting, @unchecked Sendable {
    var stored: [SpooledSubmission]
    private(set) var saveCount = 0
    init(_ initial: [SpooledSubmission] = []) { stored = initial }
    func load() -> [SpooledSubmission] { stored }
    func save(_ entries: [SpooledSubmission]) { saveCount += 1; stored = entries }
}

/// Scripted SubmissionSending: returns queued results FIFO (empty → `defaultResult`) and
/// records every submission it saw. Mutated only from the main actor (the spool is @MainActor).
final class FakeSender: SubmissionSending, @unchecked Sendable {
    var results: [SendResult] = []
    var defaultResult: SendResult = .sent
    private(set) var sent: [RemoteSubmission] = []
    func send(_ submission: RemoteSubmission) async -> SendResult {
        sent.append(submission)
        return results.isEmpty ? defaultResult : results.removeFirst()
    }
}
```

Create `SubmissionSpoolTests.swift`:

```swift
import Testing
import Foundation
@testable import SidekitCore

@MainActor
struct SubmissionSpoolTests {

    private let signup = RemoteSubmission.signup(email: "a@b.co", appVersion: "1")
    private let bug = RemoteSubmission.feedback(kind: .bug, message: "m", email: nil,
                                                appVersion: "1", osVersion: "15")

    private func makeSUT(seed: [SpooledSubmission] = []) -> (SubmissionSpool, FakeSpoolPersistence, FakeSender) {
        let persistence = FakeSpoolPersistence(seed)
        let sender = FakeSender()
        return (SubmissionSpool(persistence: persistence, sender: sender), persistence, sender)
    }

    @Test func enqueueSendsImmediatelyAndEmptiesTheSpool() async {
        let (spool, persistence, sender) = makeSUT()
        let deliveredNow = await spool.enqueue(signup)
        #expect(deliveredNow)
        #expect(spool.pending.isEmpty)
        #expect(sender.sent == [signup])
        #expect(persistence.stored.isEmpty) // success persisted too
    }

    @Test func retryableKeepsTheEntryQueued() async {
        let (spool, persistence, sender) = makeSUT()
        sender.results = [.retryable]
        let deliveredNow = await spool.enqueue(bug)
        #expect(!deliveredNow)
        #expect(spool.pending.count == 1)
        #expect(persistence.stored.count == 1) // survives a relaunch
    }

    @Test func retryAllFlushesAQueuedEntry() async {
        let (first, persistence, firstSender) = makeSUT()
        firstSender.results = [.retryable]
        _ = await first.enqueue(signup)
        // "Relaunch": a fresh spool loads the persisted outbox and retries at launch.
        let (second, _, secondSender) = makeSUT(seed: persistence.stored)
        await second.retryAll()
        #expect(secondSender.sent == [signup])
        #expect(second.pending.isEmpty)
    }

    @Test func rejectedEntryIsDroppedAfterThreeStrikes() async {
        let (spool, _, sender) = makeSUT()
        sender.results = [.rejected]
        _ = await spool.enqueue(bug)               // strike 1
        #expect(spool.pending.first?.rejections == 1)
        sender.results = [.rejected]
        await spool.retryAll()                     // strike 2
        #expect(spool.pending.first?.rejections == 2)
        sender.results = [.rejected]
        await spool.retryAll()                     // strike 3 — dropped (poison payload)
        #expect(spool.pending.isEmpty)
    }

    @Test func capacityDropsTheOldestEntry() async {
        let (spool, _, sender) = makeSUT()
        sender.defaultResult = .retryable // nothing ever goes out — the queue only grows
        _ = await spool.enqueue(signup) // the oldest — should be evicted
        for _ in 0..<SubmissionSpool.capacity { _ = await spool.enqueue(bug) }
        #expect(spool.pending.count == SubmissionSpool.capacity)
        #expect(spool.pending.first?.submission == bug) // signup evicted
    }

    @Test func mixedFlushKeepsOnlyTheRetryable() async {
        let seed = [SpooledSubmission(submission: signup), SpooledSubmission(submission: bug)]
        let (spool, persistence, sender) = makeSUT(seed: seed)
        sender.results = [.sent, .retryable]
        await spool.retryAll()
        #expect(spool.pending.map(\.submission) == [bug])
        #expect(persistence.stored.map(\.submission) == [bug])
    }

    @Test func spoolCodecRoundTripsAndToleratesCorruptData() throws {
        let entries = [SpooledSubmission(submission: signup, rejections: 2)]
        #expect(SpoolCodec.decode(SpoolCodec.encode(entries)) == entries)
        #expect(SpoolCodec.decode(Data("garbage".utf8)) == [])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mac && swift test --filter SubmissionSpoolTests`
Expected: compile FAILURE — `SubmissionSpool` / `SpooledSubmission` / `SendResult` not defined.

- [ ] **Step 3: Write the implementation**

Create `mac/Sources/SidekitCore/SubmissionSpool.swift`:

```swift
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
    private var flushing = false

    public init(persistence: SpoolPersisting, sender: SubmissionSending) {
        self.persistence = persistence
        self.sender = sender
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

    /// Walk the queue once, by entry id (entries can be added/removed across awaits).
    private func flush() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mac && swift test --filter SubmissionSpoolTests`
Expected: PASS (7 tests). Then `swift test` — full suite green.

- [ ] **Step 5: Commit**

```bash
git add mac/Sources/SidekitCore/SubmissionSpool.swift mac/Tests/SidekitCoreTests/SubmissionSpoolTests.swift mac/Tests/SidekitCoreTests/Fakes.swift
git commit -m "feat(mac): persistent submission spool with retry + poison-drop (SHIP-3)"
```

---

## Task 4 (SHIP-4): SidekitNet target — Supabase sender + JSON persistence adapters

`Skill:` none (domain) · superpowers:verification-before-completion

The sender lives in a small library target (not the app executable) so the Task 7 selftest can
drive it headlessly — exactly the `ModelSelftest` precedent. No unit tests for the thin I/O
adapters (repo convention); the sender is verified end-to-end in Task 7 against a local stand-in.

**Files:**
- Modify: `mac/Package.swift` (add `SidekitNet` target; app depends on it)
- Create: `mac/Sources/SidekitNet/SupabaseClient.swift`
- Create: `mac/Sources/SidekitApp/Adapters/JSONIdentityStore.swift`
- Create: `mac/Sources/SidekitApp/Adapters/JSONSpoolStore.swift`

- [ ] **Step 1: Add the SidekitNet target to Package.swift**

In `mac/Package.swift`, replace the targets list entries for `SidekitCore`/`SidekitApp` so they read:

```swift
        .target(name: "SidekitCore"),
        // The one network adapter (Supabase inserts), split out so SubmissionSelftest can
        // verify it headlessly (same pattern as ModelSelftest for the Whisper model).
        .target(name: "SidekitNet", dependencies: ["SidekitCore"]),
        .executableTarget(
            name: "SidekitApp",
            dependencies: [
                "SidekitCore",
                "SidekitNet",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
```

- [ ] **Step 2: Create the Supabase client**

Create `mac/Sources/SidekitNet/SupabaseClient.swift`:

```swift
import Foundation
import SidekitCore

/// Where the two inserts go (spec §4). The anon key is public-by-design: row-level
/// security on the Supabase side allows INSERT only, so an extracted key cannot read,
/// list, or modify anything.
///
/// Fill the two constants from docs/SUPABASE-SETUP.md after creating the project.
/// The env overrides let a dev build point at a local stand-in server (M9 smoke test):
///   SIDEKIT_SUPABASE_URL=http://127.0.0.1:8765 SIDEKIT_SUPABASE_KEY=test swift run …
public enum SupabaseConfig {
    private static let defaultURL = ""      // e.g. "https://abcdefgh.supabase.co"
    private static let defaultAnonKey = ""  // the project's anon/public key

    public static var projectURL: URL? {
        let raw = ProcessInfo.processInfo.environment["SIDEKIT_SUPABASE_URL"] ?? defaultURL
        return raw.isEmpty ? nil : URL(string: raw)
    }

    public static var anonKey: String {
        ProcessInfo.processInfo.environment["SIDEKIT_SUPABASE_KEY"] ?? defaultAnonKey
    }
}

/// The app's one network adapter: POST a submission's body to its PostgREST table.
/// `Prefer: return=minimal` keeps insert-only RLS sufficient (no select needed).
public struct SupabaseSubmissionSender: SubmissionSending {
    public init() {}

    public func send(_ submission: RemoteSubmission) async -> SendResult {
        // Unconfigured build (no URL baked in, no env override): keep everything queued —
        // nothing is lost, and a configured build will flush the spool on launch.
        guard let base = SupabaseConfig.projectURL else { return .retryable }
        var request = URLRequest(url: base.appendingPathComponent("rest/v1/\(submission.table)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.httpBody = submission.jsonBody()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .retryable }
            switch http.statusCode {
            case 200..<300:
                return .sent
            case 409 where submission.table == "signups":
                return .sent // duplicate email — already on the list, goal met (spec §4)
            case 400..<500:
                return .rejected
            default:
                return .retryable // 5xx — Supabase hiccup, try again next launch
            }
        } catch {
            return .retryable // offline / timeout — the spool holds it (spec §6)
        }
    }
}
```

- [ ] **Step 3: Create the two JSON persistence adapters**

Create `mac/Sources/SidekitApp/Adapters/JSONIdentityStore.swift`:

```swift
import Foundation
import SidekitCore

/// On-disk persistence for the identity state, at
/// `~/Library/Application Support/Sidekit/identity.json`. Mirrors `JSONHistoryStore`:
/// tolerant load (missing/corrupt → fresh state, logged), atomic write with one retry.
/// `@unchecked Sendable`: `url` is immutable and there's no mutable shared state.
final class JSONIdentityStore: IdentityPersisting, @unchecked Sendable {
    private let url = AppPaths.applicationSupport.appendingPathComponent("identity.json")

    func load() -> IdentityState {
        guard FileManager.default.fileExists(atPath: url.path) else { return IdentityState() }
        guard let data = try? Data(contentsOf: url) else {
            Diag.log("identity: could not read \(url.lastPathComponent)")
            return IdentityState()
        }
        return IdentityCodec.decode(data)
    }

    func save(_ state: IdentityState) {
        let data = IdentityCodec.encode(state)
        do {
            try writeAtomically(data)
        } catch {
            do { try writeAtomically(data) }
            catch { Diag.log("identity: save failed twice — keeping in memory (\(error))") }
        }
    }

    private func writeAtomically(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
```

Create `mac/Sources/SidekitApp/Adapters/JSONSpoolStore.swift`:

```swift
import Foundation
import SidekitCore

/// On-disk persistence for the submission outbox, at
/// `~/Library/Application Support/Sidekit/outbox.json` — how a failed send survives
/// quit/offline until the next launch retries it. Same tolerant/atomic pattern as the
/// other JSON stores. `@unchecked Sendable`: `url` is immutable, no shared mutable state.
final class JSONSpoolStore: SpoolPersisting, @unchecked Sendable {
    private let url = AppPaths.applicationSupport.appendingPathComponent("outbox.json")

    func load() -> [SpooledSubmission] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else {
            Diag.log("outbox: could not read \(url.lastPathComponent)")
            return []
        }
        return SpoolCodec.decode(data)
    }

    func save(_ entries: [SpooledSubmission]) {
        let data = SpoolCodec.encode(entries)
        do {
            try writeAtomically(data)
        } catch {
            do { try writeAtomically(data) }
            catch { Diag.log("outbox: save failed twice — keeping in memory (\(error))") }
        }
    }

    private func writeAtomically(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Verify it builds and the suite stays green**

Run: `cd mac && swift build && swift test`
Expected: builds clean; full suite green (no behavior change yet — nothing constructs these).

- [ ] **Step 5: Commit**

```bash
git add mac/Package.swift mac/Sources/SidekitNet/SupabaseClient.swift mac/Sources/SidekitApp/Adapters/JSONIdentityStore.swift mac/Sources/SidekitApp/Adapters/JSONSpoolStore.swift
git commit -m "feat(mac): SidekitNet Supabase sender + identity/outbox JSON adapters (SHIP-4)"
```

---

## Task 5 (SHIP-5): IdentityModel + welcome sheet + settings email field

`Skill:` none (domain) · superpowers:verification-before-completion (UI — manual verify per M9)

**Files:**
- Create: `mac/Sources/SidekitApp/IdentityModel.swift`
- Create: `mac/Sources/SidekitApp/WelcomeSheet.swift`
- Modify: `mac/Sources/SidekitApp/App.swift` (AppController wiring + pass-through)
- Modify: `mac/Sources/SidekitApp/MainWindow.swift` (present the sheet)
- Modify: `mac/Sources/SidekitApp/SettingsPanel.swift` (Account section)

- [ ] **Step 1: Create IdentityModel (observable wrapper + AppInfo)**

Create `mac/Sources/SidekitApp/IdentityModel.swift`:

```swift
import Foundation
import Combine
import SidekitCore

/// Version strings attached to submissions (shown to the user in the feedback footer —
/// spec §3: everything sent is visible).
enum AppInfo {
    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

/// SwiftUI-facing observable wrapper over the pure `IdentityStore` (NotesModel pattern).
/// A successfully stored email also queues a `signups` submission through the spool.
@MainActor
final class IdentityModel: ObservableObject {
    private let store: IdentityStore
    private let spool: SubmissionSpool

    var email: String? { store.state.email }
    var shouldShowWelcome: Bool { store.shouldShowWelcome }

    init(store: IdentityStore, spool: SubmissionSpool) {
        self.store = store
        self.spool = spool
    }

    func welcomeShown() {
        objectWillChange.send()
        store.welcomeShown()
    }

    /// Validate+store the email locally, then queue the sign-up write. Returns false
    /// (and changes nothing) when the text doesn't look like an email.
    @discardableResult
    func submitEmail(_ raw: String) -> Bool {
        objectWillChange.send()
        guard store.setEmail(raw) else { return false }
        guard let email = store.state.email else { return false }
        let submission = RemoteSubmission.signup(email: email, appVersion: AppInfo.appVersion)
        Task { await spool.enqueue(submission) }
        return true
    }

    /// Local-only (spec §2): no delete call to the backend.
    func clearEmail() {
        objectWillChange.send()
        store.clearEmail()
    }
}
```

- [ ] **Step 2: Create the welcome sheet**

Create `mac/Sources/SidekitApp/WelcomeSheet.swift`:

```swift
import SwiftUI
import SidekitCore

/// The soft-gate sign-up sheet (spec §2): email + honest why, skippable, shown at most
/// twice ever (launch 1, and once more at launch ≥5 — `IdentityStore` owns that rule).
struct WelcomeSheet: View {
    @ObservedObject var identity: IdentityModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""

    private var plausible: Bool { EmailCheck.isPlausible(email) }

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            EqualizerMark(height: 44)
            Text("Welcome to Sidekit")
                .font(.title2.weight(.semibold))
            Text("Leave an email so I can send you updates and help when something breaks — nothing else, ever.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { continueTapped() }

            HStack(spacing: DS.Space.md) {
                Button("Skip for now") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Continue") { continueTapped() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!plausible)
            }

            Text("Sidekit runs fully on your Mac. This email — and feedback you choose to send — are the only things that ever leave it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.xl)
        .frame(width: 380)
    }

    private func continueTapped() {
        guard identity.submitEmail(email) else { return }
        dismiss()
    }
}
```

(If `DS.Space` lacks `xl`/`lg`/`md` or `EqualizerMark` has a different signature, match
whatever `DesignSystem.swift` actually defines — check it before building; do not add new
design tokens for this.)

- [ ] **Step 3: Wire into AppController and present from MainWindow**

In `mac/Sources/SidekitApp/App.swift`:

a) Add stored properties to `AppController` (next to `let shelf: ShelfModel`):

```swift
    /// Sign-up identity (observable wrapper). Drives the welcome sheet + settings field.
    let identity: IdentityModel
    /// The persistent outbox for sign-up/feedback writes (spec §5).
    let spool: SubmissionSpool
```

b) In `AppController.init()`, after `let shelf = ShelfModel()` add:

```swift
        // Identity + outbox (sign-up & feedback, spec 2026-06-11). recordLaunch() advances
        // the soft-gate counter before the window reads shouldShowWelcome.
        let identityStore = IdentityStore(persistence: JSONIdentityStore())
        identityStore.recordLaunch()
        let spool = SubmissionSpool(persistence: JSONSpoolStore(), sender: SupabaseSubmissionSender())
        let identity = IdentityModel(store: identityStore, spool: spool)
```

and alongside the other `self.x = x` assignments:

```swift
        self.identity = identity
        self.spool = spool
```

then at the end of `init()` (after the shelf prune task):

```swift
        // Flush anything queued while offline last session (spec §6).
        Task { await spool.retryAll() }
```

Also add `import SidekitNet` at the top of `App.swift` (for `SupabaseSubmissionSender`).

c) In the `Window` scene, pass identity through:

```swift
        Window("Sidekit", id: MainWindow.id) {
            MainWindow(notes: controller.notes, history: controller.history,
                       settings: controller.settings, shelf: controller.shelf,
                       identity: controller.identity)
```

d) In `MainWindow.swift`, add the property + presentation. Add after `let shelf: ShelfModel`:

```swift
    /// Sign-up identity — drives the one-time welcome sheet and the settings email field.
    @ObservedObject var identity: IdentityModel
```

Add `@State private var showWelcome = false` next to the other `@State`s, and on the
`NavigationSplitView` chain (next to the existing `.sheet`s):

```swift
        .onAppear {
            // Soft gate (spec §2): the store says whether this is one of the ≤2 auto-shows.
            if identity.shouldShowWelcome {
                identity.welcomeShown()
                showWelcome = true
            }
        }
        .sheet(isPresented: $showWelcome) { WelcomeSheet(identity: identity) }
```

e) In `SettingsPanel.swift`, give `SettingsView` the identity and an Account section.
Add to `SettingsView`'s properties:

```swift
    /// Sign-up email (spec §2: also editable here, any time).
    @ObservedObject var identity: IdentityModel
    @State private var emailDraft = ""
```

Add as the FIRST section inside the `Form` (above "Dictation"):

```swift
                Section("Account") {
                    TextField("you@example.com", text: $emailDraft)
                        .onSubmit {
                            if emailDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                                identity.clearEmail()
                            } else {
                                identity.submitEmail(emailDraft)
                            }
                        }
                    Text(identity.email.map { "Signed up as \($0)" }
                         ?? "Not signed up — add an email to get updates & support.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

and seed the draft in the existing `.onAppear { model.refreshPermissions() }`:

```swift
            .onAppear { model.refreshPermissions(); emailDraft = identity.email ?? "" }
```

Update the call site in `MainWindow.swift`:

```swift
        .sheet(isPresented: $showSettings) { SettingsView(model: settings, shelf: shelf, identity: identity) }
```

- [ ] **Step 4: Build + verify**

Run: `cd mac && swift build && swift test`
Expected: clean build, suite green.

Manual smoke (dev run): delete state, launch, observe the sheet logic:

```bash
rm -f ~/Library/Application\ Support/Sidekit/identity.json ~/Library/Application\ Support/Sidekit/outbox.json
cd mac && swift run SidekitApp   # welcome sheet should appear over the main window
```

Skip → quit → relaunch: no sheet (launches 2–4). Verify `identity.json` contents evolve
(`cat ~/Library/Application\ Support/Sidekit/identity.json`). Enter an email → with no
Supabase configured, the entry must sit in `outbox.json` (unconfigured = retryable, spec §4).

- [ ] **Step 5: Commit**

```bash
git add mac/Sources/SidekitApp/IdentityModel.swift mac/Sources/SidekitApp/WelcomeSheet.swift mac/Sources/SidekitApp/App.swift mac/Sources/SidekitApp/MainWindow.swift mac/Sources/SidekitApp/SettingsPanel.swift
git commit -m "feat(mac): welcome soft-gate sheet + settings email field (SHIP-5)"
```

---

## Task 6 (SHIP-6): Feedback box — floating window, chips, ⌘↩, dictation routing

`Skill:` none (domain) · superpowers:verification-before-completion (UI — manual verify per M9)

**Files:**
- Create: `mac/Sources/SidekitApp/FeedbackBox.swift`
- Modify: `mac/Sources/SidekitApp/App.swift` (menu item, routing override, panel creation)

- [ ] **Step 1: Create the feedback model, view, and panel**

Create `mac/Sources/SidekitApp/FeedbackBox.swift`:

```swift
import AppKit
import SwiftUI
import SidekitCore

/// Draft state for the quick-feedback box (spec §3): one message, optional 🐞/💡 tag.
/// Sending queues a `feedback` submission; the toast text depends on whether it went
/// out immediately or is parked in the offline spool.
@MainActor
final class FeedbackModel: ObservableObject {
    @Published var message = ""
    @Published var kind: FeedbackKind?          // nil → lands as .other
    @Published private(set) var toast: String?  // non-nil → sent, box is closing

    private let identity: IdentityModel
    private let spool: SubmissionSpool

    init(identity: IdentityModel, spool: SubmissionSpool) {
        self.identity = identity
        self.spool = spool
    }

    var canSend: Bool { RemoteSubmission.validateFeedbackMessage(message) != nil }

    /// Footer transparency line (spec §3: everything sent is visible).
    var footer: String {
        "Sends with: \(identity.email ?? "anonymous") · Sidekit \(AppInfo.appVersion) · \(AppInfo.osVersion)"
    }

    /// Append a dictated transcript, separating with a space when needed (NotesStore rule).
    func appendDictated(_ text: String) {
        if message.isEmpty || message.last!.isWhitespace {
            message += text
        } else {
            message += " " + text
        }
    }

    /// Validate, queue, toast. Returns false when the message isn't sendable.
    func send() async -> Bool {
        guard let body = RemoteSubmission.validateFeedbackMessage(message) else { return false }
        let submission = RemoteSubmission.feedback(
            kind: kind ?? .other, message: body, email: identity.email,
            appVersion: AppInfo.appVersion, osVersion: AppInfo.osVersion)
        let deliveredNow = await spool.enqueue(submission)
        toast = deliveredNow ? "Thanks! 🙌" : "Saved — will send when you're online."
        message = ""
        kind = nil
        return true
    }

    /// Reset the toast for the next open (drafts survive an Esc — only a send clears them).
    func reopened() { toast = nil }
}

/// The 5-second feedback view: text box (placeholder invites dictation), two optional
/// chips, transparency footer, ⌘↩ send / Esc close.
struct FeedbackView: View {
    @ObservedObject var model: FeedbackModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Send Feedback").font(.headline)
                Spacer()
                chip("🐞 Bug", .bug)
                chip("💡 Idea", .feature)
            }

            ZStack(alignment: .topLeading) {
                if model.message.isEmpty {
                    Text("Type — or hold Fn and just say it.")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: $model.message)
                    .scrollContentBackground(.hidden)
                    .frame(height: 88)
            }
            .padding(DS.Space.sm)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Text(model.footer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Button("Send") { send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSend)
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 420)
        .overlay {
            if let toast = model.toast {
                Text(toast)
                    .font(.headline)
                    .padding(DS.Space.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .background(KeyCatcher(onEscape: onClose))   // Esc closes without sending (spec §3)
        .tint(DS.Palette.accent)
        .preferredColorScheme(.dark)
    }

    private func chip(_ label: String, _ value: FeedbackKind) -> some View {
        Button(label) { model.kind = (model.kind == value) ? nil : value }
            .buttonStyle(.bordered)
            .tint(model.kind == value ? DS.Palette.accent : .secondary)
    }

    private func send() {
        Task {
            guard await model.send() else { return }
            try? await Task.sleep(for: .milliseconds(900))   // let the toast read
            onClose()
        }
    }
}

/// Invisible NSView that closes the box on Esc (borderless windows don't get
/// `cancelAction` routing for free).
private struct KeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> EscapeView {
        let view = EscapeView()
        view.onEscape = onEscape
        return view
    }
    func updateNSView(_ nsView: EscapeView, context: Context) { nsView.onEscape = onEscape }

    final class EscapeView: NSView {
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { false }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53, self?.window?.isKeyWindow == true { // 53 = Esc
                    self?.onEscape?()
                    return nil
                }
                return event
            }
        }
        private var monitor: Any?
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// The feedback box's floating window: borderless glass like the family panels, but
/// **activating and keyable** — the user is deliberately here to type (or dictate), unlike
/// the click-through pill / non-activating shelf.
@MainActor
final class FeedbackBox {
    let model: FeedbackModel
    private let panel: KeyablePanel

    /// Whether dictation should route here (the box is the key window) — see the
    /// RoutingSink wiring in AppController.
    var isKey: Bool { panel.isKeyWindow }

    init(identity: IdentityModel, spool: SubmissionSpool) {
        model = FeedbackModel(identity: identity, spool: spool)
        let canvas = NSRect(x: 0, y: 0, width: 440, height: 240)
        panel = KeyablePanel(contentRect: canvas,
                             styleMask: [.borderless, .fullSizeContentView],
                             backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView:
            FeedbackView(model: model, onClose: { [weak self] in self?.hide() }))
        hosting.frame = canvas
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
    }

    func show() {
        model.reopened()
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2,
                                         y: f.midY - panel.frame.height / 2 + 80))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() { panel.orderOut(nil) }

    /// A borderless NSPanel refuses key status by default; the box needs it for typing.
    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}
```

- [ ] **Step 2: Wire into AppController — create early, route dictation, add menu item**

In `mac/Sources/SidekitApp/App.swift`:

a) Add the stored property (next to `private var pill: PillPanel?`):

```swift
    private var feedbackBox: FeedbackBox?
```

b) In `init()`, the box must exist BEFORE the routing sink so the routing closure can
capture it. Right after the identity/spool block from Task 5, add:

```swift
        // Created before the RoutingSink: when the feedback box is the key window,
        // dictation routes into it instead of the notes (spec §3, dictation-first).
        let feedbackBox = FeedbackBox(identity: identity, spool: spool)
```

c) Replace the `RoutingSink`'s `appendToNote` closure with the feedback-aware version:

```swift
            appendToNote: { text in
                MainActor.assumeIsolated {
                    // Spec §3 (2026-06-11): the feedback box outranks the notes while
                    // it's the key window — "hold Fn and just say it".
                    if feedbackBox.isKey {
                        feedbackBox.model.appendDictated(text)
                    } else {
                        let id = notes.activeID ?? notes.newNote().id
                        notes.append(text, to: id)
                    }
                }
            },
```

d) Store it alongside the other `self.x = x` assignments:

```swift
        self.feedbackBox = feedbackBox
```

e) Add the controller method (next to `openAccessibilitySettings`):

```swift
    func showFeedbackBox() { feedbackBox?.show() }
```

f) Add the menu item in `MenuContent` (after the status `Text`, before the Accessibility block):

```swift
        Divider()
        Button("Send Feedback…") { controller.showFeedbackBox() }
```

- [ ] **Step 3: Build + verify**

Run: `cd mac && swift build && swift test`
Expected: clean build, suite green.

Manual smoke (dev run, `swift run SidekitApp`):
1. Menu bar → "Send Feedback…" → box appears centered, text field focused, placeholder reads "Type — or hold Fn and just say it."
2. Type text → Send enables; ⌘↩ → toast → box closes; with no Supabase config the entry lands in `outbox.json`.
3. Esc closes without sending; reopening shows the kept draft.
4. (Bundle build only — Fn needs Accessibility:) hold Fn with the box key, speak → transcript appends into the box, NOT into a note.
5. With the box closed, dictation into a focused note still works (regression check on M5).

- [ ] **Step 4: Commit**

```bash
git add mac/Sources/SidekitApp/FeedbackBox.swift mac/Sources/SidekitApp/App.swift
git commit -m "feat(mac): dictation-first quick-feedback box + menu item (SHIP-6)"
```

---

## Task 7 (SHIP-7): SubmissionSelftest + stand-in verification + setup doc + TESTING.md M9

`Skill:` none (domain) · superpowers:verification-before-completion

**Files:**
- Modify: `mac/Package.swift` (add `SubmissionSelftest` executable)
- Create: `mac/Sources/SubmissionSelftest/main.swift`
- Create: `docs/SUPABASE-SETUP.md`
- Modify: `mac/TESTING.md` (section 9 + sign-off row)

- [ ] **Step 1: Add the selftest target**

In `mac/Package.swift`, after the `ModelSelftest` target add:

```swift
        // Dev tool: verify the Supabase sender headlessly against a real project or a
        // local stand-in. Usage:
        //   SIDEKIT_SUPABASE_URL=… SIDEKIT_SUPABASE_KEY=… swift run SubmissionSelftest
        .executableTarget(
            name: "SubmissionSelftest",
            dependencies: ["SidekitCore", "SidekitNet"]
        ),
```

Create `mac/Sources/SubmissionSelftest/main.swift`:

```swift
import Foundation
import SidekitCore
import SidekitNet

// Sends one signup + one feedback to whatever SIDEKIT_SUPABASE_URL points at and exits
// 0 iff both were accepted. Drives the same SupabaseSubmissionSender the app ships with.
let sender = SupabaseSubmissionSender()
let signup = RemoteSubmission.signup(email: "selftest@example.com", appVersion: "selftest")
let feedback = RemoteSubmission.feedback(kind: .other, message: "selftest message",
                                         email: "selftest@example.com",
                                         appVersion: "selftest", osVersion: "selftest")
let signupResult = await sender.send(signup)
let feedbackResult = await sender.send(feedback)
print("signup: \(signupResult)  feedback: \(feedbackResult)")
exit(signupResult == .sent && feedbackResult == .sent ? 0 : 1)
```

- [ ] **Step 2: Verify the sender against a local stand-in**

Start a stand-in PostgREST that records hits (run from repo root, in the background):

```bash
python3 - <<'PYEOF' > /tmp/standin.log 2>&1 &
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n).decode()
        print(f"HIT path={self.path} apikey={self.headers.get('apikey')} "
              f"prefer={self.headers.get('Prefer')} body={body}", flush=True)
        self.send_response(201); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', 8765), H).serve_forever()
PYEOF
```

Then:

```bash
cd mac && SIDEKIT_SUPABASE_URL=http://127.0.0.1:8765 SIDEKIT_SUPABASE_KEY=testkey swift run SubmissionSelftest
cat /tmp/standin.log
```

Expected: selftest prints `signup: sent  feedback: sent`, exits 0, and `/tmp/standin.log`
shows TWO hits — `path=/rest/v1/signups` and `path=/rest/v1/feedback`, both with
`apikey=testkey`, `prefer=return=minimal`, and the JSON bodies from Task 2. Also verify the
unconfigured path: `swift run SubmissionSelftest` with NO env vars must print
`signup: retryable  feedback: retryable` and exit 1. Kill the python server when done.

- [ ] **Step 3: Write the setup doc**

Create `docs/SUPABASE-SETUP.md` with: (1) create free account/project at supabase.com;
(2) SQL editor → paste the spec §4 SQL verbatim (copy it from
`docs/superpowers/specs/2026-06-11-sidekit-signup-feedback-design.md` — tables + RLS +
insert-only policies); (3) Project Settings → API → copy the URL and `anon` key into
`mac/Sources/SidekitNet/SupabaseClient.swift` (`defaultURL` / `defaultAnonKey`); (4) smoke
test: `SIDEKIT_SUPABASE_URL=<url> SIDEKIT_SUPABASE_KEY=<key> swift run SubmissionSelftest`
→ expect `signup: sent  feedback: sent`, rows visible in Table Editor; (5) verify the key
is insert-only: `curl "<url>/rest/v1/signups?select=*" -H "apikey: <key>" -H "Authorization: Bearer <key>"`
must return an error/empty — never rows; (6) the two table views are the user list and
feedback inbox; CSV export buttons live there.

- [ ] **Step 4: Add M9 to TESTING.md**

In `mac/TESTING.md`, add before the `## Sign-off` section:

```markdown
## 9. Sign-up & feedback  _(spec 2026-06-11 — the app's only network feature)_

Reset first: `rm -f ~/Library/Application\ Support/Sidekit/identity.json ~/Library/Application\ Support/Sidekit/outbox.json`

- [ ] **First launch:** welcome sheet appears over the main window (logo, email field,
      Skip / Continue). **Skip** → sheet gone; quit & relaunch (launches 2–4) → **no sheet**;
      5th launch → sheet appears **once more**; after that, never again.
- [ ] **Sign up:** enter an email → Continue. Row appears in the Supabase `signups` table
      (needs `SUPABASE-SETUP.md` done). Settings → Account shows "Signed up as …".
- [ ] **Quick feedback:** menu bar → **Send Feedback…** → box opens centered, field focused.
      **Hold Fn and dictate** → transcript lands in the box (not in a note). ⌘↩ → "Thanks!"
      toast → row in the `feedback` table with type/email/versions.
- [ ] **Esc** closes without sending; reopening keeps the draft. Chips 🐞/💡 toggle; untagged
      sends as `other`.
- [ ] **Offline:** disconnect Wi-Fi → send feedback → toast says "Saved — will send when
      you're online" and the entry sits in `outbox.json`. Reconnect → relaunch → row appears
      and `outbox.json` is empty.
- [ ] **Routing regression (M5):** with the box closed and the main window focused,
      dictation still lands in the active note; with Sidekit unfocused it still pastes at
      the cursor.
- [ ] **Key safety:** the curl `select` from `SUPABASE-SETUP.md` step 5 returns an error —
      the shipped key cannot read data.
```

Add to the sign-off table: `| 9  | Sign-up & feedback                    |                |       |`
and update the automated-test count in section 0 to the new `swift test` total.

- [ ] **Step 5: Full verification + commit**

```bash
cd mac && swift test && swift build   # full suite + clean build
git add mac/Package.swift mac/Sources/SubmissionSelftest/main.swift docs/SUPABASE-SETUP.md mac/TESTING.md
git commit -m "feat(mac): submission selftest + Supabase setup doc + M9 test plan (SHIP-7)"
```

---

## Final gate (after all tasks)

1. `cd mac && swift test` — everything green; note the total for TESTING.md §0.
2. `cd mac && ./Scripts/build-app.sh release` — the signed bundle builds.
3. Update `BRICKS.md`: add the SHIP Done entries (keep 3 newest, archive the rest to
   `BRICKS-ARCHIVE.md`), note the user's one outstanding action: **run
   `docs/SUPABASE-SETUP.md` (~20 min), paste URL + anon key into `SupabaseClient.swift`,
   rebuild, run M9.**
4. Push `feat/mac-app`.
