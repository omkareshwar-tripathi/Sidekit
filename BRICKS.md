# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Mac (Swift) — `feat/mac-app` branch

_Native Swift macOS dictation app (a deliberate **fork** — Windows stays C#, they evolve independently). Spec: `docs/superpowers/specs/2026-06-04-speaktype-mac-design.md`. Lives in `SpeakTypeMac/` (SwiftPM). Decisions: SwiftUI `MenuBarExtra`, WhisperKit (Neural Engine), hold-Fn (🌐) push-to-talk, SwiftPM + `build-app.sh`, local-dev ad-hoc-signed arm64. Ports-and-adapters with a pure tested `DictationCoordinator`. Domain `Skill:` lines are `none` (the `dotnet-*` skills don't apply to Swift, per CLAUDE.md §6); TDD + verification still apply._

### Next up (Mac)

- [ ] **MAC-2 — Pure core.** `DictationCoordinator` (port of C# `DictationOrchestrator`: press→record, release→cycle, 300 ms tap guard, 60 s auto-stop, release/auto-stop race) + `TranscriptCleaner` + `Settings`, with fake ports + full unit tests. No system frameworks. Verify: coordinator state-transition tests green. Skill: test-driven-development.
- [ ] **MAC-3 — Paste.** `MacPaste` adapter (`NSPasteboard` + `CGEvent` ⌘V) + clipboard-safe save→paste→restore sequence (sequence logic unit-tested against a fake pasteboard). Verify: unit tests green; manual paste into TextEdit. Skill: test-driven-development.
- [ ] **MAC-4 — Fn hotkey.** `FnKeyMonitor` (global `flagsChanged` on `.function`; abort if another key is pressed while Fn held). Verify: manual — menu shows recording while Fn held, stops on release. Skill: none.
- [ ] **MAC-5 — Audio.** `AVAudioCapture` (`AVAudioEngine`→16 kHz mono Float32 + RMS silence gate + mic permission). Verify: manual — mic prompt; speech → non-silent samples, silence gated. Skill: none.
- [ ] **MAC-6 — Whisper + wiring.** Add WhisperKit dep; `WhisperKitTranscriber` + composition root wiring the coordinator end-to-end + menu-bar status. Verify: manual — hold Fn, speak, release → text in TextEdit. Skill: none.
- [ ] **MAC-7 — Finalize permissions & docs.** `AXIsProcessTrusted` messaging, finalize Info.plist/entitlements, README/permissions doc; full manual end-to-end pass. Skill: verification-before-completion.

### Done (Mac)

- [x] **MAC-1 — Scaffold + bundle (2026-06-04).** Created the `SpeakTypeMac/` SwiftPM package: `SpeakTypeCore` library (`Ports.swift` — `AudioCapturing`/`HotkeyListening`/`Pasting`/`Transcribing` protocols + `CapturedAudio`/`PasteOutcome`/`DictationState` value types), `SpeakTypeApp` executable (`App.swift` — SwiftUI `MenuBarExtra` with a static mic icon + Quit), `Scripts/build-app.sh` (assembles + ad-hoc-signs `SpeakType.app` with `AppBundle/Info.plist`, `LSUIElement=true`), and `Tests/SpeakTypeCoreTests/PortsTests.swift` (4 Swift Testing tests on the value types). **Verified:** `swift build` clean; `swift test` 4/4 green; `build-app.sh` produces a `codesign --verify`-valid bundle with `LSUIElement=true`. **Manual check pending (user):** menu-bar icon visually appears on `open SpeakType.app`. **Notes:** WhisperKit dep deferred to MAC-6 to keep MAC-1 fast/offline; `Info.plist` already carries `NSMicrophoneUsageDescription` (used in MAC-5). Deployment target macOS 14.

---

## Windows (C#) — `main` line

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### App shell, UI & polish

_Modern-light UI restyle (Option 1, light-only). Spec: `docs/superpowers/specs/2026-06-03-ui-modern-light-restyle-design.md`; plan: `docs/superpowers/plans/2026-06-03-ui-modern-light-restyle.md`. All Windows-only → verify = CI compile-green + a laptop screenshot vs mockup B (no Core changes; 179 tests stay green)._

### Integration & ship

### Backlog (optional — needs a user decision, not in the v1 critical path)

- [ ] **Real installer (Start Menu + Desktop shortcut + uninstall) — deferred by user (2026-06-03).** Today SpeakType is a portable single exe: install = download `SpeakType.exe` from a CI artifact (Brick 18) and run it; first run adds a "Start with Windows" Run-key entry and lives in the tray, but creates **no** Start Menu/Desktop shortcut and has no uninstaller. User said they'll "work on installer later." Options when picked up: (a) lightweight — have the app create/remove a Start Menu + Desktop shortcut on first run / cleanup (small Windows-only brick, `IWshShortcut`/COM or a `.lnk` writer); (b) proper — an **MSI / Inno Setup / WiX** installer that handles shortcuts + uninstall + (eventually) code signing to kill the SmartScreen warning. Pairs naturally with a versioned GitHub **Release** (vs the current 90-day CI artifact). Windows-only.
  - Skill: dotnet-best-practices, run-tests


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

### Brick 18 — CI publishes a downloadable SpeakType.exe (2026-06-03)
- **What:** Made the app installable without a build. CI already published the self-contained single-file exe on every run but threw it away; added an `actions/upload-artifact@v4` step so each run attaches **`SpeakType-win-x64` → SpeakType.exe** to its "Artifacts" section. Installing is now: download the exe from a green run and double-click it — no .NET SDK, no Git, no local build. Updated the README with this download path.
- **Files:** `.github/workflows/ci.yml` (upload-artifact step); `README.md` (new "Download (no build)" section).
- **Verified:** Windows-only (CI) → **Windows x64 CI green** (run 26846751774) and the artifact is confirmed attached via the GitHub API: `SpeakType-win-x64`, **69,848,648 bytes (~66.6 MB)**, 90-day retention. Core suite untouched → **179/179**. Reviewed: YAML indentation matches sibling steps, `@v4` is current, `with:` schema valid (`name`/`path`/`if-no-files-found: error`), `path` matches the publish/verify exe path, step runs after publish so the file exists, and artifact upload is fine on PR runs too.
- **Notes / decisions:**
  - **Artifact, not a tagged Release:** every green run yields a downloadable exe (simplest, always-on) — no tagging step. A versioned GitHub **Release** (attach the exe on a `v*` tag) is the natural next step if/when we want stable, non-expiring download links.
  - **`if-no-files-found: error`** turns a silently-missing exe into a red run (defence-in-depth alongside the existing verify step, which still logs the size).
  - The exe is **unsigned** → SmartScreen "More info → Run anyway" still applies (code signing remains out of scope for v1).

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

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
