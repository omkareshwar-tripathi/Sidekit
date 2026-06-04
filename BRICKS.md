# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Mac (Swift) — `feat/mac-app` branch

_Native Swift macOS dictation app (a deliberate **fork** — Windows stays C#, they evolve independently). Spec: `docs/superpowers/specs/2026-06-04-speaktype-mac-design.md`. Lives in `SpeakTypeMac/` (SwiftPM). Decisions: SwiftUI `MenuBarExtra`, WhisperKit (Neural Engine), hold-Fn (🌐) push-to-talk, SwiftPM + `build-app.sh`, local-dev ad-hoc-signed arm64. Ports-and-adapters with a pure tested `DictationCoordinator`. Domain `Skill:` lines are `none` (the `dotnet-*` skills don't apply to Swift, per CLAUDE.md §6); TDD + verification still apply._

### Next up (Mac)

_UI redesign — floating pill + scratchpad. Spec: `docs/superpowers/specs/2026-06-04-speaktype-mac-ui-redesign-design.md`. Pure/testable core first, then adapters, then UI, then polish. Domain `Skill:` lines are `none` (no Swift skill, per §6); process skills (TDD, verification) still apply. UI/animation bricks verify manually on the Mac._

- [ ] **UI-8 — Main window shell.** Sidebar notes list + editor pane, glass styling, selection/cross-fade. Reads `NotesStore`. **Also add debounced/coalesced saves + flush-on-quit to `JSONNotesStore`** (deferred from UI-3 — the per-keystroke editor is the first high-frequency writer, and debounce without a quit-flush would lose the last edit; build them together).
  - Skill: none (Swift) · emil-design-eng (review)
- [ ] **UI-9 — Route dictation into the focused note.** `RoutingSink`: frontmost-app check (injected closure) → append to active note (create one if none) else paste-at-cursor. In-app dictation end-to-end.
  - Skill: none (Swift) · TDD for routing
- [ ] **UI-10 — Settings + note management.** Filler-removal toggle, launch-at-login, mic/Accessibility status; new/delete note.
  - Skill: none (Swift)
- [ ] **UI-11 — Polish pass.** Window transitions, transcript reveal animation, empty states; final review.
  - Skill: none (Swift) · emil-design-eng (review)

### Done (Mac)

- [x] **UI-7 — Pill animations (2026-06-04).** The pill now moves (spec §2.2), all in one file (`PillView.swift`). **Idle:** the faint bar slowly **breathes** (eased scale+opacity, `repeatForever`). **Morphs:** state→state transitions animate with a **spring** (`.spring(response: 0.35, dampingFraction: 0.72)`) keyed on a now-`Equatable` `PillState`; recording springs open (`.scale`+`.opacity`), transcribing fades, success **pops** (`.scale(0.6)`+`.opacity`). **Recording waveform:** bar heights **glide** (`.easeOut(0.12)`, value: level) instead of jumping. **Transcribing:** a small `ProgressView` spinner replaces the static glyph. **Success hold/collapse (deferred from UI-5):** entering an outcome shows the pill, holds **1.2 s**, then collapses to the idle bar — driven by a `showSuccess` `@State` flipped by an `onChange(of: state)` handler; the collapse uses a **cancellable `Task`** (a new dictation cancels a pending collapse, so it never reverts mid-cycle). **Reduce Motion (spec §9):** `@Environment(\.accessibilityReduceMotion)` swaps every spring/morph/breathe for a plain `easeInOut(0.2)` fade or `nil` — feedback is never removed, only de-animated. **Files:** `Sources/SpeakTypeApp/PillView.swift` (rewritten — `PillState: Equatable`, animation layer, `WaveformBars(level:reduceMotion:)`). **Verified:** `swift build` clean, `swift test` **55/55** (core untouched). **Manual (Mac) — pending user:** hold Fn → pill springs open with a live waveform; release → spinner; done → ✓ pops, holds ~1.2 s, collapses to the breathing dot. Toggle System Settings → Accessibility → Display → **Reduce Motion** and confirm the springs become gentle fades. (Note: the `ProgressView` spinner still spins under Reduce Motion — system behavior; acceptable as retained feedback.)
- [x] **UI-6 — Live audio metering → waveform level (2026-06-04).** The pill's waveform now reacts to the real mic. **Core (TDD):** `AudioMath.level(_:reference:) -> Float` — the buffer's peak normalized against a new `loudPeak = 0.3` reference and clamped to 0…1 (shares the peak basis with `hasSpeech`; normal speech peaks well below 1.0, so a 1.0 reference would barely move the bars). **Adapter (additive):** `AVAudioCapture` gained an `onLevel: (@MainActor (Float) -> Void)?` emitted once per converted tap buffer (~11×/sec) — peak of that buffer, hopped to the main actor via `Task { @MainActor in … }`. The accumulate/silence-gate/`stop()` paths are untouched (the level is computed from the same `frameSamples` array already being appended). **Wiring:** `AppController` republishes it as `@Published private(set) var level` (wired in the post-init closure block where `self` is fully initialized), reset to 0 whenever state leaves `.recording`. `PillView`'s `WaveformBars(level:)` scales a fixed bar silhouette by the level (0.2 floor so bars stay visible at silence). **Files:** `Sources/SpeakTypeCore/AudioMath.swift` (+`loudPeak`, +`level`), `Sources/SpeakTypeApp/Adapters/AVAudioCapture.swift` (+`onLevel`), `App.swift` (+`level` published + wiring + reset), `PillView.swift` (`WaveformBars` level-driven); tests `AudioMathTests.swift` (+5: empty→0, reference→1, half→0.5, clamp, peak-not-average). **Verified:** `swift test` **55/55** (+5); `swift build` clean. **Manual (Mac) — pending user:** while holding Fn, the pill's bars rise/fall with your voice and settle flat when recording ends. (Per-bar smoothing/animation is UI-7.)
- [x] **UI-5 — Pill panel (states, no animation) (2026-06-04).** The always-present floating recording pill (spec §2.2). **`PillPanel.swift` (new):** an AppKit `NSPanel` — `[.borderless, .nonactivatingPanel]`, `.floating` level, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, clear/`isOpaque=false`/`hasShadow=false` (the glass card draws its own shadow), `ignoresMouseEvents=true` (informational, click-through), `orderFrontRegardless()` so it shows without stealing focus — pinned to the **bottom-center** of `NSScreen.main.visibleFrame` (24pt above the Dock). Hosts the SwiftUI `PillView` via `NSHostingView`. **`PillView.swift` (new):** an `@ObservedObject` on `AppController` that maps `(DictationState, lastOutcome)` → a `PillState` and renders it **statically** — idle = a bare dim bar (auto-dimmed); recording = red dot + static `WaveformBars` + "Listening…"; transcribing = waveform glyph + "Transcribing…"; done = ✓/glyph + outcome ("Pasted"/"Added to note"/"On clipboard"/"No speech"), all in the glass capsule (`glassCard(cornerRadius: .pill)`). **Wiring:** `AppController` retains a `PillPanel`, created at the end of `init` (all stored props set) binding to `self`. **Deferred:** live waveform amplitude → UI-6; spring morphs + the ~1.2 s success-hold-then-collapse-to-idle timing → UI-7; click-pill-to-open-window → window-interaction brick (needs `openWindow`, absent from an AppKit-hosted view's environment). **Files:** `Sources/SpeakTypeApp/PillPanel.swift` (new), `PillView.swift` (new), `App.swift` (+`pill` property, created in `init`). **Verified:** `swift build` clean, `swift test` **50/50** (core untouched). **Manual (Mac) — pending user:** pill sits bottom-center on all Spaces, never takes focus; the dim idle bar expands to the right glass look for each state as you hold Fn / it transcribes / completes (states are static here — the success pill persists until the next dictation; auto-collapse is UI-7).

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
