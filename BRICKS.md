# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

### Integration & ship

- [ ] **Brick 15 — Packaging.** Finalize self-contained single-file `win-x64` publish; confirm it runs on a clean machine (first-run download + autostart). Document SmartScreen-warning expectation.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — copy `.exe` to a clean profile/VM, launch → Welcome → download → dictation works.

### Backlog (optional — needs a user decision, not in the v1 critical path)

- [ ] **Clipboard contention + paste error handling (revealed by Brick 8 review).** WinForms `Clipboard` throws transient `ExternalException` when another process holds the clipboard open; today that propagates out of `ClipboardPasteService.Paste` (and on Windows, up through the hotkey hook callback). Add best-effort retry/swallow in the `WinClipboard` adapter and decide the user-facing failure surface. Tightly coupled to Brick 9 (global exception handling) and Brick 14 (threading / marshalling the paste onto the STA thread) — fold in there rather than as a standalone brick if convenient.
  - Skill: dotnet-best-practices, run-tests
- [ ] **Unify the `%APPDATA%/%LOCALAPPDATA%\SpeakType` path literal via `AppInfo.Name` (revealed by Brick 13 review).** `JsonSettingsStore.DefaultFilePath`, `ModelStore.DefaultModelsDirectory`, and `FileLogSink.DefaultLogPath` each hardcode the `"SpeakType"` string, though `AppInfo.Name` exists for exactly this (its doc-comment already says so). Three sites now — replace all three together (a one-off in `FileLogSink` would just make it the odd one out). Pure cleanup, Core-only, fully Mac-testable.
  - Skill: dotnet-best-practices, run-tests
- [ ] **Consolidate the duplicate capturing `ILogSink` test double (revealed by Brick 14d review).** `FakeLogSink` (`SpeakType.Tests/Orchestration/Fakes.cs`, added in 14d) is byte-for-byte the private `FakeSink` nested in `SpeakType.Tests/Logging/AppLoggerTests.cs` (Brick 13). Make `AppLoggerTests` use the shared `FakeLogSink` and delete its private copy. Deferred from 14d because it edits a shipped test file outside that brick's scope; rule-of-three only just met. Test-only, Mac-testable.
  - Skill: dotnet-xunit, run-tests
- [ ] **Shared test temp-dir helper (revealed by Brick 6b review).** The temp-dir scaffolding (`_tempDir` field + ctor + `Dispose`) is now duplicated across `JsonSettingsStoreTests`, `ModelStoreTests`, and `HttpModelDownloaderTests` (rule-of-three met). Extract a tiny `TempDir`/`TempDirFixture` IDisposable helper and have the three classes use it (~12 lines saved each). Deferred from Brick 6b to keep that brick from editing already-shipped test files; do it as its own small test-only brick.
  - Skill: dotnet-xunit, run-tests
