# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

### Integration & ship

- [ ] **Brick 14d — Cycle feedback + logging.** Drive the tray icon state and the recording overlay from the live dictation cycle, and wire the diagnostic logger. (Brick 14c shipped the pipeline; the tray still just shows Idle and nothing logs.)
  - **Tray-state + overlay from the cycle.** Show **🎙 Listening…** + tray Recording on press, **⚙ Transcribing…** + tray Busy while the cycle runs, and the outcome (`NoSpeech`/`CopiedManually` → fade) on `Completed` — all gated on `settings.Overlay` and **marshalled to the UI thread** (the cycle runs on a background thread; reuse `UiMarshaller.Post`). The orchestrator only exposes `State` + the `Completed` event today, so a clean "Listening" cue likely wants either a small orchestrator **state-changed event** (Core, Mac-testable) or driving "Listening" off the hotkey `Pressed` edge in the composition root — decide in the plan.
  - **Logging wiring (from Brick 13).** Construct `FileLogSink(FileLogSink.DefaultLogPath)` → wrap in `AppLogger`, passing `() => settings.DebugLogging` (a **live** `Func<bool>`, not a captured bool, so the Debug-logging toggle applies immediately). Call `Recording`/`Transcribed`/`Latency`/`Transcript`/`Error` from the dictation cycle; measure release→paste latency with the monotonic `SystemClock` (avoids the negative-latency case). The sink is best-effort (never throws) and process-locks, so it's safe from the timer/UI/background threads.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M5** (overlay text/fade/no-focus-steal), tray colour transitions; **M8** latency line in the log.

- [ ] **Brick 14e — Settings, pause & model switch wiring.** Make the tray menu + settings window actually do things. (Brick 11 built `SettingsForm` raising events; Brick 14c built the pipeline; this connects them.)
  - **Tray + settings actions.** `tray.SettingsRequested` → show the single `SettingsForm`; `SettingsForm.HotkeyRebound` → `Win32HotkeyListener.Rebind` (treat as a cancel of any active capture); `SettingsForm.ModelChangeRequested` → download + verify the new model (progress), then **swap the live `ITranscriber`** (keep the old one working until the new file verifies); `tray.PauseToggled` → `Win32HotkeyListener.Pause`/`Resume`.
  - **Autostart unification (deferred from Brick 12).** Funnel the tray "Start with Windows" toggle AND `SettingsForm.AutostartChanged` through one `ApplyAutostart(bool)` that keeps both surfaces (tray checkmark + Settings checkbox) and `AppSettings.Autostart` in sync.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M6** (change each setting → immediate effect; survives restart; pause stops the hotkey; model switch keeps old model usable during download).

- [ ] **Brick 15 — Packaging.** Finalize self-contained single-file `win-x64` publish; confirm it runs on a clean machine (first-run download + autostart). Document SmartScreen-warning expectation.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — copy `.exe` to a clean profile/VM, launch → Welcome → download → dictation works.

### Backlog (optional — needs a user decision, not in the v1 critical path)

- [ ] **Editable-target detection via UI Automation (revealed by Brick 8 review).** The Brick 8 `WinClipboard.HasEditableTarget` uses a `GetGUIThreadInfo` caret check, which returns false for **Electron/Chromium** apps (Slack, VS Code, Chrome, Discord) — they expose no Win32 caret, so dictation into them falls back to "Copied — paste manually" instead of pasting. **M4 expects Slack to paste**, so this gap will show at manual verification. Upgrade the heuristic to UI Automation (`AutomationElement.FocusedElement` + `TextPattern`/`ValuePattern` / `IsKeyboardFocusable`), keeping the caret check as a fast-path and leave-on-clipboard as the final fallback. Windows-only; verify with M4 against an Electron app on the laptop.
  - Skill: dotnet-best-practices, run-tests
- [ ] **Clipboard contention + paste error handling (revealed by Brick 8 review).** WinForms `Clipboard` throws transient `ExternalException` when another process holds the clipboard open; today that propagates out of `ClipboardPasteService.Paste` (and on Windows, up through the hotkey hook callback). Add best-effort retry/swallow in the `WinClipboard` adapter and decide the user-facing failure surface. Tightly coupled to Brick 9 (global exception handling) and Brick 14 (threading / marshalling the paste onto the STA thread) — fold in there rather than as a standalone brick if convenient.
  - Skill: dotnet-best-practices, run-tests
