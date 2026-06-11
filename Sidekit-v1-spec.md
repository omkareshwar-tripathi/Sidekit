# SpeakType — Product Spec (v1)

**What it is:** A Windows app that turns your voice into clean, formatted text. Hold a hotkey, speak, release — your words appear at your cursor, anywhere you can type.

**Who it's for:** Professionals who send a high volume of messages (Slack, email, chat) and want to talk instead of type.

**Platform:** Windows 10/11, x64. Built in C# / .NET 8. Runs from the system tray.

> **Status of this document.** This is the complete v1 engineering spec. Every feature below states its exact behavior, edge cases, the technology choice behind it, and how it is tested. Decisions captured here were resolved in a design grilling session; the "Resolved decisions" appendix at the end is the quick-reference index.

---

## Core Flow

1. User holds a global hotkey (default **Right Ctrl**).
2. User speaks while holding it (push-to-talk). A small on-screen overlay shows **🎙 Listening…**.
3. User releases the hotkey. Overlay shows **⚙ Transcribing…**.
4. App transcribes the speech locally with Whisper (on a background thread).
5. App cleans up the text (filler removal + fixups + formatting).
6. App pastes the result at the current cursor position — in any app — using a clipboard-safe paste, then the overlay fades out.

The runtime is a strict state machine: **Idle → Recording → Transcribing → Pasting → Idle**. Hotkey presses received in any non-Idle state are ignored (no queueing in v1).

---

## Technology Stack (resolved)

| Concern | Choice | Notes |
|---|---|---|
| Runtime | **.NET 8 (LTS)**, **x64 only** | win-arm64 deferred past v1. |
| Project structure | **`SpeakType.Core`** (`net8.0`) + **`SpeakType.App`** (`net8.0-windows`, WinForms) + **`SpeakType.Tests`** (`net8.0`) | Core holds all pure logic + port interfaces and builds/tests on **macOS or Windows**; App holds Win32/NAudio/Whisper adapters + UI and builds on **Windows only**; Tests reference Core only. Enables a two-machine dev flow: write+unit-test the core on a Mac, build+run the real app on Windows, Git as the bridge. CI runs on GitHub Actions `windows-latest`. |
| UI | **WinForms** | Built-in `NotifyIcon` for tray; lightest path for a tray utility. In `SpeakType.App` only. |
| Speech-to-text | **Whisper.NET** (`Whisper.net` + `Whisper.net.Runtime`) | Managed wrapper over whisper.cpp; CPU by default; no native build to own. |
| Audio capture | **NAudio** | Capture from default input device; resample to 16 kHz mono float. |
| Packaging | **Self-contained, single-file `win-x64` `.exe`** | Bundles .NET 8 (runs on a clean machine). No installer in v1. App is **unsigned** in v1 → users will see a Windows SmartScreen warning on first launch (accepted). |
| Settings store | **`%APPDATA%\SpeakType\settings.json`** | Human-readable JSON; changes apply immediately (no Save button). |
| Single instance | **Named mutex `SpeakType.Single`** | Second launch shows a balloon and exits (prevents two global hooks). |

