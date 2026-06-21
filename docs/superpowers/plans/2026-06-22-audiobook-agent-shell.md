# Audiobook Agent — App Shell + Action Schema (Sub-project A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a real, functional native-macOS audiobook player with honest observable state plus a machine-readable 11-action schema — the foundation every later sub-project (harness, listening, fine-tuning) targets and verifies against.

**Architecture:** Ports-and-adapters, same discipline as Sidekit's `SidekitCore`. A pure, fully-unit-tested core (`AudiobookCore`: `PlayerState`, `PlayerStore`, `ActionSchema`, `Book`) talks to the OS only through two ports (`AudioOutputPort`, `ClockPort`). The SwiftUI shell and the AVFoundation/timer adapters live in a separate `AudiobookApp` target and are verified manually on the Mac. No AI in this sub-project.

**Tech Stack:** Swift 6.0, SwiftPM, swift-testing (`import Testing`, `@Test`, `#expect`), SwiftUI, AVFoundation (`AVAudioPlayer`). New top-level package at `agents/audiobook/`.

## Global Constraints

- Swift tools version `6.0`; platform floor `macOS .v14`. (Verbatim from `mac/Package.swift`.)
- Test framework is **swift-testing** (`import Testing`, `@Test`, `#expect`) — NOT XCTest. (Repo convention.)
- Pure core (`AudiobookCore`) has **zero** OS/UI/AVFoundation dependencies; it talks to ports only. (Spec: Architecture.)
- The 11 actions and their exact names/params/verifiable-state are fixed by the spec — do not add, rename, or rescope them. (Spec: action schema.)
- Chapter numbers in the **action API are 1-based** ("chapter 3" → `goToChapter(3)`); internal chapter **indexes are 0-based**. Convert at the boundary. (Plan decision, see Task 4.)
- `position`, `speed`, etc. are the verifiable source of truth; the audio adapter is a side-effect mirror. Tests assert on `PlayerState`, never on audio hardware. (Spec: Testing.)
- macOS only. No user file import, no persistence across launches, no remote content, no extra actions. (Spec: out of scope.)
- Update `STRUCTURE.md` in the task that creates the new top-level folder (CLAUDE.md §7). (Spec: success criterion 5.)
- Commit after every task (CLAUDE.md §2a; frequent commits). Work happens on branch `feat/audiobook-agent`.

---

## File Structure

```
agents/audiobook/
  Package.swift
  Sources/
    AudiobookCore/
      Book.swift            # Chapter, Book value types + bundled SampleLibrary
      PlayerState.swift     # PlayerState, SleepTimer, ActionResult; currentChapter (computed)
      Ports.swift           # AudioOutputPort, ClockPort protocols
      PlayerStore.swift     # the pure core: the 11 actions
      ActionSchema.swift    # machine-readable schema + consistency surface
    AudiobookApp/
      main.swift            # @main App entry
      AudioOutputAdapter.swift  # AVAudioPlayer-backed AudioOutputPort
      SystemClock.swift         # Timer-backed ClockPort
      PlayerViewModel.swift     # ObservableObject wrapping PlayerStore for SwiftUI
      LibraryView.swift         # book list
      NowPlayingView.swift      # cover/title/chapter/scrubber + the 11 controls
      Resources/
        book-*.caf          # bundled sample audio (generated, see Task 7) — MUST live
                            # inside the target dir for SwiftPM resources to resolve
  Scripts/
    make-samples.sh       # regenerates the sample audio deterministically (license-free)
```

> **Build-sequencing note (controller-fixed):** The `AudiobookApp` executable target is
> **declared in Task 7**, not Task 1 — a SwiftPM target with no source files fails to build, and
> `AudiobookApp` has no sources until Task 7. So Task 1's `Package.swift` declares only
> `AudiobookCore` + `AudiobookCoreTests`; Task 7 adds the `AudiobookApp` target (with its resources).

Split rationale: `Book` (content model), `PlayerState` (verifiable state), `Ports` (boundaries), `PlayerStore` (behavior), and `ActionSchema` (the reusable contract) each own one responsibility and are small enough to hold in context. Adapters + UI are isolated in `AudiobookApp` so the core stays pure and testable.

---

### Task 1: Package scaffold + content model + STRUCTURE.md

**Files:**
- Create: `agents/audiobook/Package.swift`
- Create: `agents/audiobook/Sources/AudiobookCore/Book.swift`
- Create: `agents/audiobook/Sources/AudiobookCore/PlayerState.swift`
- Create: `agents/audiobook/Tests/AudiobookCoreTests/SampleLibraryTests.swift`
- Modify: `STRUCTURE.md` (add the `agents/` row + a short section)

**Interfaces:**
- Produces:
  - `struct Chapter: Equatable { let title: String; let startTime: TimeInterval }`
  - `struct Book: Identifiable, Equatable { let id: String; let title: String; let author: String; let audioFileName: String; let duration: TimeInterval; let chapters: [Chapter] }`
  - `enum SampleLibrary { static let books: [Book] }` (≥2 books, each ≥3 chapters)
  - `struct SleepTimer: Equatable { enum Mode: Equatable { case minutes(Int); case endOfChapter }; let mode: Mode; let fireAt: TimeInterval }`
  - `enum ActionResult: Equatable { case applied; case rejected(String) }`
  - `struct PlayerState: Equatable { var currentBook: Book; var isPlaying: Bool; var position: TimeInterval; var speed: Double; var sleepTimer: SleepTimer? }` with computed `var currentChapter: Int` (0-based) and `static func initial(book: Book) -> PlayerState`

- [ ] **Step 1: Create the package manifest**

`agents/audiobook/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

// Audiobook Agent (macOS) — the first voice-agent built end-to-end to prove the
// listen→decide→act→verify loop. AudiobookCore is pure & unit-tested; AudiobookApp
// holds the AVFoundation/timer adapters + SwiftUI shell. Sub-project A: no AI yet.
let package = Package(
    name: "AudiobookAgent",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AudiobookCore"),
        .testTarget(name: "AudiobookCoreTests", dependencies: ["AudiobookCore"]),
    ]
)
```
(Only the pure core + its tests are declared now. The `AudiobookApp` executable target is added in
Task 7 — a SwiftPM target with no source files fails to build, and `AudiobookApp` has no sources
until then.)

