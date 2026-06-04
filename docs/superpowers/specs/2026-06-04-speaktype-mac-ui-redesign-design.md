# SpeakType for Mac — UI redesign: floating pill + scratchpad

**Date:** 2026-06-04
**Status:** Design approved, pending spec review
**Scope:** A visual + interaction redesign of the existing menu-bar dictation app. Adds a
floating recording pill, a real app window with a notes scratchpad, and animation polish —
without changing the proven hold-Fn → on-device-Whisper → paste pipeline.

This builds on `2026-06-04-speaktype-mac-design.md` (the original MVP). The dictation engine,
ports-and-adapters architecture, WhisperKit transcription, and code-signing setup all carry
over unchanged unless stated below.

---

## 1. Goal & non-goals

**Goal.** Turn SpeakType from a menu-bar-only utility into a polished, modern Mac app:

1. A **floating pill** at the bottom-center of the screen that shows, at a glance, what the app
   is doing (idle / recording / transcribing / done) — like Wispr Flow.
2. A **scratchpad window**: a real app window with a sidebar of saved notes and a beautiful
   editor, where dictation can land directly.
3. **Animations** throughout — the pill morphs between states, the waveform reacts to the live
   mic level, dictated text reveals gently — all respecting Reduce Motion.

**Non-goals (this redesign).** No change to the hotkey (still hold-Fn), the speech model, the
transcription pipeline, or the signing/build scripts. No cloud, no accounts, no rich-text
formatting in notes (plain text only). No multi-window. No model picker (future work).

---

## 2. The three surfaces

The app keeps running in the background; it presents three surfaces that share one glass visual
language.

### 2.1 Menu-bar icon (kept)
Stays the always-running home (`MenuBarExtra`). Gains an **"Open SpeakType"** item that shows
the main window, plus the existing status text and Accessibility prompt.

### 2.2 Floating pill (new)
- **Where:** bottom-center of the active screen, always-on-top, floats above all apps, never
  takes focus, appears on every Space.
- **Always present, auto-dimming:** a faint breathing dot when idle; expands and brightens
  during dictation; returns to the dot afterward.
- **States & look** (visual direction **A — glass + waveform**):
  - **Idle** — a faint, slowly breathing horizontal dot/bar; low opacity.
  - **Recording** — springs open into a frosted-glass pill: a red rec dot, a **live waveform**
    (bars driven by the real mic amplitude), and "Listening…".
  - **Transcribing** — morphs to a small spinner + "Transcribing…".
  - **Success** — a green ✓ pops with the outcome ("Pasted ✓" / "Added to note ✓" /
    "On clipboard" / "No speech"), holds ~1.2 s, then collapses back to the idle dot.
- **Interaction:** clicking the pill opens/focuses the main window. (No drag in this version;
  position is fixed bottom-center.)

### 2.3 Main window (new) — layout **B, sidebar**
- **Left sidebar:** list of saved notes (newest first), each showing a title + preview line +
  relative time; a "New note" affordance; a ⚙︎ Settings entry at the bottom.
- **Right pane:** the editor for the selected note — a large, comfortable plain-text editor with
  a header (note title) and a bottom status strip mirroring the pill's mini-state.
- **Settings** (reached from the sidebar): filler-removal toggle, launch-at-login toggle,
  microphone + Accessibility permission status with a button to open System Settings.
- The window uses the same glass aesthetic; closing it leaves the app running in the menu bar.

---

## 3. How dictation routes (the core behavioral change)

Today the coordinator records → transcribes → cleans → **pastes at the cursor** (clipboard +
synthetic ⌘V) in the frontmost app, then reports an *outcome* only.

**New rule:**
- If **SpeakType's own window is the frontmost (focused) app**, the cleaned transcript is
  **appended directly into the active note** in memory (then persisted) — no clipboard, no
  synthetic keystroke. This is reliable in-app dictation. If no note is active at that moment
  (e.g. an empty notes list), a new note is created to receive the text.
- **Everywhere else**, behavior is exactly as today: paste at the cursor in the frontmost app.

### 3.1 Required core change
The pure `DictationCoordinator` must surface the **cleaned transcript text**, not just the
outcome. Today `onCompleted` carries a `DictationOutcome` (`pasted` / `leftOnClipboard` /
`noSpeech`). It will instead route the cleaned text through a new **`DictationSink` port** that
decides the destination and returns the outcome:

