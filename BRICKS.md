# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

_Modern-light UI restyle (Option 1, light-only). Spec: `docs/superpowers/specs/2026-06-03-ui-modern-light-restyle-design.md`; plan: `docs/superpowers/plans/2026-06-03-ui-modern-light-restyle.md`. All Windows-only → verify = CI compile-green + a laptop screenshot vs mockup B (no Core changes; 179 tests stay green)._

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

### Brick UI-6 — App logo (waveform mark) (2026-06-03)
- **What:** Gave SpeakType a real logo (user request; concept **C** — a white equalizer/waveform on an accent-blue rounded tile). New `AppIcon` brand helper + a multi-size `Assets/speaktype.ico` (16–256px). The icon now appears as: the **.exe icon** (`<ApplicationIcon>`), the **Settings & Welcome window title bars / taskbar / Alt-Tab** (`Icon = AppIcon.Brand`, loaded from the embedded ico), and the **tray icon** — which keeps its per-state colour signal by drawing the *same waveform glyph* tinted blue/red/orange/dark-red (`AppIcon.ForState`) instead of the old plain circles.
- **Files:** `SpeakType.App/Assets/speaktype.ico` (new asset); `SpeakType.App/Branding/AppIcon.cs` (new — `Brand` + `ForState`, plus the GetHicon/DestroyIcon idiom moved here from TrayIcon); `SpeakType.App/SpeakType.App.csproj` (`ApplicationIcon` + embedded resource w/ `LogicalName`); `SpeakType.App/Tray/TrayIcon.cs` (use `ForState`, removed `MakeIcon`/`DestroyIcon`/`partial`); `SpeakType.App/Settings/SettingsForm.cs` + `SpeakType.App/Startup/WelcomeForm.cs` (`Icon = AppIcon.Brand`). No Core/test changes.
- **Verified:** Windows-only → **Windows x64 CI green** (run 26846172886) — incl. the publish step, which proves `<ApplicationIcon>` resolved and the exe built with the icon. Core suite untouched → **179/179**. `/code-review` → **all 8 risks REFUTED** (key one: WinForms `Form` does NOT dispose an assigned `Icon` — only its own derived small icon — so the shared process-lifetime `Brand` is safe across the repeatedly-created Welcome window; `LogicalName` makes `GetManifestResourceStream("speaktype.ico")` resolve; `partial`/using removals compile clean; HICON cleanup leak-free). `/simplify` → applied 2 nits (reworded an overstated comment; `FillRoundedBar` de-extension-methodised). **Visual = laptop: check the exe icon in Explorer, the window title-bar/taskbar icon, and the tray glyph colour per state — screenshot if anything's off.**
- **Notes / decisions:**
  - **The `.ico` is the single brand source** (exe + windows load it); only the **tray** is drawn programmatically, because it needs runtime per-state tinting (a static asset can't recolour). The tray glyph's bar proportions are hand-matched to the .ico.
  - **`AppIcon.Brand` is shared & never disposed** (process-lifetime, like the `UiTheme` fonts) — safe because Form doesn't own/dispose an assigned Icon.
  - **Tooling:** the `.ico` was generated on the Mac with Python/Pillow (no ImageMagick needed); regenerate via the same waveform proportions if the mark is revised.

### Brick UI-5 — Flat tray menu (2026-06-03)
- **What:** Final brick of the modern-light restyle. The tray right-click `ContextMenuStrip` now uses a `ToolStripProfessionalRenderer` backed by `FlatMenuColorTable` plus light font/colours (`UiTheme.Body`/`TextPrimary`/`Surface`, `RoundedEdges = false`) — a flat white menu with accent hover and a thin grey separator, replacing the legacy gray-gradient chrome. Menu items, the separator, checkmarks (Pause / Start with Windows) and **all Click wiring are unchanged**.
- **Files:** `SpeakType.App/Tray/TrayIcon.cs` (using + 4 lines in `BuildMenu`). No Core/test changes.
- **Verified:** Windows-only → **Windows x64 CI green** (run 26845342026, build + publish) = compile-green. Core suite untouched → **179/179**. Combined `/code-review` + `/simplify` → **clean**: `RoundedEdges` is a valid property; subclassing only the colour table leaves checkmark rendering intact; the renderer + `FlatMenuColorTable` aren't `IDisposable` and hold no unmanaged handles → no leak, nothing to dispose; behaviour-preserving. **Visual + menu actions = laptop screenshot (right-click the tray icon).**
- **Notes / decisions:**
  - **Tray *icon* glyphs unchanged** — the four state circles (SteelBlue/Red/Orange/DarkRed via `MakeIcon`) still convey Idle/Recording/Busy/Error; only the *menu* chrome changed. (A logo for the icon itself is the separate Brick UI-6.)

### Brick UI-4 — Restyle WelcomeForm (2026-06-03)
- **What:** Restyled the model-download / first-run Welcome window (also reused for a mid-session model switch) to the modern-light look: light background + Segoe UI via `StyleWindow`, a **Segoe UI Semibold heading**, **muted (TextSecondary) status text**, and the **Retry button as a primary accent button** via `StyleButton`. The system `ProgressBar` is left as-is (already accent-coloured on Win11). **Behaviour unchanged** — the async download, the `_downloading` re-entrancy guard, Retry, and cancel-on-close are untouched.
- **Files:** `SpeakType.App/Startup/WelcomeForm.cs` (using + `StyleWindow` + heading font + status colour + `StyleButton(_retry)`). No Core/test changes.
- **Verified:** Windows-only → **Windows x64 CI green** (run 26845091836, build + publish) = compile-green. Core suite untouched → **179/179**. Combined `/code-review` + `/simplify` → **clean** (purely additive theme calls; `internal UiTheme` accessible from the `public` form, same assembly; styling a hidden button before the Click handler is order-independent and fine; AutoSize layout absorbs the larger heading font; no removed behaviour). **Visual + M2 (download + Retry still work) = laptop screenshot — trigger first-run or a model switch.**
- **Notes / decisions:**
  - **ProgressBar intentionally unstyled:** Win11 already renders the continuous bar in the system accent; there's no `UiTheme` helper for it and a behaviour-preserving restyle shouldn't owner-draw it. If it looks off vs mockup B in the screenshot, revisit then.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