- [ ] **Step 2: Write the content model**

`agents/audiobook/Sources/AudiobookCore/Book.swift`:
```swift
import Foundation

public struct Chapter: Equatable, Sendable {
    public let title: String
    public let startTime: TimeInterval   // seconds from the start of the book
    public init(title: String, startTime: TimeInterval) {
        self.title = title
        self.startTime = startTime
    }
}

public struct Book: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let audioFileName: String     // bundled resource, e.g. "book-a.caf"
    public let duration: TimeInterval
    public let chapters: [Chapter]
    public init(id: String, title: String, author: String,
                audioFileName: String, duration: TimeInterval, chapters: [Chapter]) {
        self.id = id; self.title = title; self.author = author
        self.audioFileName = audioFileName; self.duration = duration; self.chapters = chapters
    }
}

public enum SampleLibrary {
    public static let books: [Book] = [
        Book(id: "meditations", title: "Meditations", author: "Marcus Aurelius",
             audioFileName: "book-a.caf", duration: 180,
             chapters: [Chapter(title: "Book I", startTime: 0),
                        Chapter(title: "Book II", startTime: 60),
                        Chapter(title: "Book III", startTime: 120)]),
        Book(id: "art-of-war", title: "The Art of War", author: "Sun Tzu",
             audioFileName: "book-b.caf", duration: 150,
             chapters: [Chapter(title: "Laying Plans", startTime: 0),
                        Chapter(title: "Waging War", startTime: 50),
                        Chapter(title: "The Sheathed Sword", startTime: 100)]),
    ]
}
```

- [ ] **Step 3: Write the state model with the failing test**

`agents/audiobook/Sources/AudiobookCore/PlayerState.swift`:
```swift
import Foundation

public enum ActionResult: Equatable, Sendable {
    case applied
    case rejected(String)
}

public struct SleepTimer: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case minutes(Int); case endOfChapter }
    public let mode: Mode
    public let fireAt: TimeInterval   // absolute position (s) at which playback stops
    public init(mode: Mode, fireAt: TimeInterval) { self.mode = mode; self.fireAt = fireAt }
}

public struct PlayerState: Equatable, Sendable {
    public var currentBook: Book
    public var isPlaying: Bool
    public var position: TimeInterval
    public var speed: Double
    public var sleepTimer: SleepTimer?

    public init(currentBook: Book, isPlaying: Bool, position: TimeInterval,
                speed: Double, sleepTimer: SleepTimer?) {
        self.currentBook = currentBook; self.isPlaying = isPlaying
        self.position = position; self.speed = speed; self.sleepTimer = sleepTimer
    }

    public static func initial(book: Book) -> PlayerState {
        PlayerState(currentBook: book, isPlaying: false, position: 0, speed: 1.0, sleepTimer: nil)
    }

    /// 0-based index of the chapter whose range contains `position`. Always consistent
    /// with `position`, so it can never drift.
    public var currentChapter: Int {
        currentBook.chapters.lastIndex { position >= $0.startTime } ?? 0
    }
}
```

`agents/audiobook/Tests/AudiobookCoreTests/SampleLibraryTests.swift`:
```swift
import Testing
import Foundation
@testable import AudiobookCore

struct SampleLibraryTests {
    @Test func libraryHasBooksWithChapters() {
        #expect(SampleLibrary.books.count >= 2)
        for book in SampleLibrary.books {
            #expect(book.chapters.count >= 3)
            #expect(book.chapters.first?.startTime == 0)
        }
    }

    @Test func initialStateIsPausedAtStart() {
        let s = PlayerState.initial(book: SampleLibrary.books[0])
        #expect(s.isPlaying == false)
        #expect(s.position == 0)
        #expect(s.speed == 1.0)
        #expect(s.currentChapter == 0)
    }

    @Test func currentChapterTracksPosition() {
        var s = PlayerState.initial(book: SampleLibrary.books[0]) // chapters at 0,60,120
        s.position = 70
        #expect(s.currentChapter == 1)
        s.position = 130
        #expect(s.currentChapter == 2)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd agents/audiobook && swift test`
Expected: PASS (3 tests in SampleLibraryTests).

- [ ] **Step 5: Update STRUCTURE.md**

In `STRUCTURE.md`, add a row to the "Repository map" table:
```
| `agents/` | Voice-driven **task agents** built on Sidekit (listen→decide→act→verify). First: `agents/audiobook/`. | `agents/audiobook/` |
```
And add a one-paragraph section after the repository map explaining: `agents/` holds the new voice-agent framework work; the first agent is a functional audiobook player whose action schema the harness targets; see `docs/superpowers/specs/2026-06-22-voice-agent-audiobook-shell-design.md`.

- [ ] **Step 6: Commit**

```bash
git add agents/audiobook STRUCTURE.md
git commit -m "feat(agent): scaffold audiobook package + content/state model"
```

---

### Task 2: Ports + test fakes

**Files:**
- Create: `agents/audiobook/Sources/AudiobookCore/Ports.swift`
- Create: `agents/audiobook/Tests/AudiobookCoreTests/Fakes.swift`
- Create: `agents/audiobook/Tests/AudiobookCoreTests/PortsTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `protocol AudioOutputPort: AnyObject { func load(_ fileName: String); func play(); func pause(); func seek(to seconds: TimeInterval); func setRate(_ rate: Double) }`
  - `protocol ClockPort: AnyObject { func start(onTick: @escaping (TimeInterval) -> Void); func stop() }`
  - Test doubles `FakeAudioOutput` (records calls) and `FakeClock` (stores `onTick`, exposes `func tick(_ delta: TimeInterval)`).

- [ ] **Step 1: Write the ports**

`agents/audiobook/Sources/AudiobookCore/Ports.swift`:
```swift
import Foundation

