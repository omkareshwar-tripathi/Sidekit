# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

- [ ] **Brick 13 — Logging + performance timing.** Rolling log at `%APPDATA%\SpeakType\logs`; metadata + timings only by default; transcript text only when Debug logging on; log release→paste latency each run.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — log line formatting; transcript absent by default, present when debug on. Manual — latency line appears, observe vs <2 s goal.

### Integration & ship

- [ ] **Brick 14 — End-to-end wiring.** Compose the real adapters into the orchestrator behind composition root; full dictation works in a real app.
  - **Provide the real `IClock` (Stopwatch-backed) and `IAutoStopTimer` (`System.Threading.Timer`, one-shot via `Timeout.Infinite` period) adapters** (deferred from Brick 3b — no real impls exist yet).
  - **Own the threading model.** The orchestrator is synchronous in v1; the real auto-stop timer fires `OnAutoStop` on a thread-pool thread, so its `State` guard + `_pressTimestamp` are **not thread-safe** today. A release racing the 60 s fire could double-run the cycle. Marshal hotkey + timer callbacks onto one thread (or lock) here, and offload the capture→transcribe→paste work off the UI thread.
  - **`WhisperTranscriber.Transcribe` must run OFF the UI thread (Brick 7 review).** It bridges Whisper's async stream synchronously (`ToBlockingEnumerable`). Verified it will NOT deadlock (Whisper.net uses `ConfigureAwait(false)` + a thread-pool worker), but calling it inline on the WinForms UI thread **freezes the window** for the whole transcription. Wrap the cycle in `Task.Run`. Also: `WhisperTranscriber.Dispose()` throws if a transcription is still in flight — only dispose when idle (or switch to `DisposeAsync`), which the single-cycle + off-UI-thread design already ensures.
  - **Reference `Whisper.net.Runtime` from the App (Brick 7).** The `SpeakType.Whisper` adapter references only managed `Whisper.net`; the deployable app must add `Whisper.net.Runtime` (native libs) so Whisper actually runs — a packaging concern shared with Brick 15.
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
- [ ] **Shared test temp-dir helper (revealed by Brick 6b review).** The temp-dir scaffolding (`_tempDir` field + ctor + `Dispose`) is now duplicated across `JsonSettingsStoreTests`, `ModelStoreTests`, and `HttpModelDownloaderTests` (rule-of-three met). Extract a tiny `TempDir`/`TempDirFixture` IDisposable helper and have the three classes use it (~12 lines saved each). Deferred from Brick 6b to keep that brick from editing already-shipped test files; do it as its own small test-only brick.
  - Skill: dotnet-xunit, run-tests

- [ ] **Cleanup-pipeline real-world hardening (revealed by Brick 2 review).** Decide whether to: (a) trim the always-filler list so it stops eating real tokens — `mm` (millimeter), `er` (ER), and possibly `ah` collide with genuine words/units; (b) make `i`→`I` skip abbreviation/list contexts like `i.e.` / `Section i` / `for i`; (c) fix the two niche defects — stacked leading fillers losing capitalization (`"Um er,"`) and hyphen-joined clusters (`"Mm-hmm."`). All three currently behave per spec lines 121/129; changing them is a spec decision, hence parked here rather than done autonomously.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests

## Done

_(Newest first. Older entries archived to `BRICKS-ARCHIVE.md`.)_

