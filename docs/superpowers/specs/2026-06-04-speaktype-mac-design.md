# SpeakType for Mac — Native Swift MVP Design

**Date:** 2026-06-04
**Branch:** `feat/mac-app` (off `main`)
**Status:** Approved design — ready for implementation plan

## 1. Goal

A native macOS menu-bar dictation app for Apple Silicon with the same core loop as
the Windows app: **hold the Fn (🌐) key → record → transcribe on-device → paste the
text into the focused app.** It is built as a flagship-native macOS app in Swift, not
a port of the C# code.

### Product decision: this is a fork

The user chose "Mac is the flagship; native quality matters most." SpeakType is
therefore intentionally **two codebases**: the existing C#/.NET Windows app and this
new native Swift macOS app. They share product *behavior* but not code. Dictation
logic that changes in one must be changed in the other; they will drift, and that is
accepted in exchange for best-in-class native Mac quality (Neural-Engine Whisper,
native input/paste, no interop bridges). The C# `SpeakType.*` projects and the
Windows app are untouched by this work.

## 2. Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| Language / approach | **Native Swift** | Flagship-native quality; removes all C# P/Invoke interop risk. |
| UI framework | **SwiftUI** (`MenuBarExtra`) | Modern, minimal code for a menu-bar app; drop to AppKit/CoreGraphics only where needed. |
| Speech engine | **WhisperKit** (CoreML / Neural Engine) | Fastest on-device option on Apple Silicon; pure-Swift package; manages its own models. |
| Build setup | **SwiftPM executable + `build-app.sh`** | All plain text (`Package.swift`) — clean for git and brick-by-brick edits. No binary project file. |
| Push-to-talk key | **Hold Fn (🌐), hard-coded** | Ergonomic, matches premium dictation apps. Configurable hotkey is a later brick. |
| Distribution | **Local dev, ad-hoc signed, arm64** | Run on the developer's Mac; grant permissions manually. Notarization/`.dmg` is later. |
| Scope | **Core dictation MVP** | Prove the native plumbing end-to-end before polish features. |

## 3. Architecture

Keep the discipline that made the Windows app solid: a **pure, fully-tested
coordinator** behind **protocol "ports,"** with thin **native adapters**. The pure
layer has no system-framework dependencies and is unit-tested with fakes; the
adapters are verified by manual tests on the machine.

```
SpeakTypeMac/
  Package.swift                      # dependency: WhisperKit
  Sources/
    SpeakTypeCore/   (pure Swift, no system frameworks → unit-testable)
      DictationCoordinator.swift     # state machine (mirrors C# DictationOrchestrator)
      TranscriptCleaner.swift
      Settings.swift
      Ports.swift                    # protocols: AudioCapturing, HotkeyListening,
                                     #            Pasting, Transcribing
    SpeakTypeApp/    (executable target: native adapters + SwiftUI shell)
      App.swift                      # @main, MenuBarExtra, composition root
      Adapters/
        AVAudioCapture.swift         # AudioCapturing
        FnKeyMonitor.swift           # HotkeyListening
        MacPaste.swift               # Pasting (NSPasteboard + CGEvent ⌘V)
        WhisperKitTranscriber.swift  # Transcribing
      UI/
        MenuBarView.swift            # status + Quit
  Tests/
    SpeakTypeCoreTests/              # Swift Testing, fake ports
  Scripts/
    build-app.sh                     # assemble SpeakType.app (Info.plist, ad-hoc sign)
```

### Ports (protocols, in `SpeakTypeCore`)

```
protocol AudioCapturing {            // 16 kHz mono Float32 capture
    func start()
    func stop() -> CapturedAudio     // (samples: [Float], hasSpeech: Bool)
}
protocol HotkeyListening {           // push-to-talk source
    var onPressed: (() -> Void)? { get set }
    var onReleased: (() -> Void)? { get set }
}
protocol Pasting {                   // insert text into focused app, or leave on clipboard
    func paste(_ text: String) -> PasteOutcome   // .pasted | .leftOnClipboard
}
protocol Transcribing {
    func transcribe(_ samples: [Float]) async -> String
}
```

