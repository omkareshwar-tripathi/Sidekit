# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### Fix & Polish pipeline

_Sub-project 0 (correction spine + SymSpell) **shipped** — bricks 0a–0d. Spec: `docs/superpowers/specs/2026-06-03-fix-polish-correction-pipeline-design.md`; plan: `docs/superpowers/plans/2026-06-03-fix-polish-correction-pipeline.md`. The spec records the full decomposition + user decisions (full 4-stage scope; **bundle** models in the exe; SymSpell on-but-conservative). **Next: sub-project 1 — ONNX Runtime foundation** (ONNX Runtime + a shared tokenizer/inference helper + embedded-model packaging), then stage 2 Punctuation, stage 3 GECToR, stage 4 CoEdIT Polish (seq2seq + "Polish" button). Each sub-project gets its own brainstorm → spec → plan. Heads-up: the "bundle in exe" choice will stress exe size at the CoEdIT stage — revisit delivery then._
  - Skill: brainstorming (each new sub-project), dotnet-best-practices, dotnet-xunit, run-tests

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

### Brick 0d — Settings "Spelling correction" toggle (2026-06-03)
- **What:** Added a "Spelling correction" toggle to the Settings window (grouped under "Remove filler words"), bound to `AppSettings.SpellCorrection` (default on). Lets the user turn the SymSpell stage off; persists via the shared `MakeToggle`/`_store.Save` path like the other toggles.
- **Files:** `SpeakType.App/Settings/SettingsForm.cs` (1 line). No Core/test changes.
- **Verified:** Windows-only → can't compile on the Mac host (WinForms SDK); **verify = CI compile-green + manual** (open Settings, toggle shows default-ON, flip it → `%APPDATA%\SpeakType\settings.json` gains `"spellCorrection": false/true`; dictate a typo-prone word → correction applies only when ON). Read-only spec+quality review: clean — matches the `FillerRemoval` row exactly; `_loading` guard prevents a spurious save on construction.
- **Notes:** Last brick of correction sub-project 0. **Pending: push so Windows CI compiles `Program.cs` + `SettingsForm.cs` (neither builds on Mac).**

### Brick 0c — Correction pipeline wired into orchestrator (2026-06-03)
- **What:** Inserted the correction pipeline into the dictation flow between `TranscriptCleaner.Clean` and paste (Whisper → clean → **correct** → paste). Orchestrator gained a trailing-optional `TextCorrectionPipeline? correctionPipeline = null` (null ⇒ passthrough, so existing tests are untouched); `ProcessRecording` computes `corrected` after the empty-check and uses it for both the transcript log and paste. Composition root (`Program.cs`) builds the real pipeline = `[SymSpellCorrector gated on s => s.SpellCorrection]`.
- **Files:** `SpeakType.Core/Orchestration/DictationOrchestrator.cs`; `SpeakType.App/Program.cs`; `SpeakType.Tests/Orchestration/DictationOrchestratorTests.cs` (2 integration tests + `UpperCorrector` fake, isolated with fresh fakes).
- **Verified:** Core → **195/195** (2 new). App Windows-only (CI compile pending). Spec review ✓; quality review ✓ — fixed a shared-fake double-subscription test hazard the review caught.
- **Notes:** Gate reads the live `AppSettings`, so the Settings toggle applies on the next dictation, no restart. `_logger?.Transcribed(…, cleaned.Length)` deliberately left on the pre-correction length.

### Brick 0b — Conservative SymSpellCorrector stage (2026-06-03)
- **What:** First concrete `ITextCorrector`: conservative SymSpell spelling correction. Token-by-token via `[A-Za-z]+` regex (preserves punctuation + the cleaner's trailing space). Skips tokens ≤2 chars, any non-all-lowercase token (protects Names/ACRONYMS/MixedCase/jargon), and known words (edit-distance 0); for unknown lowercase words, looks up at edit-distance 1 and only replaces when the suggestion clears a frequency floor (1,000,000). Fail-open (errors return input unchanged); fail-fast if the dict can't load.
- **Files:** `SpeakType.Core/Correction/SymSpellCorrector.cs`; embedded `frequency_dictionary_en_82_765.txt` (~1.3 MB, MIT); `SpeakType.Core/SpeakType.Core.csproj` (SymSpell **6.7.3** PackageReference + EmbeddedResource w/ `LogicalName`); `SpeakType.Tests/Correction/SymSpellCorrectorTests.cs` (9 tests, shared via `IClassFixture`).
- **Verified:** Core → **193/193** at brick end. Spec + quality review ✓.
- **Notes:** **First NuGet dependency in Core** (was dependency-free) — deliberate (spec §3): deterministic algorithm, keeps the stage Mac/CI-testable. API note: it's `LoadDictionary(Stream,0,1)` — the plan's `LoadDictionaryStream` name doesn't exist in 6.7.3. Dict is **bundled/embedded** per the user's delivery choice.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