/// Real audio output. The core drives this as a side effect; verification reads
/// PlayerState, not this port.
public protocol AudioOutputPort: AnyObject {
    func load(_ fileName: String)
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func setRate(_ rate: Double)
}

/// Drives logical playback time. `onTick` delivers elapsed wall-seconds since the last tick;
/// the core multiplies by `speed` to advance `position`.
public protocol ClockPort: AnyObject {
    func start(onTick: @escaping (TimeInterval) -> Void)
    func stop()
}
```

- [ ] **Step 2: Write the fakes**

`agents/audiobook/Tests/AudiobookCoreTests/Fakes.swift`:
```swift
import Foundation
@testable import AudiobookCore

final class FakeAudioOutput: AudioOutputPort {
    private(set) var loaded: String?
    private(set) var isPlaying = false
    private(set) var seekedTo: TimeInterval?
    private(set) var rate: Double = 1.0
    private(set) var playCount = 0
    private(set) var pauseCount = 0

    func load(_ fileName: String) { loaded = fileName }
    func play() { isPlaying = true; playCount += 1 }
    func pause() { isPlaying = false; pauseCount += 1 }
    func seek(to seconds: TimeInterval) { seekedTo = seconds }
    func setRate(_ rate: Double) { self.rate = rate }
}

final class FakeClock: ClockPort {
    private var onTick: ((TimeInterval) -> Void)?
    private(set) var running = false
    func start(onTick: @escaping (TimeInterval) -> Void) { self.onTick = onTick; running = true }
    func stop() { running = false }
    /// Test helper: advance logical time by `delta` wall-seconds (only fires while running).
    func tick(_ delta: TimeInterval) { if running { onTick?(delta) } }
}
```

- [ ] **Step 3: Write the failing contract test**

`agents/audiobook/Tests/AudiobookCoreTests/PortsTests.swift`:
```swift
import Testing
import Foundation
@testable import AudiobookCore

struct PortsTests {
    @Test func fakeAudioRecordsCalls() {
        let a = FakeAudioOutput()
        a.load("x.caf"); a.play(); a.setRate(1.5); a.seek(to: 42); a.pause()
        #expect(a.loaded == "x.caf")
        #expect(a.playCount == 1 && a.pauseCount == 1)
        #expect(a.rate == 1.5)
        #expect(a.seekedTo == 42)
    }