### Brick 12 — First-run + autostart (2026-06-02)
- **What:** First-launch setup + Start-with-Windows (spec Feature 2 first-run + Feature 6 autostart). On first run (no `base.en` model on disk) a **Welcome window** shows the one-line how-to ("Hold Right Ctrl, speak, release.") and downloads `base.en` with a progress bar (Retry on failure); on success the app registers autostart and shows a **"Ready!"** tray balloon. If setup doesn't complete (download abandoned / window closed) the app **exits cleanly** rather than running with no usable model. **Autostart** is the per-user `HKCU\…\Run` key (default ON, applied once first-run setup succeeds), toggled from the tray "Start with Windows" item; the menu checkmark is reconciled to the real registry state at startup.
- **Files:** `SpeakType.Core/Startup/IAutostart.cs` (new port); `SpeakType.App/Startup/WinAutostart.cs` (new, Windows-only — HKCU Run key); `SpeakType.App/Startup/WelcomeForm.cs` (new, Windows-only); `SpeakType.App/Program.cs` (first-run + autostart wiring); `SpeakType.App/Tray/TrayIcon.cs` (added `SetStartWithWindowsChecked` to reconcile the menu with real state). No new Core logic → no new unit tests (IAutostart is a pure port; the rest is Windows-only, covered by manual M2/M6 + CI compile — mirrors Brick 11).
- **Verified:** Core suite unchanged → `dotnet test SpeakType.Tests/...` **127/127**. App is **Windows-only — cannot build on Mac**; Windows x64 **CI is the compile gate** (green: run 26827903701). **Manual M2 (first-run Welcome + download → "Ready!") and M6 (autostart Run-key add/remove, survives restart) deferred to the laptop.**
- **Notes / decisions:**
  - **Exit-on-incomplete-setup + autostart-after-success (code-review must-fix):** the first cut enabled autostart *before* the download and fell through to the tray loop even if the user cancelled — registering a login entry that boot-looped into the same broken first-run with no model. Now autostart is enabled only on `DialogResult.OK`, and a non-OK Welcome disposes the tray and exits. This also makes a tray **Quit during the download** actually quit (the modal's nested loop returns non-OK → exit).
  - **Retry re-entrancy guard (code-review must-fix):** `StartDownload` is `async void`; a queued double-click on Retry could start two concurrent `EnsureAsync` calls racing the same temp file + the shared (soon-disposed) CTS. A `_downloading` guard makes it single-flight.
  - **Tray checkmark reconciled to real state (code-review must-fix):** the menu item was hardcoded `Checked = true`; once the toggle drove a real registry write, a previously-disabled autostart showed a lying checkmark and inverted the next click. Program now sets it from `autostart.IsEnabled()` at startup (via the property, so it doesn't re-fire the toggle event).
  - **First-run = "default model file absent"** (lightweight existence check). A *corrupt/truncated* cached model is NOT re-downloaded by this gate — that's spec Feature 2 "corrupt-on-load," handled at model-load time in **Brick 14** (running SHA256 over a ~150 MB file on every launch would needlessly block startup).
  - **No Registry package needed:** `Microsoft.Win32.Registry` ships in the `net8.0-windows` desktop framework; the csproj was left untouched. `Environment.ProcessPath` gives the apphost `SpeakType.exe` for the intended self-contained publish (Brick 15); the Run-key value is quoted for Program-Files spaces.

### Brick 11 — Settings window (2026-06-02)
- **What:** The settings UI (spec Feature 7). `SettingsForm` (App) is a thin fixed dialog over the shared, live `AppSettings` with **no Save button** — every edit mutates that instance, persists via `ISettingsStore.Save`, and applies live. Controls: a **Hotkey** textbox (validated with `Hotkey.TryParse`), a **Model size** dropdown (the catalog ordered by size: tiny.en/base.en/small.en), and toggles for **Remove filler words**, **Show recording overlay**, **Start with Windows**, and **Debug logging**. Side-effects the form can't do itself are raised as events for the Brick 14 composition root: `HotkeyRebound` (re-register the global hook), `ModelChangeRequested` (download/switch the model), `AutostartChanged` (write/remove the HKCU Run key — Brick 12). Filler/overlay/debug need no event — they mutate the same `AppSettings` the orchestrator/logger already read.
- **Files:** `SpeakType.App/Settings/SettingsForm.cs` (new, Windows-only). No new Core code → no new unit tests (spec §8: adapters are manual-tested; settings round-trip/defaults/invalid-hotkey are already unit-tested in earlier bricks).
- **Verified:** Core suite unchanged → `dotnet test SpeakType.Tests/...` **127/127**. App is **Windows-only — cannot build on Mac**; Windows x64 **CI is the compile gate** (green: run 26826439447). **Manual M6 (change each setting → immediate effect; survives restart) deferred to the laptop.**
- **Notes / decisions:**
  - **Hotkey via `Leave` + a changed-guard + commit-on-close (code review must-fix):** the first cut used `Validating`+`e.Cancel`, which under the form's default `AutoValidate.EnableAllowFocusChange` doesn't trap focus — so a newly-typed valid hotkey could be **lost on close**, and merely re-focusing the box **re-saved + re-registered the hook**. Now it applies on `Leave` only when the text actually changed, and `OnFormClosing` commits a pending valid value before hiding (and discards an invalid one).
  - **Orphaned `ModelSize` reconciled (code review must-fix):** `AppSettings.Normalize()` only null-checks, so a stored model name not in the catalog would leave the `DropDownList` **blank** and the setting unreconciled. The form now falls back to `DefaultModelSize` and updates the in-memory setting, so the dropdown is never empty.
  - **Shared-instance + Save-per-edit** is what makes filler/overlay/debug apply live for free. **Brick 14 owns failure/rollback** — the form persists-then-notifies and can't itself undo a setting if a side-effect (e.g. a model download) fails.
  - **No Save button** per spec; closing the window hides it so the single instance is reshown.

### Brick 10 — Recording overlay (2026-06-02)
- **What:** The on-screen status overlay (spec Feature 6). `RecordingOverlay` (App) is a borderless, always-on-top, **no-activate, click-through** `Form` that **never steals focus** (so the paste target keeps its caret), shown near the **bottom-center of the active monitor**. `ShowStatus(OverlayStatus)` displays the right text per state and `FadeOut()` fades it away on completion. The exact display strings — **🎙 Listening…**, **⚙ Transcribing…**, **No speech detected**, **Copied — paste manually** — live in Core (`OverlayText.For`, unit-tested), mirroring the `TrayState` precedent.
- **Files:** `SpeakType.Core/Overlay/OverlayStatus.cs` (new); tests `SpeakType.Tests/Overlay/OverlayTextTests.cs` (new); `SpeakType.App/Overlay/RecordingOverlay.cs` (new, Windows-only). Drive + `AppSettings.Overlay` gating deferred to Brick 14.
- **Verified:** Core on Mac → `dotnet test SpeakType.Tests/...` **127/127 pass** (4 new theory cases: the status→text mapping). App is **Windows-only — cannot build on Mac**; Windows x64 **CI is the compile gate** (green: run 26825692605, after a `fix` for a `Timer` ambiguity — see below). **Manual M5 (appears bottom-center, correct text, fades, never steals focus) deferred to the laptop.**
- **Notes / decisions:**
  - **Alpha via `SetLayeredWindowAttributes`, not `Form.Opacity` (code review must-fix):** the original set `WS_EX_LAYERED` in `CreateParams` *and* used `Form.Opacity`, a known trap that can leave the window invisible (Opacity manages the layered style itself). The overlay now drives a layered+transparent window's uniform alpha directly (LWA_ALPHA) — the reliable click-through-fading-overlay recipe.
  - **`Timer` ambiguity broke the Windows build (CI caught it):** WinForms `Timer` collided with `System.Threading.Timer` (in the implicit usings) → CS0104; fixed by fully-qualifying `System.Windows.Forms.Timer`. (The Mac unit suite can't compile App, so CI is the gate — it did its job.)
  - **Font leak fixed (code review):** the label's explicitly-created `Font` was never disposed; it's now a field disposed with the form (and the redundant `_label.Dispose()` was dropped — the Controls collection disposes it).
  - **"Active monitor" = the cursor's screen** — a reasonable v1 heuristic; resolving the foreground window's screen is a later refinement.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
