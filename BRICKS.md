# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

### Integration & ship

- [ ] **Brick 14c — End-to-end wiring (composition root).** Compose the real adapters into the orchestrator behind the composition root; full dictation works in a real app. (Bricks 14a + 14b already built + tested the real `SystemClock`/`SystemAutoStopTimer` and the thread-safe orchestrator — wire those here; do NOT re-create them.)
  - **Supply the real `ICycleDispatcher` + marshal UI work (the threading model).** Brick 14b made the orchestrator thread-safe (atomic state claim closes the release-vs-auto-stop double-run race) and added an injected `ICycleDispatcher` so the cycle can run off the UI thread. Here, pass a dispatcher that runs `RunCycle` on a **background thread** (e.g. `Task.Run`), so `WhisperTranscriber.Transcribe` never freezes the window. Because the cycle then runs off the UI thread, **the paste (`WinClipboard` — STA), tray-state, and overlay updates must be marshalled back to the UI thread** (capture the WinForms `SynchronizationContext` / a marshalling control). The hotkey hook + auto-stop callback can drive the orchestrator concurrently — the lock + claim make that safe — so no extra serialization is required, only the UI marshalling.
  - **`WhisperTranscriber.Transcribe` must run OFF the UI thread (Brick 7 review).** It bridges Whisper's async stream synchronously (`ToBlockingEnumerable`). Verified it will NOT deadlock (Whisper.net uses `ConfigureAwait(false)` + a thread-pool worker), but calling it inline on the WinForms UI thread **freezes the window** for the whole transcription. Wrap the cycle in `Task.Run`. Also: `WhisperTranscriber.Dispose()` throws if a transcription is still in flight — only dispose when idle (or switch to `DisposeAsync`), which the single-cycle + off-UI-thread design already ensures.
  - **Reference `Whisper.net.Runtime` from the App (Brick 7).** The `SpeakType.Whisper` adapter references only managed `Whisper.net`; the deployable app must add `Whisper.net.Runtime` (native libs) so Whisper actually runs — a packaging concern shared with Brick 15.
  - **Logging wiring (from Brick 13).** Construct `FileLogSink(FileLogSink.DefaultLogPath)` → wrap in `AppLogger`, passing `() => settings.DebugLogging` (a live `Func<bool>`, NOT a captured bool, so the Debug-logging toggle applies immediately). Call `Recording`/`Transcribed`/`Latency`/`Transcript`/`Error` from the dictation cycle; measure release→paste latency with the monotonic Stopwatch `IClock` (avoids the negative-latency case). The sink is best-effort (never throws) and process-locks, so it's safe to call from the timer/UI/background threads.
  - **Autostart wiring (deferred from Brick 12).** Brick 12 wired only the tray "Start with Windows" toggle → `WinAutostart`. Funnel that AND `SettingsForm.AutostartChanged` through one `ApplyAutostart(bool)` path that also keeps both surfaces (tray checkmark + Settings checkbox) and `AppSettings.Autostart` in sync. **Gate the hotkey on model readiness** (Brick 12 makes the app exit if first-run setup is abandoned, but once running, the hotkey must stay inert until the model is actually loaded). Handle **corrupt-on-load re-download** (spec Feature 2): Brick 12's first-run gate is existence-only, so a truncated/stale cached model is re-downloaded only here, at load time.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M1** end-to-end + **M8** (full happy path across Notepad/Slack/browser).

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

### Brick 13 — Logging + performance timing (2026-06-02)
- **What:** Local diagnostic logging (spec Logging & Privacy + Performance). `AppLogger` (Core) formats one line per dictation-cycle event — `recording 7.2s`, `transcribe 1.4s, 38 chars`, `latency 1.8s` (the release→paste perf line, logged each run), `error: …` — **always**; the **transcribed text** is logged **only when Debug logging is on** (privacy default = off), with the flag read **live** (a `Func<bool>`) so the Settings toggle applies immediately. `FileLogSink` (Core) writes to `%APPDATA%\SpeakType\logs\speaktype.log`, size-rolling to one `.1` backup, thread-safe, timestamp-prefixed. Not wired into the orchestrator yet (Brick 14).
- **Files:** `SpeakType.Core/Logging/{ILogSink.cs, AppLogger.cs, FileLogSink.cs}` (new); tests `SpeakType.Tests/Logging/{AppLoggerTests.cs, FileLogSinkTests.cs}` (new).
- **Verified:** Fully cross-platform → `dotnet test SpeakType.Tests/...` **143/143 pass** (16 new: each metadata line's format, transcript absent-by-default / present-when-debug / live-flag, file+dir creation, append, timestamp prefix, rolling-preserves-old-content-in-backup, non-positive-maxBytes guard, best-effort I/O-failure swallow, newline collapse). Windows x64 **CI also green** (run 26829056095). **Manual: the latency line is observed end-to-end in M8 (Brick 14).**
- **Notes / decisions:**
  - **Best-effort sink (code-review must-fix):** `FileLogSink.Write` wraps its file I/O in a swallow — a logger must never take down the thing it observes (disk full, permissions, AV lock, a dir deleted mid-run). The `ILogSink` contract now states Write never throws and emits one physical line.
  - **Newline sanitization (code-review must-fix):** dictated transcripts legitimately contain newlines; written raw they'd split into multiple un-timestamped physical lines and could **forge a log line** (injection). `Write` collapses embedded newlines (`ReplaceLineEndings(" ")`) so each event is exactly one line.
  - **Non-positive `maxBytes` guard (code-review must-fix):** `maxBytes <= 0` would roll on every write, silently destroying history; the ctor now rejects it (mirrors the existing `ThrowIfNullOrEmpty(filePath)`).
  - **Three-way split** (`ILogSink` port / `AppLogger` formatting brain / `FileLogSink` adapter) keeps formatting + the privacy gate pure and unit-testable; timestamp/rolling/locking live in the adapter. File I/O lives in Core because the project already puts cross-platform file I/O there (`ModelStore`, `JsonSettingsStore`) — so the whole brick is Mac-testable.
  - **Single `.1` backup** is the spec's minimum "rolling" interpretation (bounds disk ~2×maxBytes); N-generation rolling is a deferrable design decision, not done autonomously. The `"SpeakType"` path literal is now a 3-site duplication vs `AppInfo.Name` → backlog cleanup.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
