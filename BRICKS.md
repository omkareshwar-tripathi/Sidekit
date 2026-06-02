# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### Adapters (real OS integration — thin, manual-verified)

- [ ] **Brick 4 — Hotkey adapter (`IHotkeyListener`).** `WH_KEYBOARD_LL` low-level hook; default Right Ctrl; suppress bound key while held; hotkey string parse/validate (allow safe keys + combos, reject bare letters/digits); live re-register on rebind.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — parse/validate accept/reject cases. Manual — **M1**.

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

### Brick 2 — Cleanup pipeline (pure) (2026-06-02)
- **What:** `TranscriptCleaner.Clean(string? raw, bool removeFillers = true)` — turns a raw Whisper transcript into paste-ready text. Ordered stages in one class: (1) filler removal (toggleable) — always-words `um/uh/er/ah/hmm/mm` stripped even bare, phrase markers `you know/I mean/sort of/kind of` stripped only when comma-bounded or at a sentence boundary (so real uses survive); (2) always-on fixups — collapse comma/space debris, capitalize standalone `i`→`I`; (3) trim + single trailing space (no forced terminal punctuation); (4) hallucination/empty filter → returns `""` for empty, `[BLANK_AUDIO]`, and whole-output `you`/`Thank you.`.
- **Files:** `SpeakType.Core/Cleanup/TranscriptCleaner.cs`, `SpeakType.Tests/Cleanup/TranscriptCleanerTests.cs`.
- **Verified (on Mac):** `dotnet test SpeakType.Tests/...` → **38/38 pass**. Corpus covers the spec Feature-4 cases (filler ON, filler OFF still runs fixups, hallucinations→empty) plus a `Clean_guards_each_filler_pass` theory added during review to exercise the previously-untested passes: `sort of`/`kind of` *removal*, multi-sentence fillers after a period, filler-before-terminator, leading-filler-before-digit, stacked bare fillers. Pure logic → no manual M#. CI on Windows covers it too.
- **Notes / decisions:**
  - **No `ICleanupStage` interface / per-stage files in v1.** The spec's "composable, individually addressable stages" is forward-looking (for the Phase-2 LLM rewrite stage). v1 implements stages as ordered private methods in one class (`RemoveFillers` / `Fixups` + the filter) — a future stage slots in as another method off `Clean`. Avoids speculative abstraction (§2) and the 5-file ceiling.
  - **Simplify pass:** dropped `RegexOptions.Compiled` (net-negative JIT cost for a run-once-per-utterance path), tidied `[,]?`→`,?`, and split the hallucination list into named `Sentinels` (`[BLANK_AUDIO]`) vs `SilencePhrases` (`you`/`Thank you.`) so the membership rule is explicit, not accretive.
  - **Code review — confirmed real-world edge cases that are NOT code defects but spec-level tradeoffs (left as the spec dictates; flagged for the user, see follow-up below):** the always-filler list deletes real standalone tokens — `mm` (millimeter: "5 mm wide" → "5 wide"), `er` (ER), `ah` — because spec line 121 declares them "never real words"; and `\bi\b`→`I` (spec line 129) over-capitalizes `i.e.` / `for i` / `Section i`. These are the spec author's documented decisions; I did **not** silently override them mid-ship.
  - **Known niche defects (no spec answer; documented, not fixed):** two stacked *leading* always-fillers with a comma drop the re-capitalization (`"Um er, it works."` → `"it works. "`); a hyphen-joined cluster leaves debris (`"Mm-hmm."` → `"-hmm. "`). Rare Whisper outputs; fixing needs invented behavior or added pass complexity — deferred to the follow-up.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
