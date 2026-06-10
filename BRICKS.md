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

_**windows/ phantom deletions — investigated & guarded (2026-06-10):** `windows/SpeakType.App` was repeatedly deleted from the **worktree** (never committed) during the user's manual Shelf drag-test rounds. Ruled out by direct testing: GitNexus hooks (`augment`/`analyze` leave the tree clean), `build-app.sh` from any cwd, the app's payload-delete path (App-Support-scoped), all project hooks (read-only), gitignore case-collisions, and parallel Claude sessions (transcripts show one lineage). Conclusion: a **Finder-side move during a drag gesture** (the panel is a small target that can slip away mid-drag; Finder spring-loading makes a fumbled release a silent move — and a landing inside the gitignored `SpeakTypeMac/SpeakType.app` bundle, case-insensitively the same name, is invisible to git and erased by the next build's `rm -rf`). **Guards now in place:** (1) `.claude/hooks/restore-windows-baseline.sh` (SessionStart + Stop) auto-restores any *unstaged* deletion under the baseline — verified against simulated damage; intentional staged `git rm` is respected. (2) Drag tests use `~/SpeakType-TestFiles/` (disposable samples), never repo files — noted in TESTING.md._

#### Shelf + Mirror — Sidekit launch features (queued 2026-06-09)

_The two missing launch features for the Sidekit pivot (vision: launch = SpeakType + Shelf + Mirror). Decision-resolved specs: `docs/superpowers/specs/2026-06-09-sidekit-shelf-design.md` and `...-sidekit-mirror-design.md` (both grilled with the user). Pure/testable core first, then adapters, then UI, then the drag-start spike, then polish. Mirror rides on the Shelf panel, so `SHELF-PANEL` must land before the Mirror bricks. Domain `Skill:` lines are `none` (no Swift skill, per §6); process skills (TDD, verification) apply; UI/drag/camera bricks verify manually on the Mac._

_**SHELF-DROP split (2026-06-10):** the original SHELF-DROP brick was over the §2a hard ceiling, so it was split. **SHELF-PAYLOAD** (the `ShelfPayloadStore` port + `FileSystemShelfPayloadStore` deletion + ShelfStore wiring) is **done** (see Done); the remaining four are below._

- [ ] **SHELF-DROP-EDGES** *(remainder is sandbox-gated)* — **(a) done 2026-06-10:** the vector/PDF-backed image drop (`pngData == nil`) now logs `image drop has no encodable bitmap representation — skipped` instead of vanishing silently (shipped with SHELF-POLISH). **(b) remains:** **security-scoped file URLs** — when the app is eventually **sandboxed** (Mac App Store / Sidekit), `copyItem` on a dropped file needs `startAccessingSecurityScopedResource()` / `stopAccessing…` or every file drop fails. Latent today (no App Sandbox entitlement) — do when sandboxing lands.
  - Skill: none (verification-before-completion)
- [ ] **SHELF-LATER** *(post-v1, parked with reasons — from SHELF-POLISH deferrals)* — cancel-mid-copy for huge folders (needs a custom cancellable recursive copier; `FileManager.copyItem` can't abort), tile-direct multi-drag (unify tap+drag in one AppKit layer per tile — only after hover-reveal is verified to survive an overlay), auto-summon on non-file drags (spec scopes the summon to *file* drags).
  - Skill: none
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

- [x] **SHELF-POLISH — self-drag highlight suppression + copy-in-flight indicator (2026-06-10).** The two real remaining polish items (slide animations and glass styling already shipped with the panel — Reduce-Motion-aware fade+rise in `ShelfPanel`, `glassCard` surface): **(1) Self-drag highlight off** — the panel no longer lights up "drop to shelve" while one of its *own* tiles/chips is dragged over it. The closure `.onDrop` became a **`ShelfDropDelegate` (DropDelegate)** whose `validateDrop` rejects marker-stamped drags (`ShelfDragMarker`) — macOS then never reports the drag as targeted, so the highlight can't ignite, and `performDrop` is never called (which is also what keeps preventing the self-drop duplicate; the perform-time guard moved up into validate). **(2) "Copying…" row** (spec §7 risk 2) — dropping a large folder used to be dead silence until the tile appeared; now `ShelfModel.copyingCount` tracks in-flight ingests (+1 on entry / −1 on exit, hopped to the main actor) and the panel shows a small spinner row ("Copying…" / "Copying N items…") in both the empty and filled states while bytes copy in. **Files:** `Sources/SpeakTypeApp/{ShelfView,ShelfModel}.swift` (~70 LOC). **Verified:** `swift build` clean (Swift 6), core **90/90**. **Manual (Mac) — pending user:** drag a tile out **over the panel** → no accent border flicker (drops from Finder still highlight); drop a multi-GB folder → spinner row shows until the tile appears, panel stays responsive. **Deferred (with reasons):** cancel-mid-copy (needs a custom cancellable recursive copier — `FileManager.copyItem` can't abort; rare case, post-v1), tile-direct multi-drag (only worth it once hover-reveal is verified to survive an AppKit overlay), non-file drag auto-summon (spec says *file* drags).
- [x] **SHELF-SETTINGS — shelf TTL + store-size in Settings, plus the full prune schedule (2026-06-10).** The Settings sheet gains a **Shelf** section: a **"Keep items for"** picker (**1 day / 2 days / 1 week / Never expire**, default 2 days — spec §4) and an **"On disk"** readout ("N items · X MB") with a **Clear all** button. Changing the TTL applies **immediately** (the live store re-prunes, so shortening the window deletes newly-expired items on the spot) and persists across launches. **Core (TDD'd):** `ShelfRetentionPolicy.ttl` is now **optional** — `nil` = "Never expire"; `pruneExpired` returns `[]` without persisting under a nil TTL (new test `pruneExpiredWithNeverTTLRemovesNothing`, red→green; suite now **90**). **Adapters/UI:** `SettingsModel` gains persisted `shelfTTLSeconds` (`"ShelfTTL"` key; **0 = never**) + an `applyShelfTTL` closure seeded at init like `applySettings`; `ShelfModel.setRetentionTTL(_:)` swaps the policy and prunes; `SettingsView` takes the live `ShelfModel` (observed, so the size readout updates as items come/go), threaded `AppController → MainWindow → sheet`. **Prune schedule completed (spec §4):** launch (already) + **on every shelf summon** (status-item click and drag-start auto-summon — expired items never visibly appear) + an **hourly main-actor `Task`** so TTL expiry deletes payload bytes even while the app idles in the menu bar for days. **Files:** `Sources/SpeakTypeCore/{ShelfRetentionPolicy,ShelfStore}.swift`, `Sources/SpeakTypeApp/{SettingsPanel,ShelfModel,MainWindow,App}.swift`, `Tests/SpeakTypeCoreTests/ShelfStoreTests.swift` (~70 source LOC; 6 files — slightly over the §2a 5-file soft guidance, accepted because MainWindow/App are 2-line pass-throughs). **Verified:** `swift build` clean (Swift 6), core **90/90** (new never-TTL test written first, failed, then passed). **Manual (Mac) — pending user:** ⚙︎ → Settings shows the Shelf section; pick **1 day** with a >1-day-old item staged → it disappears immediately and its bytes leave `~/Library/Application Support/`; "On disk" readout matches the shelf footer and updates on drop/remove; **Clear all** empties the shelf; pick **Never expire**, restart the app → old items survive launch. **Notes:** (1) TTL stored as seconds-Int; a value outside the four presets renders a blank picker (can't happen via UI). (2) The hourly sweep is a `Task.sleep` loop, not a `Timer` (Swift 6 sendability — Task inherits the main actor).
- [x] **SHELF-DRAGSTART — auto-summon the Shelf when a system file-drag starts (2026-06-10).** The spike **built clean** (no fragile hacks needed — spec §7 risk 1's defer path wasn't required): start dragging a file anywhere on the system and the Shelf **slides in near the cursor** as a drop target; when the drag ends somewhere else, it slips away again. Drops/hotkey summon unchanged. **How it detects drag-start** (macOS has no notification): new adapter **`ShelfDragStartMonitor`** mirrors `FnKeyMonitor`'s global+local `NSEvent` monitors on `.leftMouseDragged` and checks the **drag pasteboard's `changeCount`** on each event — a bump = a new drag session. Fires `onFileDragStart` once per session **iff** the session has `public.file-url` items and isn't shelf-born (`ShelfDragMarker` — our own tile/chip drags must not summon the panel they came from). `.leftMouseUp` → `onDragEnd`. **Panel behavior:** `ShelfPanel.showForDrag()` places the panel below-right of the cursor (clamped on-screen, multi-display aware) without touching the **remembered position** (`autoSummoned` placements skip `saveFrame` on hide); `dragEnded()` hides it unless the cursor is over the panel — in which case the drop landed/user engaged, and the panel becomes "theirs" (`autoSummoned` clears so a *later* drag ending elsewhere can't yank it mid-use). **Files:** `Sources/SpeakTypeApp/Adapters/ShelfDragStartMonitor.swift` (new), `Sources/SpeakTypeApp/{ShelfPanel,App}.swift` (~100 LOC). **Verified:** `swift build` clean (Swift 6), core **89/89** (AppKit glue, no pure logic). **Manual (Mac) — pending user:** drag a file in Finder → Shelf appears near the cursor mid-drag; drop it on the Shelf → it shelves and the panel stays; drag a file and drop it in a folder instead → the panel slips away; drag a **tile/chip out of the Shelf** → no self-summon; menu-bar summon still opens at the remembered position (auto-summons never overwrite it). **Notes:** (1) needs **Accessibility** (already required for Fn/paste) — without it the monitors are silent and only hotkey/menu summon works (spec's stated fallback). (2) Drag-end uses the `leftMouseUp` monitor; if macOS ever swallows that during a drag session, the panel would just stay open (benign) — revisit with a `pressedMouseButtons` poll only if seen. (3) Non-file drags (text/image selections) deliberately don't summon — spec says *file* drag; revisit post-v1 if it feels off.
- [x] **SHELF-DRAG-OUT-MULTI-B / SHELF-DRAG-OUT-MULTI-A / SHELF-ITEM-ACTIONS / SHELF-DRAG-OUT / SHELF-THUMBS / SHELF-DROP-IN / SHELF-PAYLOAD / SHELF-UI / SHELF-CORE-1 / WINDOW-BRAND / MENU-ANIM / OPEN-WINDOW / ICON-2 / ICON-1 / PASTE-HONEST — archived to `BRICKS-ARCHIVE.md`** (multi-item "Drag N out" chip incl. the ShelfDragMarker self-drop saga + tap-to-multi-select tiles + per-item ⋯ Copy/Reveal + Save-all + single-item drag-out + real QuickLook tile thumbnails + Shelf pure core + window dark-glass branding + menu-bar live waveform + clicking-opens-window + the two icon bricks + the paste-honesty fix; see archive for full detail).

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