Publish command (reference):
```
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

---

## Feature 1 — Push-to-Talk Hotkey

**Behavior**
- Mechanism: a **low-level keyboard hook (`WH_KEYBOARD_LL`)**. (Win32 `RegisterHotKey` cannot give clean key-down/key-up needed for push-to-talk.)
- **Default key: Right Ctrl**, a single key. The bound key is **suppressed** (swallowed) while held, so it never leaks into the focused app.
- **Hold to record, release to transcribe.**

**Hold-duration guards**
- Hold **< 300 ms** → treated as an accidental tap: discard, no transcription, no paste.
- Hold ≥ 300 ms and **< 60 s** → normal recording.
- Hold reaching **60 s** → auto-stop, then transcribe what was captured (bounds memory/latency).
- Both thresholds are constants, tunable in code.

**Rebinding (Settings)**
- Allowed bindings: bare **modifier keys** (Right/Left Ctrl, Right/Left Alt, Shift), **F13–F24**, **Pause/Break**, OR **any modifier + key combo**.
- **Disallowed:** bare letter/digit keys (would break typing that character). Settings rejects these with an inline message.
- The bound key/combo is **always suppressed while held**.
- Rebinding re-registers the hook live (no restart).

**Pause**
- Tray "Pause listening" stops the hook for the current session. **Does not persist** — the app starts listening (active) on every launch.

**How to test**
- *Unit:* hotkey-string parsing & validation (accepts allowed keys/combos, rejects bare letters/digits); state-machine transitions for press/release including the <300 ms discard and the 60 s auto-stop (driven via a fake `IHotkeyListener` + fake clock).
- *Manual (TESTING.md M1):* in Notepad, hold Right Ctrl, say "hello", release → "Hello " appears. Tap Right Ctrl quickly → nothing happens. Rebind to Ctrl+Space → works; try to bind "E" → rejected.

---

## Feature 2 — Fully On-Device Transcription (Whisper)

**Engine & models**
- **Whisper.NET**, ggml `.bin` models, **English-only**, `language = "en"` (hard-locked, no language UI).
- Model sizes offered in Settings:
  - `tiny.en` (~75 MB) — fastest
  - `base.en` (~140 MB) — **default**
  - `small.en` (~460 MB) — most accurate
- Inference runs on the **CPU** by default, on a **background thread** (UI never blocks). Thread count = `max(1, processorCount − 1)`.

**Model delivery (download-on-first-run)**
- Models are **downloaded on demand** (not bundled) into `%LOCALAPPDATA%\SpeakType\models`. **Requires internet exactly once per model**; fully offline thereafter.
- **First run:** a small **Welcome window** shows a one-line how-to ("Hold Right Ctrl, speak, release.") and a progress bar downloading `base.en`. The hotkey is **inert until the download completes**, then a **"Ready!"** tray balloon appears.
- **Switching model size in Settings:** downloads the new model with a progress bar **while the current model keeps working**; switches over only after the new file is **verified (size + checksum)**. On success, the new model becomes active.
- **Download failure** (network/disk/corrupt): show **"Download failed — [Retry]"** and **stay on the previous model**.
- **Corrupt-on-load:** if a cached model fails verification at load time, re-download it.

**No telemetry, no cloud.** Audio and transcripts never leave the machine; the only network use is model downloads from Hugging Face.

**How to test**
- *Unit:* model path resolution; size/checksum verification logic (valid passes, truncated/corrupt fails); "keep old model on failed switch" logic (with a fake `IModelStore`).
- *Integration (gated category, slow):* run the **real Whisper engine** on a committed WAV (`test-assets/hello.wav`, a clear "hello world") and assert the transcript contains "hello world". Guards against model/runtime regressions.
- *Manual (TESTING.md M2):* fresh profile → first launch shows Welcome + download → "Ready!" balloon → dictation works. Switch to `small.en` → downloads, old model still usable during download, swaps when done. Kill network mid-download → "Download failed — Retry", previous model still active.

---

## Feature 3 — Audio Capture

**Behavior**
- Capture from the **current Windows default input device** (follows OS default changes automatically; no device picker in v1).
- Capture is **resampled to 16 kHz mono float** (Whisper's required format) via NAudio.
- **No microphone / capture failure** → tray balloon **"No microphone found"**, recording aborted, return to Idle.

**Silence gate (pre-transcription)**
- Before transcribing, check the captured audio's energy (RMS). If it is **near-silent** (below threshold), **skip transcription entirely** and show overlay **"No speech detected"** — paste nothing. (Prevents wasting CPU and prevents hallucinations on silence.)

**How to test**
- *Unit:* silence-gate RMS decision on synthetic buffers (silent buffer → skip; speech-level buffer → proceed). Resampling correctness can be checked on a known tone buffer.
- *Manual (TESTING.md M3):* unplug/disable mic, hold hotkey → "No microphone found" balloon. Hold hotkey in a silent room, say nothing → "No speech detected", nothing pasted.

---

## Feature 4 — Transcript Cleanup

**Design principle: trust Whisper for capitalization and punctuation.** Whisper already emits sentence-cased, punctuated text (e.g. `"Um, I think we should, you know, ship it."`). The cleanup pipeline therefore does **not** re-derive capitalization/punctuation from scratch — it does filler removal plus corrective fixups. The pipeline is a sequence of composable stages.

**Stage A — Filler removal (toggleable; default ON; the one user-facing cleanup switch)**
- **Always removed** (unambiguous, never real words): `um`, `uh`, `er`, `ah`, `hmm`, `mm` (and case variants).
- **Phrase fillers removed only when they look like throwaway discourse markers** — i.e. **comma-bounded** (`", you know,"`) or at a **sentence start/end** (`"You know, …"`). This leans on Whisper's own punctuation as the filler signal:
  - `you know`, `I mean`, `sort of`, `kind of`
  - Legitimate uses are preserved: `"I mean it."`, `"do you know the answer?"` are untouched.
- **Never removed in v1** (too risky — common real words): `like`, `actually`, `literally`, `basically`.

**Stage B — Fixups (always on; not user-toggleable, because turning them off leaves visibly broken text)**
- Repair artifacts left by filler removal: leading/double commas (`", I think"` → `"I think"`), double spaces, and re-capitalize the new first word of a sentence.
- Capitalize standalone `"i"` → `"I"`.

**Stage C — Output formatting (always on)**
- **Trim** leading/trailing whitespace.
- Append a **single trailing space** (so the next dictation/typed word doesn't butt against this one).
- **Do not** force terminal punctuation (respect whatever Whisper produced — avoids wrongly punctuating fragments).

**Hallucination filter (applies to whole result, before paste)**
- Drop **empty/whitespace-only** results → paste nothing.
- Drop known **silence hallucinations**: `"[BLANK_AUDIO]"`, and a bare `"you"` / `"Thank you."` produced from a very short clip → paste nothing.

**Architecture note:** stages are composable and individually addressable so Phase-2 (LLM rewrite) slots in as an additional toggled stage.

**How to test**
- *Unit (primary, table-driven xUnit `[Theory]`):* a corpus of `(rawTranscript → expectedOutput)` cases covering each stage and their interactions, e.g.:
  - `"Um, I think, you know, we should ship it."` → `"I think we should ship it. "`
  - `"I mean it."` → `"I mean it. "` (phrase kept — not a discourse marker)
  - `"do you know the answer?"` → `"do you know the answer? "` (kept)
  - `"i like pizza"` → `"I like pizza "` ("like" preserved, "i"→"I")
  - filler toggle OFF → fillers retained.
  - `"[BLANK_AUDIO]"`, `""`, short-clip `"Thank you."` → empty (nothing pasted).
- *Manual:* covered indirectly by end-to-end dictation in M1.

---

## Feature 5 — Clipboard-Safe Paste ("Works Everywhere")

**Behavior (the save → set → paste → restore sequence)**
1. **Save** the user's current clipboard — **text formats only** in v1.
   - *Accepted tradeoff:* if the user had a non-text item (image, files, rich content) on the clipboard, it is **not** preserved and will be lost when we paste. (Full-fidelity preservation deferred.)
2. **Set** our cleaned text on the clipboard.
3. **Paste** via simulated **Ctrl+V** (`SendInput`).
4. **Wait ~150 ms** (tunable) so the target app can read the clipboard (avoids the race where we restore before the app consumes our text).
5. **Restore** the original (text) clipboard.

**No-target handling**
- Attempt a lightweight check for a focused **editable** target (caret / UI-Automation).
- If a target **is** confirmed → paste, then restore as above.
- If we **cannot confirm** a target → **skip the restore** and **leave our text on the clipboard**, showing overlay **"Copied — paste manually"**. The user never silently loses their words. (Chosen because focus detection is unreliable across Electron/games.)

**How to test**
- *Unit:* clipboard save/restore logic and "leave-text-on-clipboard when no target" branch (via a fake `IClipboard` / `IPasteService`); restore-after-delay ordering.
- *Manual (TESTING.md M4):* copy "ORIGINAL" to clipboard, dictate into Slack → dictated text pastes; press Ctrl+V again elsewhere → "ORIGINAL" still there. Click the desktop (no field) and dictate → "Copied — paste manually", text remains on clipboard.

---

## Feature 6 — System Tray App, Overlay & UI

**Tray icon**
- Distinct icons/states: **Idle**, **Recording**, **Busy** (transcribing/pasting), **Error**.

**Recording overlay**
- A small, **always-on-top, no-activate, click-through** window (must **never steal focus**, or the paste target changes), shown near **bottom-center of the active monitor**:
  - **🎙 Listening…** while the key is held
  - **⚙ Transcribing…** after release
  - **"No speech detected"** / **"Copied — paste manually"** as applicable
  - Fades out on paste/completion.
- Overlay can be turned off in Settings.

**Tray right-click menu**
- **Settings…**
- **Pause listening** (toggle; session-only — resets to active on launch)
- **✓ Start with Windows** (checkbox; **default ON**, via `HKCU\…\Run` registry key)
- **About**
- **Quit**

**Errors / notifications**
- User-facing errors surface as **tray balloons** (e.g. "No microphone found", "Download failed").

**How to test**
- *Manual (TESTING.md M5–M7):* tray icon changes per state during a dictation; overlay appears/disappears and does not steal focus (focused field keeps its caret); Pause stops dictation, restart re-enables; toggle "Start with Windows" → registry Run key added/removed; "Already running" balloon when launching a second instance.

---

## Feature 7 — Settings

**Window contents** (WinForms; changes apply immediately, persisted to `settings.json`):
- **Hotkey** — rebind (with the allow/deny rules from Feature 1).
- **Model size** — dropdown `tiny.en / base.en / small.en`; selecting triggers download-if-needed with progress (Feature 2).
- **Remove filler words** — on/off (default ON).
- **Show recording overlay** — on/off (default ON).
- **Start with Windows** — on/off (default ON; mirrors tray).
- **Debug logging** — on/off (default OFF; see Logging).

**Persistence**
- Single `%APPDATA%\SpeakType\settings.json`. Schema (illustrative):
  ```json
  { "hotkey": "RightCtrl", "modelSize": "base.en",
    "fillerRemoval": true, "overlay": true,
    "autostart": true, "debugLogging": false }
  ```
- Apply-on-change: each edit writes the file and applies live (hotkey rebind re-registers the hook; model change kicks off download/switch).

**How to test**
- *Unit:* settings (de)serialization round-trip; defaults applied when file missing/partial; invalid hotkey rejected.
- *Manual:* change each setting, confirm immediate effect and that it survives a restart.

---

## Logging & Privacy

- **Rolling local log** at `%APPDATA%\SpeakType\logs\speaktype.log`.
- **Default (metadata only):** events, errors, and timings — e.g. `recording 7.2s`, `transcribe 1.4s, 38 chars`, `download failed: …`. **Never** logs transcript text or audio.
- **Debug logging toggle (default OFF):** when enabled, also records the **transcribed text** (to diagnose cleanup bugs). Clearly marked as storing sensitive content on disk.
- **No network telemetry, ever.**

**How to test**
- *Unit:* log formatting; assert transcript text is absent in default mode and present only when debug enabled.

---

## Performance

- **Goal:** key-release → text-appears in **< ~2 s** for a typical short utterance (≤10 s of speech, `base.en`, mid-range laptop). Measured (release→paste) and **logged each run**.
- This is a **goal we track, not a build-failing gate** (honest about hardware variance; CI machines vary).
- Transcription always runs **off the UI thread**; the UI must never freeze.

**How to test**
- *Manual / observational:* the metadata log records per-run latency; spot-check against the goal on reference hardware. No flaky perf assertion in CI.

---

## App Lifecycle & Robustness

- **Single instance:** named mutex `SpeakType.Single`. A second launch shows **"SpeakType is already running"** and exits.
- **Global exception handling:** wrap the app in handlers (`AppDomain.UnhandledException`, `Application.ThreadException`). On an unhandled error: **log the stack, show a tray balloon, and recover to Idle** if possible rather than dying silently.

**How to test**
- *Manual (TESTING.md M7):* launch a second instance → balloon + exit, original keeps working.

---

## Architecture for Testability (ports & adapters)

Every OS interaction sits behind an interface so the core logic is unit-testable with fakes:

- `IHotkeyListener` — global hook (down/up, suppression).
- `IAudioCapture` — start/stop, returns 16 kHz mono float buffer.
- `ITranscriber` — `Task<string> Transcribe(float[] samples)` (Whisper.NET behind it).
- `IModelStore` — model presence, download (progress), verify, path.
- `IClipboard` / `IPasteService` — save/set/restore, simulate paste, target detection.
- `ISettingsStore` — load/save JSON.

A central **orchestrator** owns the **Idle→Recording→Transcribing→Pasting→Idle** state machine and is fully unit-tested against these fakes (including concurrency: presses during non-Idle are ignored).

**Thin adapters** wrap the real Win32 / NAudio / Whisper / clipboard calls. These are intentionally minimal and covered by the **manual** checklist, not unit tests.

### Test layers
1. **Unit (xUnit, fakes)** — cleanup pipeline (table-driven), state machine, settings, hotkey parsing, silence gate, hallucination filter, model verify, logging.
2. **Integration (gated, slow)** — one real-Whisper test on a committed WAV.
3. **Manual (`TESTING.md`)** — numbered checklist (M1, M2, …) for the OS-bound features, each with exact steps + expected result. Every brick's `BRICKS.md` "Verified" line references the relevant `M#` items it exercised.