- [ ] **Deferred-dispatcher SUT-builder test helper (revealed by Brick 14e review).** Four orchestrator tests now hand-build an orchestrator + `DeferredDispatcher` + outcomes list with the same ~11-line block (the in-flight-cycle cases that the shared `_sut` — built without a dispatcher — can't exercise). Extract a `BuildWithDeferredDispatcher(...)` helper returning the SUT + the fakes the tests assert on. Deferred from 14e because the fix would edit the three older tests outside that brick's scope. Test-only, Mac-testable.
  - Skill: dotnet-xunit, run-tests
- [ ] **Reconcile `AppSettings.Autostart` with an externally-edited Run key (revealed by Brick 14e review).** The `ApplyAutostart` funnel keeps the two in-app entry points in sync, but if the user removes SpeakType from startup *externally* (Task Manager → Startup, msconfig) between sessions, the next launch reconciles only the tray checkmark (`tray.SetStartWithWindowsChecked(autostart.IsEnabled())`); `settings.Autostart` keeps the stale `true` on disk and in the Settings checkbox — a three-way divergence. Pre-existing (the funnel didn't introduce it). Decide the source of truth (likely the Run key) and sync `settings.Autostart`/save at startup when the first-run gate is skipped. Windows-only; verify with M6.
  - Skill: dotnet-best-practices, run-tests

- [ ] **Cleanup-pipeline real-world hardening (revealed by Brick 2 review).** Decide whether to: (a) trim the always-filler list so it stops eating real tokens — `mm` (millimeter), `er` (ER), and possibly `ah` collide with genuine words/units; (b) make `i`→`I` skip abbreviation/list contexts like `i.e.` / `Section i` / `for i`; (c) fix the two niche defects — stacked leading fillers losing capitalization (`"Um er,"`) and hyphen-joined clusters (`"Mm-hmm."`). All three currently behave per spec lines 121/129; changing them is a spec decision, hence parked here rather than done autonomously.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests

## Done

_(Newest first. Older entries archived to `BRICKS-ARCHIVE.md`.)_

### Brick 14h — Live model switch (2026-06-03)
- **What:** Wired the last unwired Settings action: picking a different model in the dropdown now **downloads + verifies it and hot-swaps the live transcriber** at runtime (spec Feature 4), no restart. The composition root: (1) at startup loads the **persisted** model (`ModelCatalog.Resolve(settings.ModelSize)`, falling back to the default) instead of always `base.en` — so a chosen model survives a restart (the startup bug 14e left); (2) wraps the loaded transcriber in a **`SwappableTranscriber`** (14g) and injects *that* into the orchestrator; (3) on `SettingsForm.ModelChangeRequested`, opens the (now reusable) download window modally, and on a verified download builds a new `WhisperTranscriber` and `swappable.Swap(...)` on the UI thread (Swap disposes the old model); the **old model stays live during the download** (we only swap after verify). On any failure/cancel it **keeps the live model** and rolls back both the persisted `settings.ModelSize` and the dropdown selection (new `SettingsForm.RevertModelSelection`) so they match what's actually running. Quit now disposes via `swappable.Dispose()` (disposes whichever model is active).
- **Files:** `SpeakType.App/Program.cs` (startup model load, `SwappableTranscriber` wrap+inject, `ModelChangeRequested` handler, dispose); `SpeakType.App/Settings/SettingsForm.cs` (`_modelBox` field + `RevertModelSelection`); `SpeakType.App/Startup/WelcomeForm.cs` (optional `windowTitle`/`headingText` ctor params so the first-run window is reusable for a mid-session switch); `SpeakType.Core/Models/ModelCatalog.cs` (new `Resolve(string?)` helper); tests `SpeakType.Tests/Models/ModelCatalogTests.cs` (new, +4).
- **Verified:** The new Core `ModelCatalog.Resolve` is cross-platform → `dotnet test SpeakType.Tests/...` **176/176 pass** (4 new: known name unchanged; case-insensitive match; unknown → default; null → default). The App wiring is Windows-only → Windows x64 **CI green** (run 26841436903). **Manual M2 (switch to `small.en` → progress, old model usable during download, swaps when verified; kill network mid-download → error + previous model still active + dropdown reverts) deferred to the laptop.**
- **Notes / decisions:**
  - **Closes the 14e "cosmetic dropdown" interim:** the dropdown now actually applies live and the chosen model survives restart.
  - **Reentrancy is handled by modality (code-review):** the download `ShowDialog()` (no explicit owner) is modal against the active `SettingsForm`, which disables it — so the user can't fire a second `ModelChangeRequested` mid-download. Same pattern the shipped first-run/corrupt-on-load `WelcomeForm` flows already rely on; no extra guard added.
  - **Optimistic-persist window (code-review, accepted):** the dropdown's `SelectedIndexChanged` persists `settings.ModelSize` to the new name *before* the download starts; a crash mid-download leaves a not-yet-installed name on disk, but next startup's first-run gate (`GetInstalledModelPath` null → Welcome download) recovers it. Rollback re-saves the active name on failure/cancel.
  - **/simplify applied:** extracted the duplicated `ContainsKey(x) ? x : Default` idiom (was in Program.cs + SettingsForm) into `ModelCatalog.Resolve` (which made the brick Mac-testable); parameterized `WelcomeForm`'s title/heading rather than reusing the literal "Welcome…/Hold Right Ctrl…" first-run copy mid-session. Rejected: collapsing the `switched` flag into a try/catch with early `return` (would drop the cancel→rollback path); a `FindIndex` LINQ rewrite (not an `IEnumerable` method); extending `AppSettings.Normalize()` to catalog-validate (would rewrite the stored model on every load + add coupling).

### Brick 14e — Settings window, pause, hotkey-rebind & autostart wiring (+ orchestrator Cancel) (2026-06-03)
- **What:** Made the tray menu + Settings window actually *do* things (spec Features 6 & 7), minus model switching (split to 14h per §2a). The composition root now: (1) opens the single-instance **Settings window** on `tray.SettingsRequested` (Show/Activate; it hides itself on close); (2) re-registers the global hook live on `SettingsForm.HotkeyRebound` (`hotkey.Rebind` + `orchestrator.Cancel()`); (3) **pauses/resumes** listening on `tray.PauseToggled` (`hotkey.Pause`/`Resume`, + `Cancel()` on pause); and (4) unifies **autostart** through one `ApplyAutostart(bool)` funnel that keeps the Run key + persisted `AppSettings.Autostart` + tray checkmark in sync from both entry points (tray toggle and Settings checkbox). The filler/overlay/debug toggles already applied live (the form edits the shared `AppSettings`). Added a Core **`DictationOrchestrator.Cancel()`**: a pause/rebind mid-hold means the hook won't fire `Released`, so `Cancel()` resets a stuck `Recording` to `Idle` (discards audio, no transcribe/paste/`Completed`); a no-op unless currently Recording.
- **Files:** `SpeakType.Core/Orchestration/DictationOrchestrator.cs` (+`Cancel()`); `SpeakType.App/Program.cs` (settings-load moved earlier, `ApplyAutostart` funnel, settings/pause/rebind wiring); tests `SpeakType.Tests/Orchestration/DictationOrchestratorTests.cs` (+5) and `Fakes.cs` (`FakeAudioCapture.OnStop` probe hook).
- **Verified:** Core `Cancel()` is cross-platform → `dotnet test SpeakType.Tests/...` **172/172 pass** (5 new: cancel-while-recording discards; claim-held-during-Stop regression; cancel-when-idle no-op; cancel-during-active-cycle ignored; cancel-then-new-cycle still works). App wiring is Windows-only → Windows x64 **CI green** (run 26840089265). **Manual M6 (settings apply live + persist; Start-with-Windows Run-key toggle) and M7 (pause stops the hotkey, resets to active on restart) + the M1 hotkey-rebind item deferred to the laptop.**
- **Notes / decisions:**
  - **§2a split:** full 14e (which also bundled live model switch) was well over the ceiling, so the model dropdown's wiring became **Brick 14h**. Consequence (documented interim): the model dropdown in Settings now *opens and persists* `settings.ModelSize` to disk, but nothing applies it live and startup still loads `base.en` — 14h wires `ModelChangeRequested` + honors `settings.ModelSize` at startup. The dropdown is effectively cosmetic until then.
  - **Cancel Start/Stop race (code-review must-fix):** the first cut set `_state = Idle` *before* `_audioCapture.Stop()` (outside the lock). Since `Rebind` (unlike `Pause`) leaves the hook live, a fresh press during that `Stop()` window could pass `OnPressed`'s Idle guard and `Start()` a capture overlapping the `Stop()` — violating NAudioCapture's "Start/Stop never overlap" contract. Fixed with the **claim-transient** pattern (mirrors `DiscardRecording`/`TryClaimForProcessing`): claim to a non-Idle state, `Stop()` outside the lock while claimed (blocks a racing `Start()`), reset Idle in a `finally`, surface only Idle. Locked in by the `Cancel_keeps_the_cycle_claimed_while_stopping_capture` regression test.
  - **Pause vs an in-flight paste (by design):** `Cancel()` is a no-op unless Recording, so pausing mid-paste lets the current cycle finish (matches the documented "never interrupts a running cycle"). Spec pause is a session-only hook stop, not a cycle abort.
  - **Follow-ups revealed:** (a) autostart can still diverge from an *externally* edited Run key (user removes it via Task Manager → menu checkmark reconciles via `IsEnabled()` but `settings.Autostart` stays stale) — pre-existing, not closed by the funnel; (b) a 4th copy of the deferred-dispatcher SUT-construction block in the orchestrator tests → test-builder-helper consolidation. Both added to backlog.

### Brick 16 — Always-paste (drop the caret editable-target gate) (2026-06-02)
- **What:** Fixed the manual-testing finding that dictation only ever **landed text on the clipboard** instead of typing it into the focused field. The clipboard-safe paste used to pre-check for an editable target via `GetGUIThreadInfo`'s system caret (`hwndCaret`), but only legacy Win32 edit controls create a system caret — modern apps (browsers, VS Code, Slack, Win11 Notepad) report none, so the paste always fell back to leave-on-clipboard. Now the cycle **always simulates Ctrl+V**; it falls back to leave-on-clipboard (with the "Copied — paste manually" overlay) **only** when the OS actually blocks the keystroke (`SendPaste` returns false, e.g. an elevated foreground window). Removed the orphaned `HasEditableTarget` from `IClipboard`, `WinClipboard` (and its `GetGUIThreadInfo`/`GUITHREADINFO`/`RECT` interop), and `MarshallingClipboard`.
- **Files:** `SpeakType.Core/Paste/ClipboardPasteService.cs`, `SpeakType.Core/Paste/IClipboard.cs`, `SpeakType.App/Paste/WinClipboard.cs`, `SpeakType.App/Paste/MarshallingClipboard.cs`; tests `SpeakType.Tests/Paste/ClipboardPasteServiceTests.cs` (−1, the now-meaningless no-target case); `TESTING.md` (M4 reworded).
- **Verified:** Core paste logic is cross-platform → `dotnet test SpeakType.Tests/...` **167/167 pass** (`LeftOnClipboard` is now exercised solely by the blocked-paste case). The `WinClipboard`/`MarshallingClipboard` edits are Windows-only → Windows x64 **CI green** (run 26838857395). **Manual M4 (dictation types directly into Slack/VS Code/browser/Notepad; no-field case keeps text on clipboard) deferred to the laptop.**
- **Notes / decisions:**
  - **Supersedes a backlog item:** the "Editable-target detection via UI Automation" backlog item (revealed by the Brick 8 review) proposed *fixing* the caret check with UIA. The user chose the simpler **always-paste** route instead (focus detection is unreliable and a stray Ctrl+V into a non-editable surface is harmless — the text stays on the clipboard either way), so that backlog item is retired.
  - **Behaviour tradeoff (accepted):** dictating with **no field focused** now types nowhere but silently leaves the text on the clipboard *without* the "Copied — paste manually" hint (that message now only shows on a genuine blocked injection). Judged rare and acceptable per the user's decision; the words are never lost.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