- [ ] **Unify the `%APPDATA%/%LOCALAPPDATA%\SpeakType` path literal via `AppInfo.Name` (revealed by Brick 13 review).** `JsonSettingsStore.DefaultFilePath`, `ModelStore.DefaultModelsDirectory`, and `FileLogSink.DefaultLogPath` each hardcode the `"SpeakType"` string, though `AppInfo.Name` exists for exactly this (its doc-comment already says so). Three sites now — replace all three together (a one-off in `FileLogSink` would just make it the odd one out). Pure cleanup, Core-only, fully Mac-testable.
  - Skill: dotnet-best-practices, run-tests
- [ ] **Shared test temp-dir helper (revealed by Brick 6b review).** The temp-dir scaffolding (`_tempDir` field + ctor + `Dispose`) is now duplicated across `JsonSettingsStoreTests`, `ModelStoreTests`, and `HttpModelDownloaderTests` (rule-of-three met). Extract a tiny `TempDir`/`TempDirFixture` IDisposable helper and have the three classes use it (~12 lines saved each). Deferred from Brick 6b to keep that brick from editing already-shipped test files; do it as its own small test-only brick.
  - Skill: dotnet-xunit, run-tests

- [ ] **Cleanup-pipeline real-world hardening (revealed by Brick 2 review).** Decide whether to: (a) trim the always-filler list so it stops eating real tokens — `mm` (millimeter), `er` (ER), and possibly `ah` collide with genuine words/units; (b) make `i`→`I` skip abbreviation/list contexts like `i.e.` / `Section i` / `for i`; (c) fix the two niche defects — stacked leading fillers losing capitalization (`"Um er,"`) and hyphen-joined clusters (`"Mm-hmm."`). All three currently behave per spec lines 121/129; changing them is a spec decision, hence parked here rather than done autonomously.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests

## Done

_(Newest first. Older entries archived to `BRICKS-ARCHIVE.md`.)_

