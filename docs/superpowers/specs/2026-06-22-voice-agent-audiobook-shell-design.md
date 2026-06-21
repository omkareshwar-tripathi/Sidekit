# Sub-project A — Audiobook Agent: App Shell + Action Schema

**Date:** 2026-06-22
**Status:** Design (approved in brainstorm; pending written-spec review)
**Part of:** the Voice Agent Framework vision (see "Context" below)

## Context — the bigger vision

Sidekit is becoming the foundation for **reusable voice-driven "task agents."** Each agent is a
narrow pipeline: **listen → decide → act → verify.**

- **Listen** — a *small* Whisper model (small is enough because the command vocabulary is bounded).
- **Decide** — a small LLM that maps the spoken command to one specific function the app supports.
- **Act + verify** — a **harness** that constrains the model to a valid function, executes it, and
  then **verifies the action actually happened** before calling it done. A closed loop, not a guess.

The voice-typing / Shelf / Mirror trio of Sidekit is unchanged. This framework is a new layer above it.

**Decided build strategy:** build *one* agent end-to-end as a **real, functional native-macOS app**,
then extract the reusable framework from what actually proved necessary (no speculative abstractions).
The first agent is an **audiobook player** (matches the original "Hey Audible" example; rich,
independently-verifiable state; we own every action so verification checks real ground truth).

**Full decomposition (each its own spec → plan → bricks):**

- **A (this spec)** — App shell + action schema. *Must be first; everything targets it. No AI yet.*
- **B** — Harness + decide loop, prompt-steered baseline (off-the-shelf small model). Makes the loop
  work and produces the labeled data + accuracy bar for D.
- **C** — Listening: always-on audio + "Hey [app]" wake-word spotting + endpointing + small Whisper.
- **D** — Fine-tune the task model on data from B; swap in; measure the lift.
- **Later** — Extract the framework from what A–D proved.

This document specifies **A only.**

## Goal of Sub-project A

A real, functional SwiftUI audiobook player with honest, observable state, plus a machine-readable
**action schema** describing the 11 things the agent can do. Success = a person can use the app by
hand, and each action provably changes the state the harness will later verify.

## The action schema (the central artifact)

The schema is the contract the decide-model (B) targets and the harness (B) verifies against.
Eleven actions. Each names the state that proves it worked:

| Action | Parameters | Verifiable state after |
|---|---|---|
| `play` | — | `isPlaying == true` |
| `pause` | — | `isPlaying == false` |
| `skipForward` | `seconds` (default 30) | `position` increased by ~N |
| `skipBackward` | `seconds` (default 30) | `position` decreased by ~N |
| `nextChapter` | — | `currentChapter` + 1 |
| `previousChapter` | — | `currentChapter` − 1 |
| `goToChapter` | `chapter` (Int) | `currentChapter == chapter` |
| `setSpeed` | `rate` (0.5–3.0) | `speed == rate` |
| `setSleepTimer` | `minutes` (Int) **or** `endOfChapter` (Bool) | `sleepTimer` active with target |
| `cancelSleepTimer` | — | `sleepTimer == nil` |
| `switchBook` | `title` (fuzzy string) | `currentBook == matched book` |

Notes:
- Fuzzy phrasing ("put on the next book", "go a bit faster") is the **decide-model's** job (B).
  The app takes clean, typed parameters only. `switchBook` receives a title; the app resolves it to a
  bundled book (exact/contains match; ambiguity handling is B's concern, not A's).
- `setSleepTimer` is one action with a mode: either a minute count or `endOfChapter`. "End of chapter"
  is computable because books carry chapter time-markers.
- Parameter bounds (e.g. `rate` clamped to 0.5–3.0, `goToChapter` within range) are enforced in the
  pure core and surfaced as a typed result so the harness can distinguish "done" from "rejected".

## Architecture (ports-and-adapters, matching the repo convention)

