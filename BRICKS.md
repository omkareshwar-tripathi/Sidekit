# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Mac (Swift) — `feat/mac-app` branch

_Native Swift macOS dictation app (a deliberate **fork** — Windows stays C#, they evolve independently). Spec: `docs/superpowers/specs/2026-06-04-speaktype-mac-design.md`. Lives in `SpeakTypeMac/` (SwiftPM). Decisions: SwiftUI `MenuBarExtra`, WhisperKit (Neural Engine), hold-Fn (🌐) push-to-talk, SwiftPM + `build-app.sh`, local-dev ad-hoc-signed arm64. Ports-and-adapters with a pure tested `DictationCoordinator`. Domain `Skill:` lines are `none` (the `dotnet-*` skills don't apply to Swift, per CLAUDE.md §6); TDD + verification still apply._

### Next up (Mac)

_UI redesign — floating pill + scratchpad. Spec: `docs/superpowers/specs/2026-06-04-speaktype-mac-ui-redesign-design.md`. Pure/testable core first, then adapters, then UI, then polish. Domain `Skill:` lines are `none` (no Swift skill, per §6); process skills (TDD, verification) still apply. UI/animation bricks verify manually on the Mac._

_**UI redesign complete** — UI-1…UI-11 all shipped (floating pill + scratchpad). All remaining items are pending the user's manual visual pass on the signed `.app` (see each Done entry's "Manual (Mac)" note)._

_**Co-edit polish** (`feat/mac-app`) — round complete and user-re-tested: **TRAIL** (+clear-stale ✓), **HOLD-180**, **TESTDOCS**, **POLISH-UI**, **PASTE-HONEST** (all green; HOLD-180/TESTDOCS archived). Mac development continues on this branch toward launch (full `TESTING.md` major pass → notarize + DMG); `main` stays untouched until then._

_**Repo tidy (2026-06-07):** the old root .NET solution was parked under **`windows/`** on this branch with a **`windows/STATUS.md`** note — it's a pre-split baseline; the live Windows work is on branches `chore/windows-folder` + `feat/correction-pipeline`, to be resumed after the Mac launch (replicate Mac UX to parity + merge correction-pipeline). See the Windows section below._

#### Shelf + Mirror — Sidekit launch features (queued 2026-06-09)

_The two missing launch features for the Sidekit pivot (vision: launch = SpeakType + Shelf + Mirror). Decision-resolved specs: `docs/superpowers/specs/2026-06-09-sidekit-shelf-design.md` and `...-sidekit-mirror-design.md` (both grilled with the user). Pure/testable core first, then adapters, then UI, then the drag-start spike, then polish. Mirror rides on the Shelf panel, so `SHELF-PANEL` must land before the Mirror bricks. Domain `Skill:` lines are `none` (no Swift skill, per §6); process skills (TDD, verification) apply; UI/drag/camera bricks verify manually on the Mac._

- [ ] **SHELF-DROP** — drag files/text/images IN; multi-select drag OUT (no delete-on-drag); per-item copy / reveal-in-Finder. **Includes payload-byte copying** (`ShelfPayloadStore` port + `FileSystemShelfPayloadStore` adapter: copy dropped bytes into `Application Support/SpeakType/Shelf/<uuid>/`, delete on remove/expiry) — moved here from SHELF-STORE since bytes only arrive on a drop. **Also finishes the SHELF-UI deferrals** (now that bytes exist): real **QuickLook thumbnails / content previews** in the tiles, the footer **Save-all-to…** action, per-item **⋯** (copy / reveal-in-Finder), and **remove the SHELF-UI `#if DEBUG` sample seeder** (`ShelfModel.seedSamples()` + the header ＋ button). Must handle file-not-found gracefully for any pre-existing index entry whose bytes are missing. **← current** (App-layer — needs manual Mac verification)
  - Skill: none (verification-before-completion)
- [ ] **SHELF-DRAGSTART** *(spike → build or defer)* — auto-summon the panel on a system-wide file-drag start; if fragile, ship hotkey-summon for v1 and defer.
  - Skill: none (verification-before-completion)
- [ ] **SHELF-SETTINGS** — TTL configuration + store-size readout/management in Settings.
  - Skill: none (verification-before-completion)
- [ ] **SHELF-POLISH** — slide animations (Reduce-Motion aware), empty state, glass styling pass.
  - Skill: none (verification-before-completion)
- [ ] **MIRROR-CORE** — `MirrorState` (collapsed/small/expanded) + transitions + the "camera runs iff not collapsed" invariant; unit-tested.
  - Skill: none (TDD, verification-before-completion)