    @Test func fakeClockOnlyTicksWhileRunning() {
        let c = FakeClock()
        var total = 0.0
        c.tick(1)                         // not started → ignored
        c.start { total += $0 }
        c.tick(1); c.tick(2)              // running → 3
        c.stop()
        c.tick(5)                         // stopped → ignored
        #expect(total == 3)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd agents/audiobook && swift test --filter PortsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add agents/audiobook
git commit -m "feat(agent): add AudioOutputPort + ClockPort with test fakes"
```

---

### Task 3: PlayerStore — transport actions (play/pause/skip) + position advance

**Files:**
- Create: `agents/audiobook/Sources/AudiobookCore/PlayerStore.swift`
- Create: `agents/audiobook/Tests/AudiobookCoreTests/PlayerStoreTransportTests.swift`

**Interfaces:**
- Consumes: `AudioOutputPort`, `ClockPort`, `PlayerState`, `Book`, `ActionResult`.
- Produces:
  - `final class PlayerStore { init(book: Book, audio: AudioOutputPort, clock: ClockPort); private(set) var state: PlayerState }`
  - `@discardableResult func play() -> ActionResult`
  - `@discardableResult func pause() -> ActionResult`
  - `@discardableResult func skipForward(seconds: TimeInterval = 30) -> ActionResult`
  - `@discardableResult func skipBackward(seconds: TimeInterval = 30) -> ActionResult`
  - Private `func setPosition(_ p: TimeInterval)` (clamps to `0...duration`, seeks audio).
  - Position advances on clock ticks by `delta * speed`, clamped to duration (pauses at end).

- [ ] **Step 1: Write the failing test**

`agents/audiobook/Tests/AudiobookCoreTests/PlayerStoreTransportTests.swift`:
```swift
import Testing
import Foundation
@testable import AudiobookCore

private func makeStore() -> (PlayerStore, FakeAudioOutput, FakeClock) {
    let audio = FakeAudioOutput(); let clock = FakeClock()
    let store = PlayerStore(book: SampleLibrary.books[0], audio: audio, clock: clock)
    return (store, audio, clock)
}

struct PlayerStoreTransportTests {
    @Test func playStartsAudioAndClock() {
        let (s, audio, clock) = makeStore()
        #expect(s.play() == .applied)
        #expect(s.state.isPlaying == true)
        #expect(audio.isPlaying == true)
        #expect(clock.running == true)
    }

    @Test func pauseStopsAudioAndClock() {
        let (s, audio, clock) = makeStore()
        s.play(); #expect(s.pause() == .applied)
        #expect(s.state.isPlaying == false)
        #expect(audio.isPlaying == false)
        #expect(clock.running == false)
    }

    @Test func positionAdvancesByDeltaTimesSpeedWhilePlaying() {
        let (s, _, clock) = makeStore()
        s.play()
        clock.tick(10)               // speed 1.0 → +10
        #expect(s.state.position == 10)
    }

    @Test func skipForwardMovesPositionAndSeeksAudio() {
        let (s, audio, _) = makeStore()
        #expect(s.skipForward(seconds: 30) == .applied)
        #expect(s.state.position == 30)
        #expect(audio.seekedTo == 30)
    }

    @Test func skipBackwardClampsAtZero() {
        let (s, _, _) = makeStore()
        s.skipForward(seconds: 20)
        #expect(s.skipBackward(seconds: 50) == .applied)
        #expect(s.state.position == 0)
    }

    @Test func positionClampsAtDurationAndPauses() {
        let (s, _, clock) = makeStore() // duration 180
        s.play()
        clock.tick(500)
        #expect(s.state.position == 180)
        #expect(s.state.isPlaying == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agents/audiobook && swift test --filter PlayerStoreTransportTests`
Expected: FAIL — `PlayerStore` not defined.

- [ ] **Step 3: Write the minimal implementation**

`agents/audiobook/Sources/AudiobookCore/PlayerStore.swift`:
```swift
import Foundation

public final class PlayerStore {
    public private(set) var state: PlayerState
    private let audio: AudioOutputPort
    private let clock: ClockPort

    public init(book: Book, audio: AudioOutputPort, clock: ClockPort) {
        self.state = .initial(book: book)
        self.audio = audio
        self.clock = clock
        audio.load(book.audioFileName)
    }

    @discardableResult public func play() -> ActionResult {
        guard !state.isPlaying else { return .applied }
        state.isPlaying = true
        audio.play()
        clock.start { [weak self] delta in self?.advance(by: delta) }
        return .applied
    }

    @discardableResult public func pause() -> ActionResult {
        guard state.isPlaying else { return .applied }
        state.isPlaying = false
        audio.pause()
        clock.stop()
        return .applied
    }

    @discardableResult public func skipForward(seconds: TimeInterval = 30) -> ActionResult {
        setPosition(state.position + seconds)
        return .applied
    }

    @discardableResult public func skipBackward(seconds: TimeInterval = 30) -> ActionResult {
        setPosition(state.position - seconds)
        return .applied
    }

    // MARK: - internals

    private func advance(by delta: TimeInterval) {
        setPosition(state.position + delta * state.speed)
        if state.position >= state.currentBook.duration { pause() }
    }

    private func setPosition(_ p: TimeInterval) {
        let clamped = min(max(0, p), state.currentBook.duration)
        state.position = clamped
        audio.seek(to: clamped)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd agents/audiobook && swift test --filter PlayerStoreTransportTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add agents/audiobook
git commit -m "feat(agent): PlayerStore transport — play/pause/skip + position advance"
```

---

### Task 4: PlayerStore — chapter navigation

**Files:**
- Modify: `agents/audiobook/Sources/AudiobookCore/PlayerStore.swift`
- Create: `agents/audiobook/Tests/AudiobookCoreTests/PlayerStoreChapterTests.swift`

**Interfaces:**
- Consumes: existing `PlayerStore`, `PlayerState.currentChapter` (0-based).
- Produces (added to `PlayerStore`):
  - `@discardableResult func nextChapter() -> ActionResult` (no-op `.applied` if already last)
  - `@discardableResult func previousChapter() -> ActionResult` (no-op `.applied` if already first)
  - `@discardableResult func goToChapter(_ number: Int) -> ActionResult` — `number` is **1-based**; returns `.rejected` if out of range.

- [ ] **Step 1: Write the failing test**

`agents/audiobook/Tests/AudiobookCoreTests/PlayerStoreChapterTests.swift`:
```swift
import Testing
import Foundation
@testable import AudiobookCore

private func makeStore() -> PlayerStore {
    PlayerStore(book: SampleLibrary.books[0], audio: FakeAudioOutput(), clock: FakeClock())
}

struct PlayerStoreChapterTests {
    @Test func nextChapterJumpsToNextStart() {
        let s = makeStore()               // chapters at 0,60,120
        #expect(s.nextChapter() == .applied)
        #expect(s.state.position == 60)
        #expect(s.state.currentChapter == 1)
    }

    @Test func previousChapterJumpsToPriorStart() {
        let s = makeStore()
        s.goToChapter(3)                  // position 120
        #expect(s.previousChapter() == .applied)
        #expect(s.state.position == 60)
    }

    @Test func nextChapterAtLastIsNoOp() {
        let s = makeStore()
        s.goToChapter(3)
        #expect(s.nextChapter() == .applied)
        #expect(s.state.currentChapter == 2)   // unchanged (last)
    }

    @Test func goToChapterIsOneBased() {
        let s = makeStore()
        #expect(s.goToChapter(2) == .applied)
        #expect(s.state.position == 60)
        #expect(s.state.currentChapter == 1)
    }

    @Test func goToChapterOutOfRangeRejected() {
        let s = makeStore()
        if case .rejected = s.goToChapter(9) {} else { Issue.record("expected rejected") }
        if case .rejected = s.goToChapter(0) {} else { Issue.record("expected rejected") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agents/audiobook && swift test --filter PlayerStoreChapterTests`
Expected: FAIL — `nextChapter` not defined.

- [ ] **Step 3: Add the implementation**

Append to `PlayerStore` (before `// MARK: - internals`):
```swift
    @discardableResult public func nextChapter() -> ActionResult {
        let chapters = state.currentBook.chapters
        let next = state.currentChapter + 1
        guard next < chapters.count else { return .applied }   // already last → no-op
        setPosition(chapters[next].startTime)
        return .applied
    }

    @discardableResult public func previousChapter() -> ActionResult {
        let prev = state.currentChapter - 1
        guard prev >= 0 else { return .applied }               // already first → no-op
        setPosition(state.currentBook.chapters[prev].startTime)
        return .applied
    }

    /// `number` is 1-based (natural language "chapter 3").
    @discardableResult public func goToChapter(_ number: Int) -> ActionResult {
        let chapters = state.currentBook.chapters
        let index = number - 1
        guard chapters.indices.contains(index) else {
            return .rejected("chapter \(number) out of range (1...\(chapters.count))")
        }
        setPosition(chapters[index].startTime)
        return .applied
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd agents/audiobook && swift test --filter PlayerStoreChapterTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add agents/audiobook
git commit -m "feat(agent): PlayerStore chapter navigation (next/prev/goTo, 1-based)"
```

---

### Task 5: PlayerStore — speed, sleep timer, switch book

**Files:**
- Modify: `agents/audiobook/Sources/AudiobookCore/PlayerStore.swift`
- Create: `agents/audiobook/Tests/AudiobookCoreTests/PlayerStoreControlsTests.swift`

**Interfaces:**
- Consumes: existing `PlayerStore`, `SleepTimer`, `SampleLibrary`.
- Produces (added to `PlayerStore`):
  - `@discardableResult func setSpeed(_ rate: Double) -> ActionResult` — `.rejected` if outside `0.5...3.0`; on success sets `state.speed` and calls `audio.setRate`.
  - `@discardableResult func setSleepTimer(minutes: Int) -> ActionResult` — sets `fireAt = position + minutes*60`.
  - `@discardableResult func setSleepTimerEndOfChapter() -> ActionResult` — `fireAt` = next chapter start (or duration if last chapter).
  - `@discardableResult func cancelSleepTimer() -> ActionResult`
  - `@discardableResult func switchBook(title: String) -> ActionResult` — fuzzy: case-insensitive exact-or-contains match against `SampleLibrary.books`; `.rejected` if none/ambiguous; on success resets to that book's initial state and reloads audio.
  - Sleep-timer firing: when `position >= sleepTimer.fireAt` during `advance`, pause and clear the timer.

- [ ] **Step 1: Write the failing test**

`agents/audiobook/Tests/AudiobookCoreTests/PlayerStoreControlsTests.swift`:
```swift
import Testing
import Foundation
@testable import AudiobookCore

private func makeStore() -> (PlayerStore, FakeAudioOutput, FakeClock) {
    let a = FakeAudioOutput(); let c = FakeClock()
    return (PlayerStore(book: SampleLibrary.books[0], audio: a, clock: c), a, c)
}

struct PlayerStoreControlsTests {
    @Test func setSpeedWithinRangeApplies() {
        let (s, audio, _) = makeStore()
        #expect(s.setSpeed(1.5) == .applied)
        #expect(s.state.speed == 1.5)
        #expect(audio.rate == 1.5)
    }

    @Test func setSpeedOutOfRangeRejected() {
        let (s, _, _) = makeStore()
        if case .rejected = s.setSpeed(4.0) {} else { Issue.record("expected rejected") }
        #expect(s.state.speed == 1.0)
    }

    @Test func sleepTimerMinutesFiresAndPauses() {
        let (s, _, clock) = makeStore()
        s.play()
        #expect(s.setSleepTimer(minutes: 1) == .applied)   // fireAt = 60
        #expect(s.state.sleepTimer?.fireAt == 60)
        clock.tick(59); #expect(s.state.isPlaying == true)
        clock.tick(2)
        #expect(s.state.isPlaying == false)
        #expect(s.state.sleepTimer == nil)
    }

    @Test func sleepTimerEndOfChapterTargetsNextChapter() {
        let (s, _, _) = makeStore()                         // at 0, chapters 0,60,120
        #expect(s.setSleepTimerEndOfChapter() == .applied)
        #expect(s.state.sleepTimer?.fireAt == 60)
        #expect(s.state.sleepTimer?.mode == .endOfChapter)
    }

    @Test func cancelSleepTimerClears() {
        let (s, _, _) = makeStore()
        s.setSleepTimer(minutes: 5)
        #expect(s.cancelSleepTimer() == .applied)
        #expect(s.state.sleepTimer == nil)
    }

    @Test func switchBookFuzzyMatchResetsState() {
        let (s, audio, _) = makeStore()
        s.skipForward(seconds: 30)
        #expect(s.switchBook(title: "art of war") == .applied)  // fuzzy → "The Art of War"
        #expect(s.state.currentBook.id == "art-of-war")
        #expect(s.state.position == 0)
        #expect(audio.loaded == "book-b.caf")
    }

    @Test func switchBookNoMatchRejected() {
        let (s, _, _) = makeStore()
        if case .rejected = s.switchBook(title: "nonexistent") {} else { Issue.record("expected rejected") }
        #expect(s.state.currentBook.id == "meditations")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agents/audiobook && swift test --filter PlayerStoreControlsTests`
Expected: FAIL — `setSpeed` not defined.

- [ ] **Step 3: Add the implementation**

Append to `PlayerStore` (before `// MARK: - internals`):
```swift
    @discardableResult public func setSpeed(_ rate: Double) -> ActionResult {
        guard (0.5...3.0).contains(rate) else { return .rejected("speed \(rate) outside 0.5...3.0") }
        state.speed = rate
        audio.setRate(rate)
        return .applied
    }

    @discardableResult public func setSleepTimer(minutes: Int) -> ActionResult {
        guard minutes > 0 else { return .rejected("minutes must be positive") }
        state.sleepTimer = SleepTimer(mode: .minutes(minutes),
                                      fireAt: state.position + Double(minutes) * 60)
        return .applied
    }

    @discardableResult public func setSleepTimerEndOfChapter() -> ActionResult {
        let chapters = state.currentBook.chapters
        let next = state.currentChapter + 1
        let fireAt = next < chapters.count ? chapters[next].startTime : state.currentBook.duration
        state.sleepTimer = SleepTimer(mode: .endOfChapter, fireAt: fireAt)
        return .applied
    }

    @discardableResult public func cancelSleepTimer() -> ActionResult {
        state.sleepTimer = nil
        return .applied
    }

    @discardableResult public func switchBook(title: String) -> ActionResult {
        let q = title.lowercased()
        let matches = SampleLibrary.books.filter {
            $0.title.lowercased() == q || $0.title.lowercased().contains(q)
        }
        guard matches.count == 1, let book = matches.first else {
            return .rejected("no unique book matches \"\(title)\"")
        }
        let wasPlaying = state.isPlaying
        if wasPlaying { pause() }
        state = .initial(book: book)
        audio.load(book.audioFileName)
        return .applied
    }
```

Then update `advance(by:)` to fire the sleep timer — replace the existing method body:
```swift
    private func advance(by delta: TimeInterval) {
        setPosition(state.position + delta * state.speed)
        if let timer = state.sleepTimer, state.position >= timer.fireAt {
            state.sleepTimer = nil
            pause()
            return
        }
        if state.position >= state.currentBook.duration { pause() }
    }
```

- [ ] **Step 4: Run the full core test suite**

Run: `cd agents/audiobook && swift test`
Expected: PASS (all tasks 1–5 tests green; nothing regressed).

- [ ] **Step 5: Commit**

```bash
git add agents/audiobook
git commit -m "feat(agent): PlayerStore speed, sleep timer, switch book"
```

---

### Task 6: ActionSchema + schema/methods consistency test

**Files:**
- Create: `agents/audiobook/Sources/AudiobookCore/ActionSchema.swift`
- Create: `agents/audiobook/Tests/AudiobookCoreTests/ActionSchemaTests.swift`

**Interfaces:**
- Consumes: nothing (a static description).
- Produces:
  - `struct ActionParameter: Equatable, Sendable { let name: String; let type: String; let required: Bool }`
  - `struct ActionSpec: Equatable, Sendable { let name: String; let parameters: [ActionParameter]; let verifies: String }`
  - `enum ActionSchema { static let actions: [ActionSpec]; static func json() -> String }`
  - The 11 actions exactly: `play, pause, skipForward, skipBackward, nextChapter, previousChapter, goToChapter, setSpeed, setSleepTimer, cancelSleepTimer, switchBook`.

- [ ] **Step 1: Write the schema**

`agents/audiobook/Sources/AudiobookCore/ActionSchema.swift`:
```swift
import Foundation

public struct ActionParameter: Equatable, Sendable {
    public let name: String
    public let type: String        // "int" | "double" | "string" | "bool"
    public let required: Bool
    public init(name: String, type: String, required: Bool) {
        self.name = name; self.type = type; self.required = required
    }
}

public struct ActionSpec: Equatable, Sendable {
    public let name: String
    public let parameters: [ActionParameter]
    public let verifies: String    // human-readable state assertion the harness checks
    public init(name: String, parameters: [ActionParameter], verifies: String) {
        self.name = name; self.parameters = parameters; self.verifies = verifies
    }
}

/// The machine-readable contract the decide-model (Sub-project B) targets and the
/// harness verifies against. Mirrors PlayerStore exactly (see ActionSchemaTests).
public enum ActionSchema {
    public static let actions: [ActionSpec] = [
        ActionSpec(name: "play", parameters: [], verifies: "isPlaying == true"),
        ActionSpec(name: "pause", parameters: [], verifies: "isPlaying == false"),
        ActionSpec(name: "skipForward",
                   parameters: [ActionParameter(name: "seconds", type: "double", required: false)],
                   verifies: "position increased by ~seconds"),
        ActionSpec(name: "skipBackward",
                   parameters: [ActionParameter(name: "seconds", type: "double", required: false)],
                   verifies: "position decreased by ~seconds"),
        ActionSpec(name: "nextChapter", parameters: [], verifies: "currentChapter + 1"),
        ActionSpec(name: "previousChapter", parameters: [], verifies: "currentChapter - 1"),
        ActionSpec(name: "goToChapter",
                   parameters: [ActionParameter(name: "chapter", type: "int", required: true)],
                   verifies: "currentChapter == chapter (1-based)"),
        ActionSpec(name: "setSpeed",
                   parameters: [ActionParameter(name: "rate", type: "double", required: true)],
                   verifies: "speed == rate"),
        ActionSpec(name: "setSleepTimer",
                   parameters: [ActionParameter(name: "minutes", type: "int", required: false),
                                ActionParameter(name: "endOfChapter", type: "bool", required: false)],
                   verifies: "sleepTimer active with target"),
        ActionSpec(name: "cancelSleepTimer", parameters: [], verifies: "sleepTimer == nil"),
        ActionSpec(name: "switchBook",
                   parameters: [ActionParameter(name: "title", type: "string", required: true)],
                   verifies: "currentBook == matched book"),
    ]

    public static func json() -> String {
        let objs: [[String: Any]] = actions.map { spec in
            [
                "name": spec.name,
                "verifies": spec.verifies,
                "parameters": spec.parameters.map {
                    ["name": $0.name, "type": $0.type, "required": $0.required] as [String: Any]
                },
            ]
        }
        let data = try! JSONSerialization.data(withJSONObject: objs,
                                               options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
```

- [ ] **Step 2: Write the failing consistency test**

`agents/audiobook/Tests/AudiobookCoreTests/ActionSchemaTests.swift`:
```swift
import Testing
import Foundation
@testable import AudiobookCore

struct ActionSchemaTests {
    @Test func hasExactlyTheElevenActions() {
        let names = Set(ActionSchema.actions.map(\.name))
        #expect(names == Set([
            "play", "pause", "skipForward", "skipBackward", "nextChapter",
            "previousChapter", "goToChapter", "setSpeed", "setSleepTimer",
            "cancelSleepTimer", "switchBook",
        ]))
        #expect(ActionSchema.actions.count == 11)
    }

    @Test func everyActionHasAVerifyClause() {
        for spec in ActionSchema.actions { #expect(!spec.verifies.isEmpty) }
    }

    @Test func goToChapterParamIsRequiredInt() {
        let spec = ActionSchema.actions.first { $0.name == "goToChapter" }!
        #expect(spec.parameters == [ActionParameter(name: "chapter", type: "int", required: true)])
    }

    @Test func jsonIsValidAndContainsAllActions() {
        let json = ActionSchema.json()
        let parsed = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        #expect(parsed.count == 11)
    }
}
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `cd agents/audiobook && swift test --filter ActionSchemaTests`
Expected: PASS (4 tests).

- [ ] **Step 4: Commit**

```bash
git add agents/audiobook
git commit -m "feat(agent): machine-readable ActionSchema + consistency tests"
```

---

### Task 7: Sample audio + AVFoundation/clock adapters

**Files:**
- Create: `agents/audiobook/Scripts/make-samples.sh`
- Create: `agents/audiobook/Sources/AudiobookApp/Resources/book-a.caf`, `book-b.caf` (generated by the script)
- Create: `agents/audiobook/Sources/AudiobookApp/AudioOutputAdapter.swift`
- Create: `agents/audiobook/Sources/AudiobookApp/SystemClock.swift`
- Modify: `agents/audiobook/Package.swift` (add the `AudiobookApp` executable target + its resources)

**Interfaces:**
- Consumes: `AudioOutputPort`, `ClockPort`.
- Produces:
  - `final class AudioOutputAdapter: AudioOutputPort` (wraps `AVAudioPlayer`, resolves files from `Bundle.module`).
  - `final class SystemClock: ClockPort` (a repeating `Timer`/`DispatchSourceTimer` firing ~4×/sec, delivering real elapsed deltas).

- [ ] **Step 1: Create the sample-audio generator (license-free)**

`agents/audiobook/Scripts/make-samples.sh`:
```bash
#!/usr/bin/env bash
# Generate two short license-free audio files as stand-in audiobook content.
# Uses macOS `say` (built-in TTS) so the demo plays real spoken audio, no downloads.
# Resources MUST live inside the AudiobookApp target dir for SwiftPM to bundle them.
set -euo pipefail
DEST="$(dirname "$0")/../Sources/AudiobookApp/Resources"
mkdir -p "$DEST"
say -v Daniel -o "$DEST/book-a.caf" "Meditations, by Marcus Aurelius. Book one. Book two. Book three."
say -v Daniel -o "$DEST/book-b.caf" "The Art of War, by Sun Tzu. Laying plans. Waging war. The sheathed sword."
echo "Wrote book-a.caf and book-b.caf to $DEST"
```
Run it: `chmod +x agents/audiobook/Scripts/make-samples.sh && agents/audiobook/Scripts/make-samples.sh`
(The fixed `duration`/`chapters` in `SampleLibrary` are the demo's logical timeline; they need not equal the TTS clip length — the logical player drives state, the audio is the side effect. This matches the spec: state is the source of truth.)

- [ ] **Step 2: Add the AudiobookApp target to Package.swift**

Replace the `targets:` array in `agents/audiobook/Package.swift` so the executable target is now declared (it has sources as of this task) with its bundled resources:
```swift
    targets: [
        .target(name: "AudiobookCore"),
        .executableTarget(
            name: "AudiobookApp",
            dependencies: ["AudiobookCore"],
            resources: [.copy("Resources")]   // Sources/AudiobookApp/Resources
        ),
        .testTarget(name: "AudiobookCoreTests", dependencies: ["AudiobookCore"]),
    ]
```
Run `cd agents/audiobook && swift build --target AudiobookCore` to confirm the package still resolves (the `AudiobookApp` target won't fully link until Task 8 adds `@main` — that is expected this task).

- [ ] **Step 3: Write the audio adapter**

`agents/audiobook/Sources/AudiobookApp/AudioOutputAdapter.swift`:
```swift
import Foundation
import AVFoundation
import AudiobookCore

final class AudioOutputAdapter: AudioOutputPort {
    private var player: AVAudioPlayer?

    func load(_ fileName: String) {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext,
                                          subdirectory: "Resources")
            ?? Bundle.module.url(forResource: base, withExtension: ext) else {
            print("audio resource not found: \(fileName)")
            player = nil
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.prepareToPlay()
    }

    func play() { player?.play() }
    func pause() { player?.pause() }
    func seek(to seconds: TimeInterval) { player?.currentTime = min(seconds, player?.duration ?? seconds) }
    func setRate(_ rate: Double) { player?.rate = Float(rate) }
}
```

- [ ] **Step 4: Write the system clock**

`agents/audiobook/Sources/AudiobookApp/SystemClock.swift`:
```swift
import Foundation
import AudiobookCore

final class SystemClock: ClockPort {
    private var timer: Timer?
    private var last: Date?

    func start(onTick: @escaping (TimeInterval) -> Void) {
        last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let last = self.last else { return }
            let now = Date()
            onTick(now.timeIntervalSince(last))
            self.last = now
        }
    }

    func stop() { timer?.invalidate(); timer = nil; last = nil }
}
```

- [ ] **Step 5: Build to verify adapters compile**

Run: `cd agents/audiobook && swift build 2>&1 | tee /tmp/abuild.txt; true`
Expected: **no compilation errors mentioning `AudioOutputAdapter.swift` or `SystemClock.swift`.** A link-stage error about a missing entry point / `_main` (because `@main` is not added until Task 8) is EXPECTED and acceptable at this task. Confirm with:
`grep -iE "AudioOutputAdapter|SystemClock" /tmp/abuild.txt | grep -i error || echo "no adapter compile errors"`
Expected output: `no adapter compile errors`.

- [ ] **Step 6: Commit**

```bash
git add agents/audiobook
git commit -m "feat(agent): sample audio generator + AVFoundation/clock adapters"
```

---

### Task 8: SwiftUI shell — library + now-playing + controls (manual verify)

**Files:**
- Create: `agents/audiobook/Sources/AudiobookApp/PlayerViewModel.swift`
- Create: `agents/audiobook/Sources/AudiobookApp/LibraryView.swift`
- Create: `agents/audiobook/Sources/AudiobookApp/NowPlayingView.swift`
- Create: `agents/audiobook/Sources/AudiobookApp/main.swift`

**Interfaces:**
- Consumes: `PlayerStore`, `PlayerState`, `SampleLibrary`, `AudioOutputAdapter`, `SystemClock`.
- Produces:
  - `@MainActor final class PlayerViewModel: ObservableObject { @Published var state: PlayerState; ... }` wrapping a `PlayerStore`, re-publishing `state` after each action and on a display refresh while playing.
  - SwiftUI views; `main.swift` with `@main struct AudiobookAgentApp: App`.

- [ ] **Step 1: Write the view model**

`agents/audiobook/Sources/AudiobookApp/PlayerViewModel.swift`:
```swift
import Foundation
import Combine
import AudiobookCore

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var state: PlayerState
    private let store: PlayerStore
    private var refresh: Timer?

    init() {
        let s = PlayerStore(book: SampleLibrary.books[0],
                            audio: AudioOutputAdapter(), clock: SystemClock())
        self.store = s
        self.state = s.state
    }

    private func sync() { state = store.state }

    func play()  { store.play();  startRefresh(); sync() }
    func pause() { store.pause(); stopRefresh();  sync() }
    func skipForward()  { store.skipForward();  sync() }
    func skipBackward() { store.skipBackward(); sync() }
    func nextChapter()  { store.nextChapter();  sync() }
    func previousChapter() { store.previousChapter(); sync() }
    func goToChapter(_ n: Int) { store.goToChapter(n); sync() }
    func setSpeed(_ r: Double) { store.setSpeed(r); sync() }
    func setSleepTimer(minutes: Int) { store.setSleepTimer(minutes: minutes); sync() }
    func setSleepTimerEndOfChapter() { store.setSleepTimerEndOfChapter(); sync() }
    func cancelSleepTimer() { store.cancelSleepTimer(); sync() }
    func switchBook(_ title: String) { store.switchBook(title: title); sync() }

    private func startRefresh() {
        refresh = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }
    private func stopRefresh() { refresh?.invalidate(); refresh = nil }
}
```

- [ ] **Step 2: Write the now-playing view**

`agents/audiobook/Sources/AudiobookApp/NowPlayingView.swift`:
```swift
import SwiftUI
import AudiobookCore

struct NowPlayingView: View {
    @ObservedObject var vm: PlayerViewModel

    var body: some View {
        let s = vm.state
        VStack(spacing: 16) {
            Text(s.currentBook.title).font(.title2).bold()
            Text(s.currentBook.author).foregroundStyle(.secondary)
            Text("Chapter \(s.currentChapter + 1): \(s.currentBook.chapters[s.currentChapter].title)")
            Text(timeString(s.position) + " / " + timeString(s.currentBook.duration))
                .monospacedDigit()

            HStack(spacing: 12) {
                Button("⏪ 30") { vm.skipBackward() }
                Button(s.isPlaying ? "⏸ Pause" : "▶︎ Play") { s.isPlaying ? vm.pause() : vm.play() }
                Button("30 ⏩") { vm.skipForward() }
            }
            HStack(spacing: 12) {
                Button("⏮ Chapter") { vm.previousChapter() }
                Button("Chapter ⏭") { vm.nextChapter() }
            }
            HStack(spacing: 8) {
                Text("Speed \(String(format: "%.1f×", s.speed))")
                ForEach([0.75, 1.0, 1.5, 2.0], id: \.self) { r in
                    Button(String(format: "%.2g×", r)) { vm.setSpeed(r) }
                }
            }
            HStack(spacing: 8) {
                Button("Sleep 15m") { vm.setSleepTimer(minutes: 15) }
                Button("Sleep: end of chapter") { vm.setSleepTimerEndOfChapter() }
                Button("Cancel sleep") { vm.cancelSleepTimer() }
            }
            if let t = s.sleepTimer {
                Text("Sleep timer set (fires at \(timeString(t.fireAt)))").font(.caption)
            }
        }
        .padding()
        .frame(minWidth: 420)
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
```

- [ ] **Step 3: Write the library view + app entry**

`agents/audiobook/Sources/AudiobookApp/LibraryView.swift`:
```swift
import SwiftUI
import AudiobookCore

struct LibraryView: View {
    @ObservedObject var vm: PlayerViewModel

    var body: some View {
        HStack(spacing: 0) {
            List(SampleLibrary.books) { book in
                Button {
                    vm.switchBook(book.title)
                } label: {
                    VStack(alignment: .leading) {
                        Text(book.title).bold()
                        Text(book.author).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(width: 220)
            Divider()
            NowPlayingView(vm: vm)
        }
        .frame(minHeight: 360)
    }
}
```

`agents/audiobook/Sources/AudiobookApp/main.swift`:
```swift
import SwiftUI

@main
struct AudiobookAgentApp: App {
    @StateObject private var vm = PlayerViewModel()
    var body: some Scene {
        WindowGroup("Audiobook Agent") {
            LibraryView(vm: vm)
        }
    }
}
```

- [ ] **Step 4: Build the app**

Run: `cd agents/audiobook && swift build`
Expected: builds clean.

- [ ] **Step 5: Manual verification on the Mac**

Run: `cd agents/audiobook && swift run AudiobookApp`
Verify by hand (spec success criteria 1–2):
1. App window opens; the two sample books are listed.
2. Click a book → it becomes current; Play → real spoken audio plays and the time advances.
3. Each control changes the displayed state correctly: skip ±30, next/prev chapter, speed buttons, sleep-timer set/cancel, switch book resets to 0:00 and loads the other title.
4. Let a "Sleep 15m"… (for a quick check, the core test already proves firing; manually confirm "Sleep: end of chapter" shows a fire time at the next chapter boundary).

Record the result in the brick's BRICKS.md entry ("Manual (Mac): …").

- [ ] **Step 6: Commit**

```bash
git add agents/audiobook
git commit -m "feat(agent): SwiftUI shell — library + now-playing + 11 controls"
```

---

## Self-Review

**1. Spec coverage:**
- App shell (functional player, real audio) → Tasks 1, 7, 8. ✓
- 11-action schema, all verifiable → `PlayerStore` Tasks 3–5; `ActionSchema` Task 6. ✓
- Ports-and-adapters, pure tested core → Tasks 2–6 (core+fakes), Task 7 (adapters), Task 8 (UI). ✓
- Real audio bundled samples → Task 7. ✓
- New `agents/audiobook/` folder + STRUCTURE.md → Task 1. ✓
- `ActionSchema` machine-readable, B-ready → Task 6 (`json()` + consistency test). ✓
- Testing: core unit-tested with fakes, schema consistency, adapters/UI manual → Tasks 2–6 / 7–8. ✓
- Out-of-scope items (no AI, no import, no persistence, no extra actions) → respected; no task adds them. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to" — each step ships real code and exact commands. ✓

**3. Type consistency:** `PlayerStore` method names match across Tasks 3–8 and the `ActionSchema` names (Task 6) and the view model calls (Task 8). `currentChapter` is 0-based everywhere; `goToChapter` is 1-based at the API boundary (stated in Global Constraints and Tasks 4/6). `ActionResult`, `SleepTimer`, `Book`, `Chapter`, `PlayerState` defined once (Task 1/2) and reused. `setSleepTimerEndOfChapter()` (core) vs the schema's single `setSleepTimer{minutes|endOfChapter}` action — intentional: the schema models one action with a mode; the core exposes two typed methods the harness/UI map onto it. Noted here so it isn't read as drift. ✓