These mirror the C# `IAudioCapture`, `IHotkeyListener`, `IPasteService`, and
`ITranscriber`, so the coordinator's logic transfers one-to-one.

## 4. The coordinator (the tested heart)

`DictationCoordinator` ports the Windows `DictationOrchestrator`:

- **Fn press** → start capture, arm a 60 s auto-stop timer, state → `recording`.
- **Fn release** → if held ≥ **300 ms**, run `capture → transcribe → clean → paste`
  and report the outcome; if held < 300 ms, discard as an accidental tap.
- **60 s auto-stop** → end the hold and run the cycle (same path as release).
- Concurrent triggers (release racing the auto-stop) are resolved by a single atomic
  state claim, exactly as in the C# version.

**Concurrency:** state is serialized through a Swift `actor` (or a serial dispatch
queue), so the hotkey callback thread, the auto-stop timer, and the async
transcribe/paste task never race on state. Transcription is `async` (WhisperKit is
async); the coordinator awaits it off the main actor and marshals UI status updates
back to the main actor for the menu bar.

The coordinator is driven entirely through the four protocols, so it is unit-tested
with fake ports — the analogue of `DictationOrchestratorTests`. Tests cover:
accidental-tap discard, normal cycle, no-speech path, auto-stop, and the
release/auto-stop race.

## 5. The four native adapters