- [ ] **MIRROR-CAM** — `CameraPort` + `AVFoundationCamera` (start/stop, `isVideoMirrored`, device discovery); fake for tests.
  - Skill: none (verification-before-completion)
- [ ] **MIRROR-UI** — Mirror strip on the Shelf panel: button → small → expanded; first-open permission prompt; source picker when >1 camera.
  - Skill: none (verification-before-completion)
- [ ] **MIRROR-LIFECYCLE** — stop() wired to every exit (collapse, panel close, app deactivate); verify green light releases.
  - Skill: none (verification-before-completion)
- [ ] **MIRROR-POLISH** — size animation (Reduce-Motion aware), glass styling, denied/empty states.
  - Skill: none (verification-before-completion)

### Done (Mac)

- [x] **SHELF-UI — Shelf item grid + footer (2026-06-10).** Upgraded the placeholder list to a **`LazyVGrid` of `ShelfTile`s** (76×64 thumbnail area — kind glyph for now, QuickLook-ready — with the name beneath, middle-truncated) plus a **`ShelfFooter`** (item count + total store size via `ByteCountFormatter` over a new `ShelfModel.totalByteSize`, and **Clear all** moved here from the header). Hovering a tile reveals an inset **×** to remove it. **Deferred to SHELF-DROP (needs dropped bytes):** real QuickLook thumbnails/previews, footer **Save-all**, per-item **⋯** (copy / reveal). To make the grid verifiable before drag-in exists, added a **`#if DEBUG`-only** sample seeder (`ShelfModel.seedSamples()` + a header **＋** button) — release/notarized builds physically cannot contain it. **Files:** `Sources/SpeakTypeApp/{ShelfView,ShelfModel}.swift`. **Verified:** `swift build` clean, core **84/84**; `/simplify` (extracted tile-dim constants; wrapped seeder in `#if DEBUG`) and `/code-review` low (inset the hover-× so the grid can't clip it) both applied. **Manual (Mac) — pending user:** open Shelf → click header **＋** to seed 4 samples → grid renders 2-up glyph tiles + names; footer reads "4 items · ~7 MB"; hover a tile → inset × removes it; **Clear all** empties it. **Notes:** seeded samples are real index entries (persist to `shelf.json` across relaunch — Clear all to reset) with no bytes, so SHELF-DROP must tolerate file-not-found when wiring real thumbnails/Save-all.
- [x] **SHELF-PANEL — Summonable floating Shelf panel (2026-06-09).** The Shelf surface now exists and can be summoned. New `ShelfPanel` (App) — a borderless **non-activating** `NSPanel` (mirrors `PillPanel`: always-on-top, `.canJoinAllSpaces`, no focus-steal) but **interactive** and **summoned**: starts hidden, `toggle()/show()/hide()` from a new menu-bar **"Show Shelf"** item; `isMovableByWindowBackground` so the user drags it anywhere; frame persisted to `UserDefaults` (`shelf.panel.frame`) across show/hide/launch, first-run placed top-right. New `ShelfModel` (App, `@MainActor ObservableObject` over `ShelfStore`+`JSONShelfStore`, prunes expired on init, publish-then-mutate — mirrors `NotesModel`). New `ShelfView` (App, SwiftUI) — glass card (`glassCard()`), header, **Clear all**, empty state (`EqualizerMark` + "Drop files, text, or images here"), and a simple item list with per-row kind glyph + remove ×. `AppController` owns `shelf`/`shelfPanel` + `toggleShelf()`. **Files:** `Sources/SpeakTypeApp/{ShelfPanel,ShelfModel,ShelfView}.swift` (new), `App.swift` (own + wire + "Show Shelf" menu item). **Verified:** **`swift build` clean** (app links), **core suite 84/84**. **Manual (Mac) — pending user:** menu **Show Shelf** toggles the glass panel; it floats over other apps without stealing focus; drag it → position persists across hide/show + relaunch; empty state reads right. **Notes:** this brick is the panel + placeholder list; rich grid/thumbnails = SHELF-UI, drag-in/out + payload bytes = SHELF-DROP. Summon is menu-only for now — global hotkey + auto-on-drag are SHELF-DRAGSTART. Watch in manual test: `isMovableByWindowBackground` can fight SwiftUI hit-testing — if dragging the card is finicky, add an explicit drag handle.
  - **Fix round + SHELF-SUMMON (2026-06-09, from user manual test):** user found (a) panel wouldn't drag, (b) no close button; also asked for show/hide animation + a dedicated summon. Fixes: **drag** now via a `WindowDragHandle` `NSViewRepresentable` (`performDrag(with:)` on header mouse-down) replacing the SwiftUI-swallowed `isMovableByWindowBackground`; **× close** button in the header (calls `onClose` → `panel.hide()`); **animation** — fade + 8pt rise on show / fade on hide via `NSAnimationContext`, gated on `NSWorkspace…accessibilityDisplayShouldReduceMotion`. **SHELF-SUMMON:** a dedicated **Shelf menu-bar icon** (`ShelfStatusItem`, an `NSStatusItem` with a `tray.full` template glyph) whose **click toggles the panel directly**; removed the now-redundant "Show Shelf" item from the SpeakType dropdown. **Files:** `Sources/SpeakTypeApp/{ShelfView,ShelfPanel}.swift` (drag/close/anim), `Sources/SpeakTypeApp/ShelfStatusItem.swift` (new), `App.swift` (own `shelfStatusItem`, remove menu item). **Verified:** `swift build` clean, core **84/84**. **Manual (Mac) — pending user re-test:** drag panel by its header; × closes; fade+rise animation (and none under Reduce Motion); a tray icon appears in the menu bar and one click shows/hides the shelf. (Hover-to-show deferred — user chose click-toggle for v1.)
  - **SHELF-HOVER removed (2026-06-09, user decision):** hover-to-reveal was tried (tray-icon `NSTrackingArea`, panel SwiftUI `.onHover`, and a pinned/grace-timer state machine in `AppController`) but never worked reliably inside the non-activating panel — the shelf collapsed while the mouse was genuinely over it. Per the user (*"still not working, let's forget about it"*) the feature was **dropped** and summon reverted to plain **click-toggle**: the tray-icon click calls `shelfPanel.toggle()`, the × calls `hide()`. Removed all hover code — `ShelfStatusItem` (`onHoverEnter/Exit` + tracking area + `mouseEntered/Exited` + debug logs), `ShelfView` (`onHover` prop + `.onHover`/`.contentShape`), `ShelfPanel` (`onHover` param + `[shelf-hover]` logs), and `App.swift` (`shelfPinned`/`shelfCloseWork`, `clickShelfIcon`/`hoverOpenShelf`/`shelfPanelHover`/`scheduleShelfClose`/`cancelShelfClose`/`closeShelf` — collapsed to inline `toggle()`/`hide()` closures). **Verified:** `swift build` clean, core **84/84**. The earlier drag/×/animation fixes and the `ShelfStatusItem` click-summon below all remain.
- [x] **SHELF-STORE — Shelf index persistence: `ShelfCodec` + `JSONShelfStore` (2026-06-09).** Persists the Shelf's item index across quit/reboot (spec §8). Followed the codebase's `NotesCodec`/`JSONNotesStore` split: **`ShelfCodec`** (pure Core, **unit-tested**) does the `[ShelfItem]` ⇄ JSON mapping (pretty/sorted-keys; tolerant decode — corrupt/empty → `[]` so a bad file degrades to "start fresh"); **`JSONShelfStore`** (App adapter, build-verified) implements `ShelfPersisting` over `~/Library/Application Support/SpeakType/shelf.json` with an immediate atomic write + one retry (no debounce — shelf mutations are infrequent, unlike per-keystroke notes) and tolerant load via `Diag`. **Re-scope:** the planned `FileSystemShelfPayloadStore` (copying the actual payload *bytes*) moved to **SHELF-DROP**, since bytes only arrive on a drop; this brick is index-only. **Files:** `Sources/SpeakTypeCore/ShelfCodec.swift` (new), `Sources/SpeakTypeApp/Adapters/JSONShelfStore.swift` (new), `Tests/SpeakTypeCoreTests/ShelfCodecTests.swift` (new, 4 tests). **Verified:** TDD on the codec (RED `ShelfCodec` missing → GREEN); **core suite 84/84** (+4); **`swift build` clean** (adapter compiles). **Manual (Mac) — pending user:** drop items, quit + relaunch → shelf restores; corrupt `shelf.json` → starts empty (logged). **Notes:** shelf.json sits beside notes.json/history.json under the **SpeakType** support dir (not the spec's `Sidekit/`) — all three move together at the Sidekit rebrand; the app isn't renamed yet.
- [x] **SHELF-CORE-1 / WINDOW-BRAND / MENU-ANIM / OPEN-WINDOW / ICON-2 / ICON-1 / PASTE-HONEST — archived to `BRICKS-ARCHIVE.md`** (Shelf pure core + window dark-glass branding + menu-bar live waveform + clicking-opens-window + the two icon bricks + the paste-honesty fix; see archive for full detail).

_(Older Mac Done entries — POLISH-UI, TRAIL, HOLD-180, TESTDOCS, UI-1…UI-11, MAC-*… — archived to `BRICKS-ARCHIVE.md`.)_

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
