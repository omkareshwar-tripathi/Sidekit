# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### Adapters (real OS integration — thin, manual-verified)

- [ ] **Brick 4b — Win32 hotkey hook adapter (`IHotkeyListener`).** `WH_KEYBOARD_LL` low-level hook in `SpeakType.App` (Windows-only). Consume the parsed `Hotkey` from Brick 4a (`Hotkey.TryParse`): map `TriggerKey`→VK + the modifier flags (unsided `Ctrl`/`Alt`/`Shift` match either side); default Right Ctrl; **suppress the bound key while held**; raise `Pressed`/`Released`; live re-register on rebind; tray Pause stops the hook for the session.
  - **Settings-validation follow-up (revealed by Brick 4a review):** route the persisted settings hotkey through `Hotkey.TryParse`, falling back to `AppSettings.DefaultHotkey` when invalid — `AppSettings.Normalize()` only null-guards today, so a hand-edited bad value (e.g. `"Hotkey":"E"`) currently survives load and would leave the app with no usable hotkey at registration time. (Could also live in Brick 11 Settings; do it wherever the setting is first turned into a real binding.)
  - Skill: dotnet-best-practices, run-tests
  - Verify: Windows-only — CI build proves it compiles on x64; **manual M1** on the laptop (hold Right Ctrl → dictation; quick tap → nothing; rebind to Ctrl+Space; bind "E" → rejected).

- [ ] **Brick 5 — Audio capture adapter (`IAudioCapture`) + silence gate.** NAudio capture from Windows default device; resample to 16 kHz mono float; RMS silence gate; no-mic → abort + balloon signal.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — silence gate on synthetic buffers (silent → skip, speech-level → proceed); resample on a known tone. Manual — **M3**.

- [ ] **Brick 6 — Model store (`IModelStore`).** Resolve `%LOCALAPPDATA%\SpeakType\models`; download a chosen ggml `.en` model with progress; verify size + checksum; retry on failure; re-download on corrupt-on-load; keep prior model active during a switch.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — verification passes valid / fails truncated; keep-old-on-failed-switch logic (fakes/temp dir). Manual — **M2** (download + switch + failure).

- [ ] **Brick 7 — Whisper transcriber (`ITranscriber`).** Whisper.NET adapter; `language="en"`; threads = `max(1, cpu-1)`; runs on a background thread; takes a model path from the model store.
  - Skill: dotnet-best-practices, run-tests
  - Verify: integration (gated/slow) — real Whisper on `test-assets/hello.wav` asserts transcript contains "hello world" (fixture provides tiny.en locally; skip if model/offline). Note: no skill for local Whisper — work against Whisper.NET docs.

- [ ] **Brick 8 — Clipboard-safe paste (`IClipboard`/`IPasteService`).** Save (text only) → set our text → `SendInput` Ctrl+V → ~150 ms delay → restore. Best-effort editable-target detection; if unsure, skip restore and leave our text on the clipboard.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — save/restore and leave-on-clipboard branch (fake clipboard); restore-after-delay ordering. Manual — **M4**.

### App shell, UI & polish

- [ ] **Brick 9 — Tray app + lifecycle.** `NotifyIcon` with Idle/Recording/Busy/Error icons; menu (Settings…, Pause, Start with Windows, About, Quit); single-instance mutex `SpeakType.Single`; global exception handlers (log + balloon + recover to Idle). Wire Pause (session-only) and tray state to the orchestrator.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M5**, **M7**.

- [ ] **Brick 10 — Recording overlay.** No-activate, click-through, always-on-top window at bottom-center of the active monitor; states 🎙 Listening / ⚙ Transcribing / "No speech detected" / "Copied — paste manually"; fade out; overlay on/off setting. Must never steal focus.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M5** (focus not stolen; overlay shows/hides per state).

- [ ] **Brick 11 — Settings window.** WinForms form: hotkey rebind, model dropdown, Remove-filler toggle, overlay toggle, Start-with-Windows toggle, Debug-logging toggle. Apply-on-change → `ISettingsStore`; hotkey rebind re-registers hook; model change triggers store download/switch.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M6**.

- [ ] **Brick 12 — First-run + autostart.** Welcome window (how-to + `base.en` download progress; hotkey inert until ready → "Ready!" balloon); `HKCU\…\Run` autostart (default ON), toggled from tray/Settings.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M2** (first-run), **M6** (autostart registry key add/remove).

