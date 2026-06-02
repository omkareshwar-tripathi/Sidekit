# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

### Integration & ship

- [ ] **Brick 14f — Cycle feedback + logging wiring (App).** Wire Brick 14d's `StateChanged` event + injected `AppLogger` into the live UI and a log file. (Brick 14d made the cycle observable in Core; the tray still shows Idle and `Program.cs` constructs no logger.) **Windows-only → CI compile gate + manual.**
  - **Tray-state + overlay from `StateChanged`/`Completed`.** Subscribe to the orchestrator's new `StateChanged` event: `Recording` → 🎙 Listening overlay + tray Recording; `Transcribing` → ⚙ Transcribing overlay + tray Busy; `Pasting` → tray Busy (no overlay change); `Idle` → tray Idle + overlay `FadeOut`. On `Completed`: `NoSpeech`/`LeftOnClipboard` → `ShowStatus` the outcome then fade; `Pasted` → fade. All gated on `settings.Overlay` and **marshalled to the UI thread** via `UiMarshaller.Post` (StateChanged/Completed fire on the background cycle thread). Reuse the existing `RecordingOverlay` (`ShowStatus(OverlayStatus)`/`FadeOut`) + `TrayStatus.From(RecordingState)`.
  - **Logging wiring.** Construct `FileLogSink(FileLogSink.DefaultLogPath)` → `AppLogger(sink, () => settings.DebugLogging)` (live `Func<bool>`) and pass it as the orchestrator's trailing `logger:` arg. (Brick 14d already emits every line from inside the cycle and measures latency with the monotonic clock; this brick only constructs + injects the logger.)
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M5** (overlay text/fade/no-focus-steal), tray colour transitions; **M8** latency line in the log. Note: the outcome overlay may need a short dwell timer if `ShowStatus`+`FadeOut` flashes too briefly — check at M5.

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
- [ ] **Consolidate the duplicate capturing `ILogSink` test double (revealed by Brick 14d review).** `FakeLogSink` (`SpeakType.Tests/Orchestration/Fakes.cs`, added in 14d) is byte-for-byte the private `FakeSink` nested in `SpeakType.Tests/Logging/AppLoggerTests.cs` (Brick 13). Make `AppLoggerTests` use the shared `FakeLogSink` and delete its private copy. Deferred from 14d because it edits a shipped test file outside that brick's scope; rule-of-three only just met. Test-only, Mac-testable.
  - Skill: dotnet-xunit, run-tests
- [ ] **Shared test temp-dir helper (revealed by Brick 6b review).** The temp-dir scaffolding (`_tempDir` field + ctor + `Dispose`) is now duplicated across `JsonSettingsStoreTests`, `ModelStoreTests`, and `HttpModelDownloaderTests` (rule-of-three met). Extract a tiny `TempDir`/`TempDirFixture` IDisposable helper and have the three classes use it (~12 lines saved each). Deferred from Brick 6b to keep that brick from editing already-shipped test files; do it as its own small test-only brick.
  - Skill: dotnet-xunit, run-tests

- [ ] **Cleanup-pipeline real-world hardening (revealed by Brick 2 review).** Decide whether to: (a) trim the always-filler list so it stops eating real tokens — `mm` (millimeter), `er` (ER), and possibly `ah` collide with genuine words/units; (b) make `i`→`I` skip abbreviation/list contexts like `i.e.` / `Section i` / `for i`; (c) fix the two niche defects — stacked leading fillers losing capitalization (`"Um er,"`) and hyphen-joined clusters (`"Mm-hmm."`). All three currently behave per spec lines 121/129; changing them is a spec decision, hence parked here rather than done autonomously.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests

## Done

_(Newest first. Older entries archived to `BRICKS-ARCHIVE.md`.)_

### Brick 14d — Orchestrator observability (state-changed event + cycle logging) (2026-06-02)
- **What:** Made the dictation cycle observable so the App can drive UI feedback + a log file (the wiring is Brick 14f). Added (1) a `StateChanged` event on `DictationOrchestrator` (`EventHandler<RecordingState>`) reporting the UI-meaningful lifecycle — `Recording` on press, `Transcribing` when a cycle actually begins, `Pasting` while text is pasted, `Idle` when it finishes or a tap is discarded (the transient `Transcribing` an accidental tap passes through is deliberately NOT surfaced); and (2) an optional injected `AppLogger` (trailing ctor param, default `null` = no logging) that the cycle calls — `Recording(holdDuration)`, `Transcribed(transcribeDuration, charCount)`, `Transcript(text)` (debug-only), `Latency(release→paste)`, `Error(msg)` — timing the transcribe + release→paste latency with the monotonic clock. No app-visible change yet (logger is `null` in `Program.cs` until 14f).
- **Files:** `SpeakType.Core/Orchestration/DictationOrchestrator.cs` (changed: event + raises, logger param/field, `StartCycle`, transcribe/latency timing); tests `SpeakType.Tests/Orchestration/DictationOrchestratorTests.cs` (+8) and `Fakes.cs` (+`FakeLogSink`).
- **Verified:** Fully cross-platform → `dotnet test SpeakType.Tests/...` **161/161 pass** (8 new: 4 StateChanged lifecycle sequences incl. tap-skips-Transcribing + auto-stop; 4 logging — full line set, transcript-omitted-when-debug-off, error-logged-on-throw, silent-audio-logs-only-recording). Windows x64 **CI also green** (run 26835742946).
- **Notes / decisions:**
  - **Brick 14d split:** the original 14d (feedback + logging) spanned Core + Windows-only App and was over §2a (≈12 tests, mixed-platform, 5 files), so it split along the Core/App seam: **14d** = this Core observability (full Mac TDD); **14f** = the App wiring (tray/overlay + FileLogSink, Windows-only/CI).
  - **`StateChanged` surfaces committed transitions, not every `_state` write:** `Transcribing` is raised in `StartCycle` (after the MinHold gate), not in `TryClaimForProcessing`, so an accidental tap (claim→discard) never flashes Transcribing. Raised outside the lock, like `Completed`.
  - **Logging lives inside the cycle, not driven from App events (altitude):** transcribe duration, char count, transcript text, and latency only exist inside the cycle; driving logging from `Completed`/`StateChanged` would force widening those UI-facing payloads with diagnostics (and leak the privacy-sensitive transcript out of Core). `AppLogger?` is injected with null-conditional calls → tests omit it, prod wires it in 14f.
  - **Don't raise events from a `finally` (code-review must-fix):** the first cut raised `StateChanged(Idle)` inside `RunCycle`/`DiscardRecording`'s `finally` — a throwing handler there would mask the in-flight adapter exception. Moved both out so `Idle` fires on the normal path only (the error path's UI reset is owned by the dispatcher's `onError`); the state-reset stays in the `finally`. Mirrors the pre-existing `Completed` placement.
  - **Follow-up revealed:** `FakeLogSink` duplicates the private `FakeSink` in `AppLoggerTests` (Brick 13) → backlog consolidation (deferred — touches a shipped file).

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

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