```swift
/// Where a finished, cleaned transcript goes. The app supplies the implementation;
/// the coordinator stays unaware of clipboards, windows, or notes.
public protocol DictationSink: AnyObject {
    /// Deliver the cleaned transcript. Returns how it was delivered, for the UI to surface.
    func deliver(_ text: String) -> DictationOutcome
}
```

- `DictationOutcome` grows one case: `.addedToNote` (alongside `.pasted`, `.leftOnClipboard`,
  `.noSpeech`).
- The coordinator replaces its direct `paste.paste(cleaned)` call with `sink.deliver(cleaned)`.
  The `Pasting` port stays; it's used *inside* one sink implementation.
- The app provides a **routing sink** that, at delivery time, checks whether SpeakType's window
  is frontmost: if so it appends to the active note (`.addedToNote`); otherwise it delegates to
  the existing paste path (`.pasted` / `.leftOnClipboard`). The frontmost-app check is an
  injected closure so the routing logic stays unit-testable with a fake.

This keeps the core pure and testable: the routing decision is one swappable piece, verifiable
with fakes (focused → appends; not focused → pastes).

---

## 4. Notes model & persistence

### 4.1 Pure model (in `SpeakTypeCore`)
```swift
public struct Note: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Title = first non-empty line, trimmed; "" → "New note" for display (UI concern).
    public var title: String { ... }
}
```

`NotesStore` is an `@MainActor` observable owner of `[Note]`:
- `newNote()` — creates an empty note, inserts it at the top, makes it active.
- `append(_ text:, to:)` — appends transcript text to a note's body (with sensible spacing),
  bumps `updatedAt`, re-sorts newest-updated-first.
- `delete(_:)`, `select(_:)`, `activeNote`.
- Emits changes for SwiftUI; calls a `NotesPersisting` port to save.

The text-manipulation rules (title derivation, spacing when appending, ordering) live in pure
functions unit-tested with no I/O.

### 4.2 Persistence port + adapter
```swift
public protocol NotesPersisting: Sendable {
    func load() -> [Note]
    func save(_ notes: [Note])
}
```
Adapter (`SpeakTypeApp`): a JSON file at
`~/Library/Application Support/SpeakType/notes.json`. Atomic write; tolerant load (missing or
corrupt file → empty list, logged via `Diag`). Saves are debounced/coalesced so rapid edits
don't thrash the disk.

---

## 5. Live audio metering (for the waveform)

The waveform must react to the real microphone level. `AVAudioCapture` currently only buffers
samples and returns them at stop. It gains a lightweight **level callback** during recording —
a published running amplitude (e.g. recent-window peak, reusing the same peak math as
`AudioMath`) emitted a few times per second on the main actor. The pill's waveform view binds to
this level; no audio is exposed beyond a single 0…1 number. This is additive — capture/stop
behavior and the existing speech-gate are untouched.

---

## 6. Visual design system

A small SwiftUI design-system file in `SpeakTypeApp` centralizes the look so the pill and window
stay consistent:
- **Material:** dark frosted glass (`.ultraThinMaterial` over a dark tint) with hairline white
  borders and soft shadows.
- **Accent:** a single accent for active/recording affordances; red reserved for the rec dot;
  green for success.
- **Typography & spacing:** a small type scale and spacing tokens.
- **Radii & shadows:** pill = full-round; window cards = ~13–16px.

Tokens are defined once and referenced everywhere; no per-view hardcoded colors.

---

## 7. App lifecycle / activation

The app is `LSUIElement` (menu-bar-only, no Dock icon) today. With a real window it switches
activation policy to **`.regular` while the main window is open** (so it appears in the Dock and
⌘-Tab and can take focus for in-app dictation), and back to **`.accessory`** when the window
closes (returning to a pure background utility). The floating pill is a non-activating panel and
never affects this.

---

## 8. Architecture summary

