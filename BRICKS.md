# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

### Integration & ship

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

### Brick 14f — Cycle feedback + logging wiring (App) (2026-06-02)
- **What:** Wired Brick 14d's `StateChanged`/`Completed` events + injected `AppLogger` into the live UI and a log file (spec Feature 6 overlay/tray + Logging & Privacy). The composition root now drives the **tray colour** from every state (`TrayStatus.From` → Idle/Recording/Busy) and the **recording overlay** — 🎙 Listening on press, ⚙ Transcribing while the cycle runs, the outcome (No speech / Copied — paste manually) on completion, then fade. A **`FileLogSink`-backed `AppLogger`** (transcript gated live on `settings.DebugLogging`) is passed to the orchestrator, so each cycle writes `recording`/`transcribe`/`latency`/`error` (+ the transcript when Debug logging is on). The app now gives visible + logged feedback for every dictation, not just a silent paste.
- **Files:** `SpeakType.App/Program.cs` (overlay + logger construction; `StateChanged`/`Completed` wiring; `onError` now also fades the overlay). No new Core logic → no new unit tests (pure App composition; the units it wires are tested in 14d/13/earlier).
- **Verified:** App is **Windows-only — cannot build on Mac**; Windows x64 **CI is the compile gate** (green: run 26836353743). Core suite unchanged → `dotnet test SpeakType.Tests/...` **161/161**. **Manual M5 (overlay text/fade/no-focus-steal + tray colour transitions) and M8 (latency line in `%APPDATA%\SpeakType\logs\speaktype.log`) deferred to the laptop.**
- **Notes / decisions:**
  - **Show/clear invariant (code-review):** SHOWING the overlay is gated on `settings.Overlay`; CLEARING it (`FadeOut`) is unconditional — on `Idle`, on `Completed`, and on the dispatcher's `onError`. This pre-empts a latent orphan where toggling Overlay off mid-cycle (the live toggle Brick 14e adds) would otherwise leave a stale overlay stuck on screen.
  - **Error-path overlay clear (code-review):** a background-cycle exception fires neither `StateChanged(Idle)` (14d made it success-path-only) nor `Completed`, so the cycle's `onError` now also fades the overlay (the tray was already reset there).
  - **All UI touches marshalled:** `StateChanged`/`Completed` can fire on the background cycle thread, so every tray/overlay call goes through `UiMarshaller.Post`; they serialize on the one UI thread, so the `onError` `FadeOut` can't race a `StateChanged` `ShowStatus`. Shutdown is safe — once `Application.Run()` returns the pump is dead, so any late Post never executes (and `UiMarshaller.Post` already swallows on a disposed control).
  - **Outcome-overlay dwell — watch at M5:** the outcome text is shown then immediately faded (~330 ms) with no dwell hold; if it reads too briefly at M5, add a short one-shot dwell timer in `RecordingOverlay` before the fade (a small follow-up, not done speculatively).
  - **Brick 14d split:** 14d = Core observability (shipped); **14f = this App wiring.** Logging lives inside the cycle (14d) because only the cycle has the transcribe duration / char count / transcript / latency; this brick just constructs + injects the sink/logger.

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

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
