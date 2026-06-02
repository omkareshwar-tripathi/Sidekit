# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

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
  - **`WhisperTranscriber.Transcribe` must run OFF the UI thread (Brick 7 review).** It bridges Whisper's async stream synchronously (`ToBlockingEnumerable`). Verified it will NOT deadlock (Whisper.net uses `ConfigureAwait(false)` + a thread-pool worker), but calling it inline on the WinForms UI thread **freezes the window** for the whole transcription. Wrap the cycle in `Task.Run`. Also: `WhisperTranscriber.Dispose()` throws if a transcription is still in flight — only dispose when idle (or switch to `DisposeAsync`), which the single-cycle + off-UI-thread design already ensures.
  - **Reference `Whisper.net.Runtime` from the App (Brick 7).** The `SpeakType.Whisper` adapter references only managed `Whisper.net`; the deployable app must add `Whisper.net.Runtime` (native libs) so Whisper actually runs — a packaging concern shared with Brick 15.
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
- [ ] **Shared test temp-dir helper (revealed by Brick 6b review).** The temp-dir scaffolding (`_tempDir` field + ctor + `Dispose`) is now duplicated across `JsonSettingsStoreTests`, `ModelStoreTests`, and `HttpModelDownloaderTests` (rule-of-three met). Extract a tiny `TempDir`/`TempDirFixture` IDisposable helper and have the three classes use it (~12 lines saved each). Deferred from Brick 6b to keep that brick from editing already-shipped test files; do it as its own small test-only brick.
  - Skill: dotnet-xunit, run-tests

- [ ] **Cleanup-pipeline real-world hardening (revealed by Brick 2 review).** Decide whether to: (a) trim the always-filler list so it stops eating real tokens — `mm` (millimeter), `er` (ER), and possibly `ah` collide with genuine words/units; (b) make `i`→`I` skip abbreviation/list contexts like `i.e.` / `Section i` / `for i`; (c) fix the two niche defects — stacked leading fillers losing capitalization (`"Um er,"`) and hyphen-joined clusters (`"Mm-hmm."`). All three currently behave per spec lines 121/129; changing them is a spec decision, hence parked here rather than done autonomously.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests

## Done

_(Newest first. Older entries archived to `BRICKS-ARCHIVE.md`.)_

### Brick 9 — System tray app + lifecycle (2026-06-02)
- **What:** The app's persistent presence + lifecycle shell (spec Feature 6). `TrayIcon` (App) is a `NotifyIcon` whose icon + tooltip reflect four states — Idle/Recording/Busy/Error — drawn **programmatically** (filled circles, no binary `.ico` assets), plus a right-click menu: **Settings…**, **Pause listening** (checkable), **Start with Windows** (checkable, default ON), **About**, **Quit**. The menu raises events (`SettingsRequested`/`PauseToggled`/`StartWithWindowsToggled`/`QuitRequested`) for the Brick 14 composition root to wire to the orchestrator; About is handled in place; it exposes `SetState(TrayState)`/`ShowBalloon(...)`. `Program` does **single-instance** via the `SpeakType.Single` mutex (a 2nd launch shows an "already running" balloon and exits) and installs **global exception handlers**. The pure `RecordingState→TrayState` mapping (Transcribing/Pasting→Busy) lives in Core (`TrayStatus.From`).
- **Files:** `SpeakType.Core/Orchestration/TrayState.cs` (new), `SpeakType.Core/AppInfo.cs` (added `SingleInstanceMutexName`); tests `SpeakType.Tests/Orchestration/TrayStateTests.cs` (new); `SpeakType.App/Tray/TrayIcon.cs` (new, Windows-only), `SpeakType.App/Program.cs` (rewrote the Brick-0 scaffold into the tray lifecycle). Orchestrator wiring deferred to Brick 14.
- **Verified:** Core on Mac → `dotnet test SpeakType.Tests/...` **123/123 pass** (4 new theory cases: the state mapping). App is **Windows-only — cannot build on Mac**; Windows x64 **CI is the compile gate** (green: run 26824885574). **Manual M5 (icon changes per state) + M7 (second-instance balloon, pause, error→balloon→recover) deferred to the laptop.**
- **Notes / decisions:**
  - **Exception-handler semantics fixed (code review must-fix):** only `Application.ThreadException` (UI thread) can actually *recover* — it logs, balloons, and resets the tray to Idle while the message loop keeps running. `AppDomain.UnhandledException` runs on the throwing (non-UI) thread and **cannot stop termination**, so it must not touch the `NotifyIcon` (cross-thread) — it now only last-chance-logs. The original code ballooned cross-thread and falsely claimed recovery.
  - **HICON leak fixed (code review):** `Icon.FromHandle(bitmap.GetHicon())` doesn't own the handle, so the `Dispose` loop was misleading and leaked 4 GDI handles. Now clones an owning `Icon` and `DestroyIcon`s the original (via `[LibraryImport]`), so `Dispose` is honest.
  - **Second-instance balloon needs a pump (code review):** a balloon won't render without a running message loop, so the "already running" path runs a brief `Application.Run()` that exits on a timer instead of `Thread.Sleep`.
  - **Icons generated in code, not shipped as assets** — keeps the brick self-contained and avoids committing binaries; colors Idle=SteelBlue, Recording=Red, Busy=Orange, Error=DarkRed.
  - **`TrayState.Error`** has no `RecordingState` source by design — it's a spec-listed tray state set explicitly by Brick 14's adapter-failure handling (e.g. "No microphone found") via `SetState`, so it's staged, not dead.