Same discipline as Sidekit's `DictationCoordinator`: a **pure, testable core built and unit-tested
with fakes before any OS dependency exists.**

- **`PlayerState`** — a plain value type, the single source of verifiable truth:
  `currentBook`, `isPlaying`, `position` (seconds), `currentChapter`, `speed`, `sleepTimer`.
  The harness (B) will snapshot this to verify actions.
- **`PlayerStore`** — the pure core. Exposes the 11 actions as methods that mutate `PlayerState` and
  return a typed result (`applied` vs `rejected(reason)`). No AVFoundation, no wall-clock timers — it
  talks only to ports. Fully unit-testable.
- **Ports (protocols) + adapters:**
  - `AudioOutputPort` → `AVAudioPlayerAdapter` (real playback of bundled files) / `FakeAudioOutput`
    (tests). Responsibilities: load file, play, pause, seek(to:), setRate.
  - `ClockPort` → real timer adapter / `FakeClock` (tests). Drives `position` advancement and fires
    the sleep timer. Injectable clock keeps the core deterministic in tests.
- **`ActionSchema`** — a machine-readable description of the 11 actions (name, parameters, types,
  bounds). Defined now so B has a contract and a test can assert the schema stays in sync with the
  `PlayerStore` methods. **This is what makes A reusable by later sub-projects.**
- **Books / content model** — a small fixed set of bundled "books," each: title, audio file
  reference, ordered chapters (each with a title + start time). Read-only; no import/persistence in A.

## Content (real audio, bundled samples)

Ship a few short **royalty-free** audio files as books, each with a handful of chapter time-markers,
played via `AVAudioPlayer` behind `AudioOutputPort`. Real playhead = real ground truth for verify.
No user import, no remote content (keeps the fully-on-device principle and avoids scope creep).

## Where it lives & UI

- **New top-level folder `agents/audiobook/`** — its own SwiftPM package, cleanly separated from the
  shipped `mac/` app but on the same Swift / (later) WhisperKit / MLX stack. `STRUCTURE.md` is updated
  in the same brick that creates the folder (build-in-the-open, CLAUDE.md §7).
- **UI:** a real SwiftUI player — a library list (the bundled books) and a now-playing view (cover,
  title, current chapter, playhead/scrubber) with on-screen controls for all 11 actions. The UI is a
  thin layer over `PlayerStore`; it adds no logic the schema doesn't already cover.
- **App / wake-word name** is deferred to Sub-project C. A uses a code name (`AudiobookAgent`); the
  user-facing name and "Hey ___" trigger are decided when listening is built.

## Testing

TDD per brick (CLAUDE.md §2a):

- **Pure core** (`PlayerStore`, `PlayerState`, bounds, sleep-timer logic) and **`ActionSchema`** get
  unit tests with `FakeAudioOutput` + `FakeClock`. Each test asserts an action produces exactly its
  "verifiable state after" — the same checks the harness performs at runtime, so these tests
  pre-validate B.
- A schema/methods **consistency test**: every `ActionSchema` entry maps to a real `PlayerStore`
  method with matching parameters (catches drift).
- **Adapters** (`AVAudioPlayerAdapter`, real clock) and **UI** verify **manually on the Mac** per repo
  convention — audio actually plays, controls move real state.

## Explicitly out of scope for A (YAGNI)

No AI/LLM, no audio capture, no wake word (those are B/C/D). No user file import, no persistence
across launches, no streaming/remote content, no bookmarks/volume/queries (possible later schema
additions, deliberately excluded from v1). No cross-platform; macOS only.

## Success criteria

1. The app launches, lists bundled books, and plays real audio.
2. All 11 actions are invocable from the UI and each changes `PlayerState` as specified.
3. `PlayerStore` + `ActionSchema` are unit-tested green with fakes; schema/methods consistency test passes.
4. `ActionSchema` is machine-readable and ready for B to target.
5. `STRUCTURE.md` documents the new `agents/audiobook/` folder.