### Brick 14c — End-to-end dictation pipeline (composition root) (2026-06-02)
- **What:** Wired the real adapters into the thread-safe orchestrator so **hold-hotkey → speak → release → text is pasted** works end-to-end (spec Feature 1 happy path). The composition (after first-run model setup): load `AppSettings`; build the `WhisperTranscriber` from the cached model **with corrupt-on-load re-download**; build the hotkey/capture/clipboard/clock/auto-stop adapters + `TranscriptCleaner`; run the cycle on a **background thread** (`BackgroundCycleDispatcher` → `ICycleDispatcher`) so transcription never freezes the UI; the paste hops to the **STA UI thread** via a `MarshallingClipboard` over a `UiMarshaller`. The hotkey hook is installed **last** (after the model loads), so it stays inert until SpeakType is ready. Referenced `Whisper.net.Runtime` so Whisper actually runs. Tray-state/overlay/logging and settings/pause/model-switch are **deferred to Bricks 14d/14e** — the tray still shows Idle and nothing logs yet.
- **Files:** `SpeakType.App/Program.cs` (pipeline composition + `LoadTranscriber`); `SpeakType.App/Threading/{UiMarshaller.cs, BackgroundCycleDispatcher.cs}` (new); `SpeakType.App/Paste/MarshallingClipboard.cs` (new); `SpeakType.App/SpeakType.App.csproj` (added `Whisper.net.Runtime` 1.9.1 + the `SpeakType.Whisper` project ref). No new Core logic → no new unit tests (pure App composition; the units it wires are already tested).
- **Verified:** Core suite unchanged → `dotnet test SpeakType.Tests/...` **153/153**. App is **Windows-only — cannot build on Mac**; Windows x64 **CI is the compile gate** (green: run 26834284182, after a CS0411 fix — see notes). **Manual M1 (Notepad: hold Right Ctrl, say "hello", release → "Hello " appears) and M3 (no-mic / silence) deferred to the laptop — this is the first brick where pressing the hotkey actually does something.**
- **Notes / decisions:**
  - **Brick 14 split (final stretch):** 14c = the dictation pipeline (this); **14d** = tray/overlay feedback + logging; **14e** = settings/pause/model-switch/autostart unification. Kept 14c to 5 files / ~140 LOC (the §2a ceiling) since it's Windows-only and CI only compile-checks it.
  - **Threading model.** Cycle runs off the UI thread (`Task.Run` via `BackgroundCycleDispatcher`); WinForms `Clipboard` is STA-only, so `MarshallingClipboard` hops each clipboard op to the UI thread (`UiMarshaller` = a parentless `Control` whose handle is forced on the UI thread). The `Thread.Sleep` inside `ClipboardPasteService` stays on the background thread, so the UI never blocks. The orchestrator is already thread-safe (Brick 14b), so the hotkey (UI thread) and auto-stop (thread-pool) can drive it concurrently without extra serialization.
  - **Corrupt-on-load (spec Feature 2):** detected by *attempting* the load — if `WhisperTranscriber`'s ctor throws on a truncated/stale file, re-download via the `WelcomeForm` flow (its `EnsureAsync` re-verifies + refetches) and rebuild. Avoids a SHA256 over ~150 MB on every launch (the Brick 12 concern).
  - **Quit-during-dictation guard (code-review must-fix):** on Quit while a background cycle is mid-paste, the cycle would post its result/error to a now-disposed `UiMarshaller`, throwing on a thread-pool thread (possible "stopped working" dialog). `UiMarshaller.Post` now no-ops once the control is disposed, breaking that crash chain; `NAudioCapture.Stop` already returns empty after dispose and the transcriber dispose is try/caught.
  - **Hotkey gated on readiness by construction order:** the hook is created only after the model loads, so there's no window where pressing the key does work with no model.
  - **CI compile gate caught a `/simplify` false positive:** a cleanup pass claimed `UiMarshaller.Invoke(Action)` was unused and it was dropped — but the **void** clipboard ops (`SetText`/`Clear`) need it (a void lambda can't bind to `Invoke<T>(Func<T>)`). The Windows CI build (which this Mac can't run) failed with CS0411; the overload was restored. `UiMarshaller` keeps `Invoke<T>` (value-returning clipboard ops), `Invoke(Action)` (void ops), and `Post` (fire-and-forget UI work).