| Port | Adapter | Native API & notes |
|---|---|---|
| `AudioCapturing` | `AVAudioCapture` | `AVAudioEngine` input-node tap → `AVAudioConverter` to 16 kHz mono Float32; RMS silence gate sets `hasSpeech`. Microphone prompt is triggered by starting the engine, given `NSMicrophoneUsageDescription` in the bundle. |
| `HotkeyListening` | `FnKeyMonitor` | Watches global `flagsChanged` events for the `.function` (Fn/🌐) modifier flag: flag on → `onPressed`, flag off → `onReleased`. **If another key is pressed while Fn is held, the in-flight press is aborted** (Fn used as a modifier, not dictation). Needs an input-monitoring/Accessibility permission — already required for paste, so no extra burden. |
| `Pasting` | `MacPaste` | Clipboard-safe sequence (mirrors C# `ClipboardPasteService`): save current pasteboard text → set our text → synthesize **⌘V** via `CGEvent` → wait ~150 ms → restore original (or clear). If the keystroke can't be posted, leave text on the clipboard (`.leftOnClipboard`). Needs **Accessibility** permission. The save→paste→restore *logic* lives in `SpeakTypeCore` and is unit-tested against a fake pasteboard; only the `NSPasteboard`/`CGEvent` primitives live in the adapter. |
| `Transcribing` | `WhisperKitTranscriber` | Loads a WhisperKit model (downloads its CoreML model on first run) and transcribes the 16 kHz samples on the Neural Engine. |

## 6. Permissions & the `.app` bundle

macOS grants permissions to a *bundle*, not a loose binary, so even for local dev
`build-app.sh` assembles **`SpeakType.app`**:

- `Info.plist` with:
  - `NSMicrophoneUsageDescription` — text shown in the mic prompt (fires on first record).
  - `LSUIElement = true` — menu-bar-only app, no Dock icon.
  - `CFBundleIdentifier`, version, executable name.
- **Ad-hoc code-sign** (`codesign -s -`) so macOS reliably associates the granted
  TCC permissions with a stable identity across rebuilds.

**Accessibility** (for the ⌘V keystroke and Fn monitoring) is granted once by the
user in **System Settings → Privacy & Security → Accessibility**. The app detects
when it is missing (`AXIsProcessTrusted()`) and shows a menu-bar message telling the
user to grant it.

**Fn-key system conflict:** macOS's "Press 🌐 key to…" setting can make Fn trigger the
emoji picker / input-source switch. The app advises the user (in the menu / first-run
note) to set **System Settings → Keyboard → "Press 🌐 key to" → Do Nothing.** The
300 ms min-hold guard already discards the accidental taps that would otherwise fire
that action.

## 7. Brick sequence (MVP)

Each brick is reviewed, tested, and verified before the next (CLAUDE.md §2a). Domain
`Skill:` lines are mostly `none` because the repo's `dotnet-*` skills do not apply to
Swift (CLAUDE.md §6 anticipated this); the process skills (TDD, verification) still apply.

1. **MAC-1 — Scaffold + bundle.** `Package.swift`, `SpeakTypeCore` skeleton (ports +
   empty coordinator), `SpeakTypeApp` with a `MenuBarExtra` showing a static icon +
   Quit, `build-app.sh` producing a runnable `SpeakType.app`, and a green test target.
   *Verify:* `swift build` + `swift test` pass; the assembled app shows a menu-bar icon
   and quits. *Skill: test-driven-development, verification-before-completion (domain: none).*
2. **MAC-2 — Pure core.** `DictationCoordinator` + `TranscriptCleaner` + `Settings`
   with fake ports and full unit tests (mirror `DictationOrchestratorTests`). No system
   frameworks. *Verify:* all coordinator state-transition tests green. *Skill: test-driven-development.*
3. **MAC-3 — Paste.** `MacPaste` adapter + the clipboard-safe sequence (pure sequence
   logic unit-tested against a fake pasteboard). *Verify:* unit tests green; manual
   paste into TextEdit. *Skill: test-driven-development.*
4. **MAC-4 — Fn hotkey.** `FnKeyMonitor` (flagsChanged on `.function`, with the
   modifier-abort rule). *Verify:* manual — menu shows "recording" while Fn is held,
   stops on release; pressing another key while held aborts. *Skill: none.*
5. **MAC-5 — Audio.** `AVAudioCapture` (16 kHz mono float + RMS silence gate + mic
   permission). *Verify:* manual — mic prompt appears; speaking produces non-silent
   samples, silence is gated. *Skill: none.*
6. **MAC-6 — Whisper + wiring.** `WhisperKitTranscriber` + composition root wiring the
   coordinator end-to-end, with menu-bar status (idle / recording / transcribing).
   *Verify:* manual — hold Fn, speak, release, text appears in TextEdit. *Skill: none.*
7. **MAC-7 — Finalize permissions & docs.** Finalize `Info.plist`/entitlements,
   `AXIsProcessTrusted` messaging, and a `README`/permissions doc; full manual
   end-to-end test pass. *Verify:* clean-machine-style run with both permission prompts.
   *Skill: verification-before-completion.*

## 8. Testing strategy

- **Pure core** (`SpeakTypeCore`): unit-tested with fake ports via **Swift Testing**
  (Swift 6.2). Covers the coordinator state machine, transcript cleaner, and the
  clipboard-safe paste sequence.
- **Adapters**: the native-API code (AVAudioEngine, CGEvent, flagsChanged, WhisperKit)
  is verified by **manual tests** on the Mac, documented per brick.
- **Manual end-to-end** (MAC-7): mic prompt → Accessibility prompt → hold Fn → speak →
  release → text pasted into TextEdit → original clipboard restored → no-speech path.

## 9. Out of scope (follow-on bricks)

- CoEdIT text polishing (would need ONNX Runtime or a CoreML conversion in Swift).
- Recording overlay window.
- Rich settings UI / configurable hotkey / onboarding.
- Autostart on login (`SMAppService`).
- Code signing with a Developer ID, notarization, `.dmg` packaging.
- Intel (x86_64) support.

## 10. Risks

- **WhisperKit first-run model download** requires network and disk; the MVP accepts a
  first-run download (bundling a model is a later option).
- **Fn-key system behavior** varies with the user's "Press 🌐 key to…" setting; mitigated
  by advising "Do Nothing" and the 300 ms min-hold guard.
- **Permission attribution** depends on a correctly-formed, ad-hoc-signed `.app` bundle;
  this is why MAC-1 builds the bundle up front rather than running a loose binary.