### Brick 8 — Clipboard-safe paste (2026-06-02)
- **What:** "Works everywhere" paste (spec Feature 5). Behind the ports-and-adapters seam: a new `IClipboard` port (Core) with text-only save/restore primitives, a best-effort editable-target check, and a `SendPaste` that reports whether the keystrokes were actually injected. `ClipboardPasteService` (Core) runs the sequence **save current clipboard text → set our text → check for a focused editable target → Ctrl+V → wait ~150 ms (so the target can read the clipboard) → restore the original**. If no editable target is confirmed **or** the OS blocks the paste injection, it skips the restore and **leaves our text on the clipboard** (`PasteOutcome.LeftOnClipboard` → overlay "Copied — paste manually"), so the user's words are never silently lost. The Windows adapter `WinClipboard` (App) wraps WinForms `Clipboard` + `SendInput` Ctrl+V + `GetGUIThreadInfo` caret detection. Not wired into the app yet (Brick 14).
- **Files:** `SpeakType.Core/Paste/{IClipboard.cs, ClipboardPasteService.cs}` (new); `SpeakType.App/Paste/WinClipboard.cs` (new, Windows-only); tests `SpeakType.Tests/Paste/ClipboardPasteServiceTests.cs` (new).
- **Verified:** Core on Mac → `dotnet test SpeakType.Tests/...` **119/119 pass** (7 new: full-sequence ordering, restore-after-delay ordering, null-original → `Clear`, no-target leave-on-clipboard, **blocked-paste leave-on-clipboard**, null-text and null-clipboard guards). App adapter is **Windows-only — cannot build on Mac**; Windows x64 **CI is the compile gate** (green: run 26823975915). **Manual M4 deferred to the laptop** (paste into Slack, clipboard restored, click-desktop → "Copied — paste manually").
- **Notes / decisions:**
  - **Save-then-set, in both branches** — our cleaned text is put on the clipboard *before* the target check, so even the leave-on-clipboard path preserves the words. The injected `Action<TimeSpan>` delay keeps the 150 ms restore-wait policy in Core while making the ordering unit-testable without real sleeping.
  - **SendPaste returns success (code review must-fix):** the original ignored `SendInput`'s return, so a paste blocked by UIPI (non-elevated app → elevated foreground window) would still restore the old clipboard and report success, silently losing the dictation. Now a blocked injection returns `LeftOnClipboard` and keeps our text. Core-tested.
  - **CS0649 build-break averted (code review must-fix):** the Win32 interop structs (`MOUSEINPUT`/`RECT`/unused `GUITHREADINFO` members) have fields populated only by the marshaller, which trips CS0649 under `TreatWarningsAsErrors` — fixed with a scoped `#pragma warning disable CS0649` (the existing hotkey adapter sidestepped this by reading raw bytes). This would have failed CI; caught before push.
  - **`GetGUIThreadInfo(0, …)`** uses the foreground thread directly, dropping the `GetForegroundWindow`+`GetWindowThreadProcessId` dance (simpler, avoids a rare focus-on-another-thread false negative).
  - **Follow-ups revealed (see Backlog):** the caret-only target check returns false for **Electron/Chromium** apps (Slack, VS Code, Chrome, Discord) → they hit leave-on-clipboard, which **M4 expects to paste** — needs UI Automation. Also clipboard `ExternalException` contention + the STA-thread requirement are owned by Bricks 9/14 (error handling + threading), noted on `WinClipboard`.