### Brick 14b — Orchestrator threading (thread-safe + offloadable cycle) (2026-06-02)
- **What:** Made `DictationOrchestrator` safe to drive from production threading and closed a real race. (1) **Injected cycle executor** — a new `ICycleDispatcher` port (default `SynchronousCycleDispatcher`) so the composition root can run the capture→transcribe→paste cycle on a **background thread** (spec Feature 2: inference off the UI thread, UI never blocks). (2) **Atomic state-claim under a lock** — `TryClaimForProcessing()` flips `Recording → Transcribing` under `_gate`, so a key-release and the 60 s auto-stop (which fires on a thread-pool thread, per Brick 14a) can no longer **both** run the cycle (the double-`Stop()`/double-`Completed` race flagged in the 14a review). All `_state` access is now serialized by `_gate`. No app-visible change yet (the real dispatcher + UI marshalling are Brick 14c).
- **Files:** `SpeakType.Core/Orchestration/DictationOrchestrator.cs` (changed); `SpeakType.Core/Orchestration/{ICycleDispatcher.cs, SynchronousCycleDispatcher.cs}` (new); tests `SpeakType.Tests/Orchestration/DictationOrchestratorTests.cs` (+2) and `Fakes.cs` (+`DeferredDispatcher`).
- **Verified:** Fully cross-platform → `dotnet test SpeakType.Tests/...` **153/153 pass** (all 14 prior orchestrator tests green on the synchronous default + 2 new: the cycle is handed to the dispatcher rather than run inline; an auto-stop claim blocks a following release from running a second cycle). Windows x64 **CI also green** (run 26833167502).
- **Notes / decisions:**
  - **Brick 14 split (continued):** after 14a (time adapters), the composition root was still too big for one §2a brick, so this brick took the **Mac-testable** orchestrator-threading slice; the Windows composition root is now **Brick 14c**.
  - **`ICycleDispatcher` port, not a raw `Action<Action>` (code-review altitude):** the first cut injected `Action<Action>`; promoted to a named one-method port + a `SynchronousCycleDispatcher` default to match the codebase's ports convention (every other injected dependency is a named interface) and document the contract ("run the cycle once, possibly on another thread") for 14c.
  - **Complete locking discipline (code-review must-fix, 2 finders converged):** the first cut left three gaps — the `State=Pasting` write ungated, `OnPressed` publishing `Recording` (and stamping `_pressTimestamp` / starting capture) **outside** the lock (a thread-pool auto-stop could claim a cycle against an un-started capture), and a lock-free public `State` getter. Now **every** `_state` read/write goes through `_gate`, `OnPressed` is fully atomic (publishes `Recording` only after capture+timer start succeed), and the getter reads under the lock. Lock order is always orchestrator→timer (the timer fires `onElapsed` outside its own lock), so no deadlock.
  - **Concurrency is documented, not stress-tested:** the deterministic claim/dispatch behaviour is covered by the 2 new tests (via the controllable `DeferredDispatcher`); the pure memory-visibility/interleaving correctness is argued in code + the class doc (a real-thread stress test would be flaky — same precedent as `SystemAutoStopTimer`/`FileLogSink`).
  - **Deferred to Brick 9:** `OnPressed` still rethrows a capture-start failure to the hotkey thread (error *surfacing* is Brick 9's job; the state machine already resets to Idle so it never wedges).

### Brick 14a — Real time adapters (2026-06-02)
- **What:** Real implementations of the two time ports deferred from Brick 3b. `SystemClock : IClock` wraps `Stopwatch` (monotonic, wall-clock-immune) for press→release hold timing. `SystemAutoStopTimer : IAutoStopTimer` wraps a single `System.Threading.Timer` as a reliable **one-shot** with a lock-guarded **generation counter**, so a cancel or restart reliably drops a superseded/queued callback. Both live in `SpeakType.Core` (pure .NET, cross-platform). Not wired into the app yet — that's Brick 14b.
- **Files:** `SpeakType.Core/Time/{SystemClock.cs, SystemAutoStopTimer.cs}` (new); tests `SpeakType.Tests/Time/{SystemClockTests.cs, SystemAutoStopTimerTests.cs}` (new).
- **Verified:** Fully cross-platform → `dotnet test SpeakType.Tests/...` **151/151 pass** (8 new: clock one-second-ago band / never-negative / monotonic; timer fires-after-delay / cancel-prevents-fire / fires-once / cancel-no-op / null-callback-throws). Windows x64 **CI also green** (run 26831426782).
- **Notes / decisions:**
  - **Brick 14 split per CLAUDE.md §2a:** full end-to-end wiring was well past the hard ceiling (150 LOC / 5 files), so it split into **14a** (these cross-platform adapters, full Mac TDD loop) and **14b** (the Windows composition root). Follows the Bricks 1–4 pattern: unit-test the adapter in isolation before its consumer exists.
  - **Generation guard (all 4 /simplify + both review angles confirmed it's the right depth):** `Timer.Dispose()` does NOT stop a callback the thread pool already dequeued, so honoring the "Cancel → won't fire" contract needs a monotonic generation bumped under the lock; a fired callback only runs `onElapsed` if its generation is still current. `onElapsed` runs **outside** the lock (in production it runs the whole dictation cycle — keeps it deadlock/reentrancy-free).
  - **Documented limitation (code review):** a callback already *past* the generation check can still complete `onElapsed` after `Cancel`/`Dispose` returns ("won't *start*", not "won't *be running*"). The consumer must guard its own side — the orchestrator already does, via `OnAutoStop`'s recording-state check. **⚠ Brick 14b must serialize `OnAutoStop` (thread-pool thread) vs `OnReleased` (hotkey thread): both can currently observe `State==Recording` and double-run `RunCycle` (double `Stop()`/double `Completed`).**
  - **No deterministic concurrency test:** a real-timer interleaving test is inherently flaky; the guard's race-correctness is argued in the class doc instead (matches the `FileLogSink` documented-not-unit-tested precedent). The happy-path/cancel/one-shot/guard tests are deterministic.
  - **`ClearLocked()` helper (/simplify):** removed the bump/dispose/null teardown triplicated across `Cancel`/`Dispose`/`Fire`; `Dispose()` now aliases `Cancel()`.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