- [ ] **Brick 13 — Logging + performance timing.** Rolling log at `%APPDATA%\SpeakType\logs`; metadata + timings only by default; transcript text only when Debug logging on; log release→paste latency each run.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — log line formatting; transcript absent by default, present when debug on. Manual — latency line appears, observe vs <2 s goal.

### Integration & ship

- [ ] **Brick 14 — End-to-end wiring.** Compose the real adapters into the orchestrator behind composition root; full dictation works in a real app.
  - **Provide the real `IClock` (Stopwatch-backed) and `IAutoStopTimer` (`System.Threading.Timer`, one-shot via `Timeout.Infinite` period) adapters** (deferred from Brick 3b — no real impls exist yet).
  - **Own the threading model.** The orchestrator is synchronous in v1; the real auto-stop timer fires `OnAutoStop` on a thread-pool thread, so its `State` guard + `_pressTimestamp` are **not thread-safe** today. A release racing the 60 s fire could double-run the cycle. Marshal hotkey + timer callbacks onto one thread (or lock) here, and offload the capture→transcribe→paste work off the UI thread.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M1** end-to-end + **M8** (full happy path across Notepad/Slack/browser).

- [ ] **Brick 15 — Packaging.** Finalize self-contained single-file `win-x64` publish; confirm it runs on a clean machine (first-run download + autostart). Document SmartScreen-warning expectation.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — copy `.exe` to a clean profile/VM, launch → Welcome → download → dictation works.

### Backlog (optional — needs a user decision, not in the v1 critical path)

- [ ] **Cleanup-pipeline real-world hardening (revealed by Brick 2 review).** Decide whether to: (a) trim the always-filler list so it stops eating real tokens — `mm` (millimeter), `er` (ER), and possibly `ah` collide with genuine words/units; (b) make `i`→`I` skip abbreviation/list contexts like `i.e.` / `Section i` / `for i`; (c) fix the two niche defects — stacked leading fillers losing capitalization (`"Um er,"`) and hyphen-joined clusters (`"Mm-hmm."`). All three currently behave per spec lines 121/129; changing them is a spec decision, hence parked here rather than done autonomously.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests

## Done

_(Newest first. Older entries archived to `BRICKS-ARCHIVE.md`.)_