### Brick 7 — On-device Whisper transcriber (2026-06-02)
- **What:** The actual speech-to-text (spec Feature 2). New **cross-platform** `SpeakType.Whisper` project with `WhisperTranscriber : ITranscriber` over Whisper.NET: loads a ggml model once, then `Transcribe(float[] samples)` runs whisper.cpp with `language="en"` and `threads = max(1, cpu-1)` and returns the trimmed transcript (bridges Whisper's async stream via `ToBlockingEnumerable`). The adapter references only the **managed** `Whisper.net` so `Core` stays dependency-free and the engine runs on macOS/Windows/Linux. Whisper.NET was validated on this Mac (Metal-accelerated) before building — see the spike notes below.
- **Files:** `SpeakType.Whisper/{SpeakType.Whisper.csproj, WhisperTranscriber.cs}` (new); `SpeakType.Whisper.Tests/{SpeakType.Whisper.Tests.csproj, WhisperTranscriberTests.cs, assets/hello.wav}` (new integration test project); `SpeakType.sln` (both projects added). App wiring is deferred to Brick 14.
- **Verified (on Mac):** fast suite `dotnet test SpeakType.Tests/...` still **112/112**; the adapter builds warning-clean; and the gated **end-to-end integration test passes for real** — it downloads `tiny.en` via the real `ModelStore`+`HttpModelDownloader`, decodes the committed WAV via `AudioMath.Pcm16ToFloat`, transcribes, and asserts the words (produced "The quick brown fox jumps over the lazy dog."). So it exercises Bricks **5+6+7** together. The test is `[Trait("Category","Integration")]` + `[SkippableFact]` (skips offline); CI's fast job excludes `Category=Integration`, so it **builds but does not run** there (green: run 26822466951). Real-mic + the laptop is M1/M8.
- **Notes / decisions:**
  - **Separate `SpeakType.Whisper` project (not Core, not App):** Whisper.NET is a heavy native dependency; isolating it keeps `Core` pure/cross-platform and out of the fast unit suite, mirroring the `ISettingsStore`→`JsonSettingsStore` shape. The integration test references `Whisper.net.Runtime` (native libs) only in the test project.
  - **Pre-build spike validated portability:** Whisper.NET 1.9.1 runs on Apple-Silicon Mac (Metal); the runtime package ships native libs for macOS/Windows/Linux/Android in one package. A 3-model bench (tiny/base/small) + a real-voice recording confirmed **base.en is the right default** (≈small accuracy at ~3× the speed; tiny weakest), feeding the Brick 11 model dropdown. The catalog sizes/SHA256 were confirmed against real downloads.
  - **Integration test = real download path (intentional "duplication"):** code review suggested replacing the hand-rolled WAV parser with Whisper.net's `ProcessAsync(Stream)`; declined, because that would bypass `AudioMath.Pcm16ToFloat` + `Transcribe(float[])` — i.e. stop testing the *production* path (the app feeds `float[]` from the mic, never a WAV file). The robust RIFF chunk-scan was load-bearing: the `say`/`afconvert` WAV's data chunk starts at offset 4096, not 44.
  - **Threading deferred to Brick 14 (review, noted there):** `Transcribe` won't deadlock but freezes its calling thread for the transcription duration — Brick 14 must run the cycle off the UI thread; and the deployable app must add `Whisper.net.Runtime`.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
