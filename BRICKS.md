# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

### Integration & ship

- [ ] **Brick 14e — Settings, pause & model switch wiring.** Make the tray menu + settings window actually do things. (Brick 11 built `SettingsForm` raising events; Brick 14c built the pipeline; this connects them.)
  - **Tray + settings actions.** `tray.SettingsRequested` → show the single `SettingsForm`; `SettingsForm.HotkeyRebound` → `Win32HotkeyListener.Rebind` (treat as a cancel of any active capture); `SettingsForm.ModelChangeRequested` → download + verify the new model (progress), then **swap the live `ITranscriber`** via `SwappableTranscriber.Swap` (Brick 14g) — wrap the loaded transcriber in a `SwappableTranscriber` in `Program.cs`, inject *that* into the orchestrator, and on a model change build the new `WhisperTranscriber` and call `.Swap(...)` (the old one keeps working until the new file verifies; `Swap` disposes it). Call `Swap` on the UI thread (per its threading contract). `tray.PauseToggled` → `Win32HotkeyListener.Pause`/`Resume`.
  - **Active-capture cancel on rebind/pause (revealed by 14e scoping):** `Win32HotkeyListener.Rebind`/`Pause` won't fire `Released` for an in-progress hold, so the orchestrator could be left mid-`Recording`. It self-heals at the 60 s auto-stop, but consider exposing an orchestrator `Cancel()` (Core, Mac-testable) to reset cleanly — decide in the plan.
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

### Brick 14g — Live-swappable transcriber (Core) (2026-06-02)
- **What:** Built the runtime model-switch foundation: `SwappableTranscriber : ITranscriber, IDisposable` (Core) wraps a current inner transcriber that can be **hot-swapped** at runtime. `Transcribe` holds a lock for the whole call, so a `Swap` can never dispose/replace the inner mid-transcription; `Swap(newInner)` atomically replaces the inner and disposes the one it replaced (a no-op if it's already current). It **owns** its inner (`Dispose` disposes it). Not wired into the app yet — the composition-root injection + the Settings model-switch UI are Brick 14e; this brick builds + unit-tests the mechanism in isolation (mirrors how 14a built Core adapters before 14c wired them).
- **Files:** `SpeakType.Core/Transcription/SwappableTranscriber.cs` (new); tests `SpeakType.Tests/Transcription/SwappableTranscriberTests.cs` (new, +7).
- **Verified:** Fully cross-platform → `dotnet test SpeakType.Tests/...` **168/168 pass** (7 new: delegates to current inner; swap routes to the new inner; swap disposes the replaced inner; same-inner swap is a no-op that doesn't dispose; dispose disposes the inner; ctor + swap null guards). Windows x64 **CI also green** (run 26837136462).
- **Notes / decisions:**
  - **Brick 14e split:** the original 14e (Settings + pause + model-switch + autostart wiring) was far over §2a and almost entirely Windows-only/untestable. This brick carved out the one piece that had to be **built** (the swap mechanism) as a Mac-TDD Core class; the Settings window / pause / hotkey-rebind / autostart-unification / model-switch UI wiring remains queued as 14e (now able to call `SwappableTranscriber.Swap`).
  - **Lock-around-`Transcribe` is correct, not wasteful (simplify + review):** the orchestrator serializes cycles, so the lock is uncontended on the hot path; it exists only to coordinate the rare `Swap`. An atomic/`volatile` swap would reintroduce a **use-after-dispose** race (a `Transcribe` reading the old inner, then `Swap` disposing it mid-call), so the full-call lock is the simplest correct option. `Swap` disposes the old inner *outside* the lock — safe, since the full-call lock guarantees no call is still using it.
  - **Threading contract documented (code-review):** safe against a concurrent `Transcribe` (background cycle thread); `Swap`/`Dispose` must NOT race each other — they're single-threaded (UI thread) user/lifecycle actions, so concurrent swaps are out of scope by design. Argued, not stress-tested (precedent: `SystemAutoStopTimer`/`FileLogSink`).

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

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