```
SpeakTypeCore (pure, unit-tested)
  DictationCoordinator   — now delivers cleaned text via DictationSink (+ .addedToNote outcome)
  DictationSink (port)   — destination for finished transcripts
  Note, NotesStore       — notes model + ordering/title/append rules (pure)
  NotesPersisting (port) — load/save
  (unchanged) AudioMath, TranscriptCleaner, ClipboardSafePaste, Timing, Settings, Ports

SpeakTypeApp (native adapters + SwiftUI)
  RoutingSink            — focused-window check → append-to-note OR paste-at-cursor
  PasteSink              — wraps existing ClipboardSafePaste/MacClipboard path
  JSONNotesStore adapter — notes.json in Application Support
  AVAudioCapture         — + live level callback
  DesignSystem           — glass tokens, colors, type
  PillPanel + PillView   — floating always-on-top pill, animated states
  MainWindow (Sidebar + Editor + Settings)
  AppController          — composition root, activation-policy switching
```

Data flow (recording cycle):
`Fn down → coordinator.pressed() → AVAudioCapture.start()` → live level drives pill waveform →
`Fn up → coordinator.released() → stop → transcribe → clean → sink.deliver(text)` →
RoutingSink: focused? append to active note : paste at cursor → outcome → pill success state.

---

## 9. Error handling

- **Persistence:** corrupt/missing `notes.json` → start empty, log; failed save → retry once,
  then log and keep notes in memory (never crash, never lose the in-memory copy mid-session).
- **Paste path:** unchanged — failure still falls back to `.leftOnClipboard`.
- **Pill:** purely driven by coordinator state; if metering stalls, the waveform idles but the
  state label remains correct.
- **Reduce Motion:** when enabled, all spring/morph animations degrade to simple opacity fades;
  feedback is never removed, only de-animated.

---

## 10. Testing strategy

Pure core (no hardware) is unit-tested with Swift Testing + fakes, consistent with the existing
suite:
- **DictationSink routing:** focused → `.addedToNote` & note received text; not focused →
  delegates to paste fake & returns its outcome.
- **Coordinator:** still records/transcribes/cleans; now delivers cleaned text to the sink
  (assert the sink received the cleaned string); `.noSpeech`/discard paths unchanged.
- **NotesStore:** new note inserts at top & becomes active; append adds text with correct
  spacing and bumps ordering; title = first non-empty line; delete/select behavior.
- **Persistence round-trip:** save → load returns equal notes; corrupt file → empty list.
- **Audio metering math:** level computation (reuses peak math) over sample windows.

UI/animation, the pill panel, activation-policy switching, and live mic metering are verified
**manually** (no headless UI test harness), matching the project's existing approach for native
adapters.

---

## 11. Brick plan (high level)

Pure/testable core first, then adapters, then UI, then polish — per the ports-and-adapters
discipline and CLAUDE.md §2a sizing. Domain `Skill:` lines are `none` (the `dotnet-*` skills
don't apply to Swift, per CLAUDE.md §6); TDD + verification-before-completion still apply on
every brick. The writing-plans step finalizes exact boundaries.

1. **Core — transcript + `DictationSink`**: coordinator delivers cleaned text via the sink;
   add `.addedToNote`; wrap today's paste as `PasteSink`. *(TDD)*
2. **Core — `Note` + `NotesStore`** (pure, in-memory): add/append/title/ordering. *(TDD)*
3. **Adapter — JSON persistence** (`notes.json`, atomic, tolerant, debounced).
4. **App — design-system tokens** + activation-policy switching (window-capable app).
5. **Pill panel** (borderless, always-on-top, bottom-center) wired to coordinator state — states
   without animation.
6. **Live audio metering** from `AVAudioCapture` → pill waveform level.
7. **Pill animations** — spring morphs, waveform, spinner, ✓; Reduce Motion fallback.
8. **Main window shell** — sidebar + editor, glass styling, selection.
9. **Route dictation into the focused note** via `RoutingSink` — in-app dictation end-to-end.
10. **Settings + note management** — filler removal, launch-at-login, permission status,
    new/delete note.
11. **Polish pass** — window transitions, transcript reveal, empty states.

Each brick: make → review → test → verify → update `BRICKS.md` (archive per §2b).

---

## 12. Open questions / future work

Deferred (not in this redesign): draggable pill / position memory; per-note model picker;
search across notes; export; notarized distribution; iCloud sync. These start from the sidebar
app once this redesign lands.
