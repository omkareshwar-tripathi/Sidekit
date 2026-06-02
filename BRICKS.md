# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

_Modern-light UI restyle (Option 1, light-only). Spec: `docs/superpowers/specs/2026-06-03-ui-modern-light-restyle-design.md`; plan: `docs/superpowers/plans/2026-06-03-ui-modern-light-restyle.md`. All Windows-only → verify = CI compile-green + a laptop screenshot vs mockup B (no Core changes; 179 tests stay green)._

- [ ] **Brick UI-3 — Restyle SettingsForm.** Apply `UiTheme`, swap the 4 checkboxes → `ToggleSwitch` (`MakeCheck`→`MakeToggle`, keep the `_loading` guard + all event wiring), flatten the hotkey field + model dropdown. First visible change.
  - Skill: dotnet-best-practices, run-tests
  - Verify: CI compile-green; laptop screenshot vs mockup B; re-check M6 (settings still apply live).
- [ ] **Brick UI-4 — Restyle WelcomeForm.** Apply `UiTheme` (Semibold heading, muted status), make Retry a primary accent button; keep the system progress bar.
  - Skill: dotnet-best-practices, run-tests
  - Verify: CI compile-green; laptop screenshot; re-check M2 (download + Retry still work).
- [ ] **Brick UI-5 — Flat tray menu.** Give the tray `ContextMenuStrip` a `ToolStripProfessionalRenderer(new FlatMenuColorTable())` + light font/colors (flat white menu, accent hover) in place of the gray gradient.
  - Skill: dotnet-best-practices, run-tests
  - Verify: CI compile-green; laptop screenshot; menu actions still work.

### Integration & ship

### Backlog (optional — needs a user decision, not in the v1 critical path)

- [ ] **Clipboard contention + paste error handling (revealed by Brick 8 review).** WinForms `Clipboard` throws transient `ExternalException` when another process holds the clipboard open; today that propagates out of `ClipboardPasteService.Paste` (and on Windows, up through the hotkey hook callback). Add best-effort retry/swallow in the `WinClipboard` adapter and decide the user-facing failure surface. Tightly coupled to Brick 9 (global exception handling) and Brick 14 (threading / marshalling the paste onto the STA thread) — fold in there rather than as a standalone brick if convenient.
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

### Brick UI-2 — ToggleSwitch control (2026-06-03)
- **What:** Second foundation brick of the modern-light restyle. Added `ToggleSwitch` — a small owner-drawn on/off switch (pill track + knob, painted via `UiTheme` colours: accent when on, grey `ToggleOff` when off, white knob) that replaces the square WinForms `CheckBox` in Settings. Exposes only the slice the forms use — `Checked` (bool) + `CheckedChanged` — and toggles on mouse click or Space/Enter. No animation (instant flip, per spec). **Not wired into any form yet** — that's UI-3.
- **Files:** `SpeakType.App/Controls/ToggleSwitch.cs` (new). No Core/test changes.
- **Verified:** Windows-only → **Windows x64 CI green** (run 26844485594, build + publish) = compile-green. Core suite untouched → **179/179**. `/simplify` → applied one nit (knob fill routed through `UiTheme.OnAccent` instead of a hardcoded `Color.White`, so a future dark-mode swap catches it; `OnAccent` *is* white → zero behaviour change). `/code-review` → found + **fixed one real correctness bug**: the focus ring was painted `if (Focused)` but nothing repainted on focus change, so the keyboard focus indicator never appeared/cleared on Tab — added `OnGotFocus`/`OnLostFocus` overrides that `Invalidate()`. **Visual + manual toggle behaviour: laptop screenshot/keyboard test comes with UI-3 (when it's first placed in a window).**
- **Notes / decisions:**
  - **Cosmetic knob-centering asymmetry deferred to the screenshot loop:** the off-state knob inset is 2px and the on-state is 1px (from the plan's exact pixels). Review flagged the slight asymmetry; rather than blind-guess pixel values on a Mac that can't render WinForms, this is left for the agreed laptop screenshot pass to tune against mockup B.
  - **Programmatic-set contract:** setting `Checked` raises `CheckedChanged`, but setting to the current value early-returns (no spurious fire); callers (SettingsForm in UI-3) set `Checked` before attaching the handler and gate with `_loading`, mirroring the old checkbox wiring.

### Brick UI-1 — UiTheme tokens + style helpers (2026-06-03)
- **What:** First foundation brick of the modern-light UI restyle. Added a central theme — `UiTheme` (Win11 "Fluent light" palette: bg `#F3F3F3`, white surface, accent `#0067C0`, secondary text `#616161`, etc.; Segoe UI body + Segoe UI Semibold heading fonts; 20px window padding / 12px row gap) plus three styling helpers (`StyleWindow`/`StyleField`/`StyleButton`) and a `FlatMenuColorTable` (flat white context-menu colours). Single source of truth so the look changes in one place (and dark mode is a future one-place swap). **No visible change yet** — nothing consumes it until UI-3/UI-4/UI-5.
- **Files:** `SpeakType.App/Theme/UiTheme.cs` (new). No Core/test changes.
- **Verified:** Windows-only (WinForms, `net8.0-windows`) → **Windows x64 CI green** (run 26844090822, incl. build + publish steps) = compile-green, the only automated proof for UI. Core suite untouched → still **179/179**. `/simplify` clean (no reuse/simplification/efficiency/altitude findings — confirmed no pre-existing theme/palette helper existed). `/code-review` clean (`[]`; brand-new unreferenced file, nothing removed/no callers). **Visual: no UI surface yet — first screenshot comes with UI-3.**
- **Notes / decisions:**
  - **`public` members inside an `internal static` class** → effective accessibility is internal (harmless; left as written in the plan).
  - **Tray-state colours (SteelBlue/Red/Orange/DarkRed) and the dark RecordingOverlay are intentionally NOT in UiTheme** — they're status-indicator / dark-HUD concerns, separate from the light chrome palette.
  - **Fonts are `static readonly`, held for process lifetime** (small fixed set, app is a singleton) — not disposed by design.

### Brick 17 — Unify per-user path literals via AppInfo.Name (2026-06-03)
- **What:** Pure cleanup (revealed by the Brick 13 review): the three per-user default paths each hardcoded the `"SpeakType"` folder string, although `AppInfo.Name` exists for exactly that (its doc-comment already cites these paths). Replaced the literal with `AppInfo.Name` at all three sites so renaming the app moves settings/models/logs together instead of leaving stragglers. No behavior change (`AppInfo.Name == "SpeakType"`).
- **Files:** `SpeakType.Core/Settings/JsonSettingsStore.cs` (`DefaultFilePath`), `SpeakType.Core/Models/ModelStore.cs` (`DefaultModelsDirectory`), `SpeakType.Core/Logging/FileLogSink.cs` (`DefaultLogPath`); tests `SpeakType.Tests/DefaultPathsTests.cs` (new, +3).
- **Verified:** Fully cross-platform → `dotnet test SpeakType.Tests/...` **179/179 pass** (3 new characterization tests assert each default ends with `Path.Combine(AppInfo.Name, …)` — green both before and after the swap, locking in the behavior the refactor preserves).
- **Notes / decisions:**
  - **Scope:** `AppInfo` resolves with no `using` from the `SpeakType.Core.*` sub-namespaces (enclosing-namespace lookup). The two remaining `"SpeakType…"` strings in the App layer are **UI copy** ("SpeakType Settings" title, the "already running" balloon), not the path folder — intentionally left (display text can diverge from the folder name). Backlog item retired.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
