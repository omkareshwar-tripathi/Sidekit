# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

_Modern-light UI restyle (Option 1, light-only). Spec: `docs/superpowers/specs/2026-06-03-ui-modern-light-restyle-design.md`; plan: `docs/superpowers/plans/2026-06-03-ui-modern-light-restyle.md`. All Windows-only → verify = CI compile-green + a laptop screenshot vs mockup B (no Core changes; 179 tests stay green)._

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

### Brick UI-4 — Restyle WelcomeForm (2026-06-03)
- **What:** Restyled the model-download / first-run Welcome window (also reused for a mid-session model switch) to the modern-light look: light background + Segoe UI via `StyleWindow`, a **Segoe UI Semibold heading**, **muted (TextSecondary) status text**, and the **Retry button as a primary accent button** via `StyleButton`. The system `ProgressBar` is left as-is (already accent-coloured on Win11). **Behaviour unchanged** — the async download, the `_downloading` re-entrancy guard, Retry, and cancel-on-close are untouched.
- **Files:** `SpeakType.App/Startup/WelcomeForm.cs` (using + `StyleWindow` + heading font + status colour + `StyleButton(_retry)`). No Core/test changes.
- **Verified:** Windows-only → **Windows x64 CI green** (run 26845091836, build + publish) = compile-green. Core suite untouched → **179/179**. Combined `/code-review` + `/simplify` → **clean** (purely additive theme calls; `internal UiTheme` accessible from the `public` form, same assembly; styling a hidden button before the Click handler is order-independent and fine; AutoSize layout absorbs the larger heading font; no removed behaviour). **Visual + M2 (download + Retry still work) = laptop screenshot — trigger first-run or a model switch.**
- **Notes / decisions:**
  - **ProgressBar intentionally unstyled:** Win11 already renders the continuous bar in the system accent; there's no `UiTheme` helper for it and a behaviour-preserving restyle shouldn't owner-draw it. If it looks off vs mockup B in the screenshot, revisit then.

### Brick UI-3 — Restyle SettingsForm (2026-06-03)
- **What:** First *visible* brick of the modern-light restyle. The Settings window now wears `UiTheme`: light background + Segoe UI via `StyleWindow`, the hotkey `TextBox` and model `ComboBox` flattened via `StyleField`, and the four square checkboxes (Remove filler words / Show recording overlay / Start with Windows / Debug logging) replaced by the new `ToggleSwitch`. The old `MakeCheck` helper became `MakeToggle` (same signature). **All behaviour is unchanged** — the `_loading` guard, the four apply-and-save handlers, the `AutostartChanged` event, hotkey commit/rebind and model-switch wiring are preserved verbatim.
- **Files:** `SpeakType.App/Settings/SettingsForm.cs` (usings, `StyleWindow`/`StyleField`, layout `BackColor`, `MakeCheck`→`MakeToggle` + 4 call sites). No Core/test changes.
- **Verified:** Windows-only → **Windows x64 CI green** (run 26844849720, build + publish) = compile-green. Core suite untouched → **179/179**. `/code-review` → **no correctness bugs** (6 candidates all REFUTED): object-initializer ordering + `_loading` both prevent any spurious save on construction; `FlatStyle.Flat` doesn't change the `DropDownList` selection; `internal` `ToggleSwitch`/`UiTheme` are accessible from the `public` form (same assembly); the fixed-size toggle in an AutoSize cell won't clip. `/simplify` → 2 soft findings, neither applied (see notes). **Visual + M6 (settings still apply live) = laptop screenshot vs mockup B — first screenshot of the restyle, do this pass.**
- **Notes / decisions:**
  - **`/simplify` deferred, not skipped blindly:** (a) the layout's explicit `BackColor = UiTheme.Background` is technically redundant with `StyleWindow`'s ambient inheritance — **kept** as plan-specified (explicit beats relying on WinForms ambient-color quirks; zero cost). (b) the layout still hardcodes `Padding(12)` instead of `UiTheme.WindowPadding` (20px) and the rows don't use `RowGap` — that's a **visual spacing** change, deferred to the screenshot loop rather than blind-guessing pixels on a Mac that can't render WinForms. **If the first screenshot looks cramped vs mockup B, the fix is `Padding(12)`→`UiTheme.WindowPadding` (and widen `AddRow` margins toward `RowGap`).**
  - **Toggle rows are ~18px tall vs the old checkbox rows** — slightly shorter; expected from the restyle, validate in the screenshot.

### Brick UI-2 — ToggleSwitch control (2026-06-03)
- **What:** Second foundation brick of the modern-light restyle. Added `ToggleSwitch` — a small owner-drawn on/off switch (pill track + knob, painted via `UiTheme` colours: accent when on, grey `ToggleOff` when off, white knob) that replaces the square WinForms `CheckBox` in Settings. Exposes only the slice the forms use — `Checked` (bool) + `CheckedChanged` — and toggles on mouse click or Space/Enter. No animation (instant flip, per spec). **Not wired into any form yet** — that's UI-3.
- **Files:** `SpeakType.App/Controls/ToggleSwitch.cs` (new). No Core/test changes.
- **Verified:** Windows-only → **Windows x64 CI green** (run 26844485594, build + publish) = compile-green. Core suite untouched → **179/179**. `/simplify` → applied one nit (knob fill routed through `UiTheme.OnAccent` instead of a hardcoded `Color.White`, so a future dark-mode swap catches it; `OnAccent` *is* white → zero behaviour change). `/code-review` → found + **fixed one real correctness bug**: the focus ring was painted `if (Focused)` but nothing repainted on focus change, so the keyboard focus indicator never appeared/cleared on Tab — added `OnGotFocus`/`OnLostFocus` overrides that `Invalidate()`. **Visual + manual toggle behaviour: laptop screenshot/keyboard test comes with UI-3 (when it's first placed in a window).**
- **Notes / decisions:**
  - **Cosmetic knob-centering asymmetry deferred to the screenshot loop:** the off-state knob inset is 2px and the on-state is 1px (from the plan's exact pixels). Review flagged the slight asymmetry; rather than blind-guess pixel values on a Mac that can't render WinForms, this is left for the agreed laptop screenshot pass to tune against mockup B.
  - **Programmatic-set contract:** setting `Checked` raises `CheckedChanged`, but setting to the current value early-returns (no spurious fire); callers (SettingsForm in UI-3) set `Checked` before attaching the handler and gate with `_loading`, mirroring the old checkbox wiring.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