### Brick 4a — Hotkey model + parse/validate (pure) (2026-06-02)
- **What:** The pure, OS-agnostic hotkey parser/validator (spec Feature 1 "Rebinding"; the unit-test deliverable). `Hotkey.TryParse(string?, out Hotkey?, out string? error)` turns a string like `"RightCtrl"`, `"Ctrl+Space"`, `"F13"` into a validated `Hotkey(HotkeyModifiers Modifiers, string TriggerKey)`, or returns false with a user-facing message. **Allows** bare modifiers, bare F13–F24, bare Pause/Break, and any modifier+key combo; **rejects** bare letters/digits, bare F1–F12, bare other named keys, modifier-only combos, two main keys, and empty/unknown tokens. `ToString()` gives a canonical round-trippable form. Win32 virtual-key mapping is deliberately **not** here — that's the Brick 4b adapter (Core stays dependency-free).
- **Files:** `SpeakType.Core/Input/Hotkey.cs` (new); tests `SpeakType.Tests/Input/HotkeyTests.cs` (new).
- **Verified (on Mac):** `dotnet test SpeakType.Tests/...` → **78/78 pass** (26 new: accept matrix incl. case-insensitive + `Alt+5`/`Ctrl+Shift+F1`, reject matrix incl. bare `E`/`5`/`F1`/`Space`/`Ctrl+Shift`/`Ctrl+A+B`/`Ctrl+`/`Ctrl+Foo`/null, and ToString round-trip). Critically, the `AppSettings` default `"RightCtrl"` parses. Pure logic → no manual M# (the hook's M1 is Brick 4b). CI on Windows covers it too.
- **Notes / decisions:**
  - **Brick 4 was split (4a + 4b)** by both §2a sizing and platform routing: the pure parser (here, Mac-verified) vs the Windows-only `WH_KEYBOARD_LL` hook (4b, App). Same seam as Brick 3.
  - **`TriggerKey` is a `string`, not an enum** (altitude-reviewed): keeps Core OS-agnostic and lets the 4b adapter own the single VK lookup table; an enum would force Core to enumerate every key and need a serialization shim for the string-typed `AppSettings.Hotkey`.
  - **Simplify pass:** merged the duplicate letter/digit branches into one `char.IsAscii*` check (dropped the regex + the duplicated error literal), renamed `Modifiers_`→`ModifierAliases`, replaced an unused `List` with a single field, and trimmed speculative modifier alias short-forms (kept canonical spellings + `control`). Kept the full `NamedKeys` table — the spec's "any modifier + key combo" makes `Ctrl+Enter` etc. valid, so trimming would wrongly reject them.
  - **Deliberate leniencies (documented, per spec interpretation; not bugs):** bare unsided `Ctrl`/`Alt` are accepted (spec enumerates sided, but this mirrors the spec's own unsided bare `Shift`; 4b maps unsided→either side); duplicate modifiers collapse idempotently; `Shift+E` is accepted (it *is* "modifier + key"); the literal `+` key can't be bound (`+` is the separator) and yields an "empty key" message. The Settings UI (Brick 11) uses key-capture, not free text, so these edge spellings are unlikely in practice.
  - **Follow-up recorded on Brick 4b:** `AppSettings.Normalize()` doesn't run `TryParse`, so a hand-edited invalid hotkey survives settings load — wire validation+fallback where the setting becomes a real binding.

### Brick 3b — Orchestrator timing guards (2026-06-02)
- **What:** The two hold-duration guards on the Brick 3a orchestrator (spec Feature 1). A hold **< 300 ms** is an accidental tap → discarded (capture stopped to release the mic + keep Start/Stop balanced, no transcribe/paste, no `Completed`). A hold reaching **60 s** auto-stops: a one-shot timer started on press fires `OnAutoStop`, which runs the same `RunCycle()` as a release **while the key is still held** (the later real release is then ignored). Two new ports — `IClock` (Stopwatch-style `GetTimestamp`/`GetElapsedTime`, measures press→release wall-clock elapsed) and `IAutoStopTimer` (`Start(delay,onElapsed)`/`Cancel`) — injected into the orchestrator; thresholds are tunable `MinHold`/`MaxHold` consts.
- **Files:** `SpeakType.Core/Time/IClock.cs`, `SpeakType.Core/Time/IAutoStopTimer.cs` (new); edited `SpeakType.Core/Orchestration/DictationOrchestrator.cs`; tests `SpeakType.Tests/Orchestration/{Fakes.cs, DictationOrchestratorTests.cs}`.
- **Verified (on Mac):** `dotnet test SpeakType.Tests/...` → **52/52 pass**. New tests: <300 ms discard (no transcribe/paste, mic stopped, timer cancelled, no outcome); 60 s auto-stop runs the cycle while held + the late release is ignored; timer starts at 60 s and is cancelled on release; discard-then-next-cycle works; and **audio `Start()` throwing resets State to Idle so the next press works** (the must-fix below). Pure logic → no manual M#. CI on Windows covers it too.
- **Notes / decisions:**
  - **Code review caught a real latent bug (fixed):** `OnPressed` set `State=Recording` then called `_audioCapture.Start()`/`_autoStopTimer.Start()` with no protection — if the mic won't open (`Start()` throws), State stuck at `Recording` forever, wedging all future dictation (same failure class as the Brick 3a `RunCycle` fix, but on the press path this brick modified). Wrapped the press body in `try { … } catch { State = Idle; throw; }`. Regression test added.
  - **Hand-rolled `IClock`/`IAutoStopTimer` instead of .NET 8 `TimeProvider` — deliberate** (simplify + review both raised it). `TimeProvider` (+`FakeTimeProvider`) would cover `IClock`'s role, but Core currently has **zero external NuGet deps** and every port is project-owned (`IHotkeyListener`/`IAudioCapture`/…); `FakeTimeProvider` needs an extra test package and `TimeProvider` bundles wall-clock/timer-creation members we don't use. Kept the convention; revisit if Core ever takes a `Microsoft.Extensions.*` dep anyway.
  - **`MinHold`/`MaxHold` are private consts, not `AppSettings`** — no spec/user story exposes them; promoting to settings (JSON key + Normalize default + Settings UI) would be speculative configurability (§2). "Tunable in code" per spec line 57.
  - **Threaded-timer races + real adapters deferred to Brick 14** (now noted on that brick): the real `IAutoStopTimer` fires on a thread-pool thread, so the `State` guard + `_pressTimestamp` aren't thread-safe yet — a release racing the 60 s fire could double-run the cycle. The orchestrator is **synchronous in v1 by design** (Brick 3a); the real Stopwatch/`System.Threading.Timer` adapters + threading model are Brick 14's job.

### Brick 3a — Dictation orchestrator: ports + core flow (2026-06-02)
- **What:** The pure state machine that wires a dictation cycle, plus the ports it drives. `DictationOrchestrator` subscribes to hotkey press/release: press (Idle) → `Recording` + `audioCapture.Start()`; release → `Transcribing` → `Stop()` → if no speech skip → `Transcribe()` → `TranscriptCleaner.Clean(raw, settings.FillerRemoval)` → if empty skip → `Pasting` → `Paste()` → `Idle`, raising a single `Completed(DictationOutcome)` per cycle (`Pasted` / `LeftOnClipboard` / `NoSpeech`). Press while non-Idle is ignored (busy). **This brick is the non-timing logic only** — Brick 3b adds the `<300 ms`/`60 s` guards.
- **Files:** `SpeakType.Core/Input/IHotkeyListener.cs`, `SpeakType.Core/Audio/IAudioCapture.cs` (+ `CapturedAudio` record), `SpeakType.Core/Transcription/ITranscriber.cs`, `SpeakType.Core/Paste/IPasteService.cs` (+ `PasteOutcome` enum), `SpeakType.Core/Orchestration/DictationOrchestrator.cs` (+ `RecordingState`, `DictationOutcome` enums); tests `SpeakType.Tests/Orchestration/{Fakes.cs, DictationOrchestratorTests.cs}`.
- **Verified (on Mac):** `dotnet test SpeakType.Tests/...` → **47/47 pass**. Orchestrator tests cover: normal flow (asserts captured samples reach the transcriber **and** the *cleaned* text reaches paste), busy-ignore (one `Start`), silence-skip (transcriber not called), no-target → `LeftOnClipboard`, empty-after-clean → `NoSpeech` (transcriber *was* called), press→`Recording`, release-without-press ignored, second-release-after-cycle ignored, and **adapter-throws → State resets to Idle and the next cycle works**. Pure logic → no manual M#. CI on Windows covers it too.
- **Notes / decisions:**
  - **Brick 3 was split (3a + 3b) — it exceeded the §2a sizing ceiling** (5 ports + clock + timer + orchestrator + 6 edge cases ≈ 180+ LOC / 7 files). Seam: 3a = result-based branches (no clock); 3b = the two time-based guards (need `IClock`/`ITimer`).
  - **`IModelStore` is NOT defined here** (the BRICKS plan originally listed it among "the ports"). The orchestrator's flow doesn't touch the model store — it belongs to Brick 6 where it's implemented. Defining it here would be a speculative, untested interface.
  - **Code review caught a real latent bug (fixed):** with no `try/finally`, any adapter throwing (`Stop`/`Transcribe`/`Paste`) left `State` non-Idle forever, so the press-guard silently blocked *all* future dictation until restart. Fixed by `try { outcome = ProcessRecording() } finally { State = Idle }`, then raising `Completed` **after** the reset (which also closes a re-entrancy trap where a `Completed` handler could start a nested cycle). User-facing error reporting stays deferred to Brick 9; only the local "never wedge" invariant lives here. Regression test added.
  - **`RunCycle()` is a trigger-independent entry point** (extracted in the simplify pass) precisely so Brick 3b's auto-stop timer can call it without faking a key event.
  - **`RecordingState.Transcribing`/`Pasting` are intentionally kept** though unread today — the spec's overlay (Feature 6: `⚙ Transcribing`) needs them as distinct states for Brick 10. Not speculative; spec-traced.
  - **Deferred (noted, not bugs):** orchestrator subscribes to hotkey events in its ctor and never unsubscribes — fine for a process-lifetime singleton; add `IDisposable` only if a later brick rebuilds the pipeline (e.g. settings reload). Threading (background-thread the cycle) is Brick 14.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