---

## Explicitly NOT in v1

- No LLM rewriting (Phase 2).
- No cloud / API transcription.
- No tone or structure rewriting (rambling → crisp sentences comes later).
- No Mac version (separate later phase).
- No accounts, login, or pricing/licensing.
- No microphone picker (uses Windows default).
- No multi-language support (English-only).
- No image/file clipboard preservation (text-only restore).
- No installer / code signing (single-file exe; SmartScreen warning accepted).
- No win-arm64 build.
- No removal of `like`/`actually`/`literally`/`basically` as fillers.
- No recording queue (busy = ignore new presses).

---

## Roadmap (direction, not v1 scope)

- **Phase 2:** Add a small local LLM (sub-1GB, e.g. Liquid LFM2.5 / Gemma 3 1B) for true rewriting — professional tone, restructuring rambling into clean messages. Slots into the cleanup pipeline as an additional toggled stage. Target: under 2 seconds, runs in background without hurting performance.
- **Phase 3:** macOS version.
- **Later:** Pricing, licensing, custom modes (email / Slack / notes), custom vocabulary, full-fidelity clipboard preservation, microphone picker, installer + code signing, multi-language.

---

## Appendix — Resolved Decisions (quick index)

| # | Decision | Resolution |
|---|---|---|
| 1 | UI framework | WinForms + .NET 8 |
| 2 | Whisper engine | Whisper.NET (managed) |
| 3 | Model delivery | Download on first run → `%LOCALAPPDATA%` |
| 4 | Model sizes | tiny/base/small `.en`; **base.en** default |
| 5 | Default hotkey | Right Ctrl, single key, suppressed |
| 6 | Hold limits | <300 ms discard; 60 s auto-stop |
| 7 | Concurrency | Busy = ignore new presses (state machine) |
| 8 | Rebind rules | Safe keys + combos only; always suppress |
| 9 | Microphone | Windows default; balloon if none |
| 10 | Clipboard restore | **Text only** (images/files lost — accepted) |
| 11 | Paste timing | SendInput Ctrl+V, ~150 ms delay, then restore |
| 12 | Cleanup scope | Trust Whisper; rules = filler + fixups |
| 13 | Filler list | Safe set + comma-bounded phrases; not like/actually/etc. |
| 14 | Phrase guard | Comma-bounded / sentence-edge only |
| 15 | Output format | Trim + single trailing space; no forced period |
| 16 | Recording cue | Tray icon + non-focus-stealing overlay |
| 17 | Tray menu | Settings/Pause/Start-with-Windows(ON)/About/Quit |
| 18 | Settings store | JSON in `%APPDATA%`, apply-on-change |
| 19 | Cleanup toggles | Filler removal only; fixups always on |
| 20 | First run | Welcome window + auto-download default |
| 21 | Model switch/DL errors | Download-on-select, keep old, verify, retry |
| 22 | Empty/noise result | Silence gate + hallucination filter |
| 23 | No target field | Best-effort paste; leave text on clipboard if unsure |
| 24 | Latency | Goal <2 s typical, logged, not a hard gate |
| 25 | Logging | Local metadata only; transcript under debug toggle |
| 26 | Packaging | Self-contained single-file `win-x64` exe, no installer |
| 27 | Test strategy | Ports-and-adapters + 1 gated real-Whisper test |
| 28 | Test docs | `TESTING.md` checklist + per-brick `Verified` |
| 29 | App lifecycle | Single instance (mutex) + global crash handler |
| 30 | Pause persistence | Resets to active on launch |
| 31 | Architecture | x64 only |
| 32 | Language | English-only, hard-locked (`en`) |
