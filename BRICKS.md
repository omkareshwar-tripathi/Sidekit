# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### CoEdIT Polish

_On-device text improvement: CoEdIT (Flan-T5-large) runs **automatically on every dictation** before paste (toggle, default-on), fail-open. Replaces the abandoned 4-stage "Fix & Polish" — we dropped Punctuation/GECToR/SymSpell as redundant-with-Whisper. Spec: `docs/superpowers/specs/2026-06-03-coedit-polish-design.md` (records all decisions + the CE-1→CE-4 decomposition + the tokenizer finding). **CE-1 (tokenizer) + CE-2 (inference engine) shipped.**_

- **Next: CE-3 — model acquisition.** Download + unpack the coedit-large ONNX archive on first run, reusing the existing `IModelDownloader`/`ModelStore` plumbing (single-archive → extract; the current store is single-file, so extend it or add a small sibling). Then build the **real** `OnnxCoEditModel : ICoEditModel` (two ONNX Runtime sessions: encoder + merged decoder w/ KV cache) — this is where the int64 `input_ids` / "Int64 vs Float" tensor-dtype gotchas live; use Optimum's **merged decoder**. Then CE-4 (orchestrator wiring + `CoEditPolishing` setting + Settings toggle + logging, Windows-verified). **CE-3 needs the real exported model** — the export tooling is **now in place** (see below); run it, then paste the printed `size` + `sha256` into the CE-3 model catalog.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
- **Model export tooling shipped (not a brick — external, no app dep):** `scripts/export_coedit_onnx.py` (+ `scripts/requirements-export.txt`) converts `grammarly/coedit-large` → int8 ONNX zip (encoder + merged decoder), prints SHA256 + size. Run it via the **`Export CoEdIT model`** GitHub Actions workflow (`.github/workflows/export-coedit-model.yml`, manual `workflow_dispatch`): leave `release_tag` blank for a 90-day artifact, or set it (e.g. `coedit-large-v1`) to publish a **GitHub Release** → stable download URL `…/releases/download/<tag>/coedit-large-int8.zip` for the catalog. Syntax-validated on Mac; **first real run happens on GH Actions** (no torch here) — expect to tweak dep pins / disk if the first run errors. **Quality caveat:** int8 dynamic quantization of T5 is unproven for this model — verify output quality in CE-3; fall back to fp16/selective quant if poor.
- **Seam already in place:** `SpeakType.Onnx/Inference/ICoEditModel.cs` — `Encode(sourceIds) → IEncoderOutput` (run once) + `DecodeNextLogits(encoderOutput, decodedSoFar) → float[] logits` (per token). `CoEditPolisher` (the greedy loop) consumes it; CE-3 just supplies the real ONNX-backed implementation. `decoder_start_token_id=0`, `eos_token_id=1`, vocab 32100.

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

### Brick CE-2 — CoEdIT inference engine (greedy decode loop) (2026-06-03)
- **What:** The engine that turns text into polished text. `CoEditPolisher : ITextPolisher` tokenizes `instruction + text` (default `"Fix the grammar: "`), runs the encoder once, greedily decodes one token at a time (argmax → append) until EOS or a safety cap, then detokenizes. All ONNX/tensor/KV-cache work is hidden behind the `ICoEditModel` seam, so the loop is **pure, fully-tested logic** — the real 800 MB model isn't needed to prove it correct.
- **Files:** `SpeakType.Core/Polishing/ITextPolisher.cs` (port); `SpeakType.Onnx/Inference/ICoEditModel.cs` (seam + `IEncoderOutput` opaque handle); `SpeakType.Onnx/Inference/CoEditPolisher.cs` (engine); `SpeakType.Onnx.Tests/Inference/CoEditPolisherTests.cs` (6 tests w/ a scripted `FakeModel` + the real tokenizer for detokenization).
- **Verified:** `SpeakType.Onnx.Tests` **19/19** (13 + 6) on macOS — covers: scripted tokens → exact text, instruction-prefix applied, encoder-runs-once, stop-at-EOS, runaway cap, null guard. Core **179/179** unchanged; Core/Onnx build.
- **Notes / decisions:**
  - **Seam named `ICoEditModel`, not the plan's `IOnnxSession`** — it abstracts the *model* (`Encode` / `DecodeNextLogits`), not a raw ORT session. The real ONNX two-session + KV-cache impl (`OnnxCoEditModel`) is **CE-3**.
  - **Fail-open is deferred to CE-4** (orchestrator wraps `Polish` in try/catch → paste raw text). The engine itself only guards null input.
  - **CE-4 spacing watch:** `TranscriptCleaner` adds a trailing space; the model output won't have it. Decide in CE-4 whether to polish before/after the trailing-space step and re-add it for paste.

### Brick CE-1 — SpeakType.Onnx project + CoEditTokenizer (2026-06-03)
- **What:** First brick of the CoEdIT Polish feature. New **cross-platform** `SpeakType.Onnx` project (net8.0, builds/tests on Mac+CI, unlike the WinForms App) holding `CoEditTokenizer` — encode text → T5 token ids (EOS appended) / decode ids → text (special tokens stripped) for the Flan-T5 CoEdIT model. Bundles `assets/tokenizer.json` (~2.4 MB). De-risks the feature's #1 unknown: correct T5 tokenization in C#.
- **Files:** `SpeakType.Onnx/SpeakType.Onnx.csproj`, `SpeakType.Onnx/Tokenization/CoEditTokenizer.cs`, `SpeakType.Onnx/assets/tokenizer.json`; `SpeakType.Onnx.Tests/SpeakType.Onnx.Tests.csproj` + `Tokenization/CoEditTokenizerTests.cs` (13 tests); `SpeakType.sln` (2 projects added).
- **Verified:** `SpeakType.Onnx.Tests` **13/13** on macOS (5 golden vectors from the reference HF `tokenizers` lib, encode + round-trip + EOS + guards). Core **179/179** unchanged; Core/Whisper/Onnx all build.
- **Notes / decisions:**
  - **Tokenizer library = `Tokenizers.DotNet` 1.4.1, NOT `Microsoft.ML.Tokenizers`** (the design's assumption). MS.ML.Tokenizers **crashes** (`IndexOutOfRangeException`) loading the T5 Unigram `spiece.model` on both 2.0.0 and 3.0.0-preview; onnxruntime-extensions supports it but ships **Windows-only** natives. `Tokenizers.DotNet` wraps the HF Rust tokenizer, loads `tokenizer.json` directly, ships osx/win/linux natives → cross-platform + exact-correct (matches reference ids). Native dep, but portable like `Whisper.net.Runtime`.
  - Golden vectors are generated from a Python venv (`pip install tokenizers`) — regenerate the same way if the tokenizer asset changes.
  - Built on a **fresh branch `feat/coedit-polish` off `main`** (not stacked on the abandoned SymSpell PR #1).

### Brick 18 — CI publishes a downloadable SpeakType.exe (2026-06-03)
- **What:** Made the app installable without a build. CI already published the self-contained single-file exe on every run but threw it away; added an `actions/upload-artifact@v4` step so each run attaches **`SpeakType-win-x64` → SpeakType.exe** to its "Artifacts" section. Installing is now: download the exe from a green run and double-click it — no .NET SDK, no Git, no local build. Updated the README with this download path.
- **Files:** `.github/workflows/ci.yml` (upload-artifact step); `README.md` (new "Download (no build)" section).
- **Verified:** Windows-only (CI) → **Windows x64 CI green** (run 26846751774) and the artifact is confirmed attached via the GitHub API: `SpeakType-win-x64`, **69,848,648 bytes (~66.6 MB)**, 90-day retention. Core suite untouched → **179/179**. Reviewed: YAML indentation matches sibling steps, `@v4` is current, `with:` schema valid (`name`/`path`/`if-no-files-found: error`), `path` matches the publish/verify exe path, step runs after publish so the file exists, and artifact upload is fine on PR runs too.
- **Notes / decisions:**
  - **Artifact, not a tagged Release:** every green run yields a downloadable exe (simplest, always-on) — no tagging step. A versioned GitHub **Release** (attach the exe on a `v*` tag) is the natural next step if/when we want stable, non-expiring download links.
  - **`if-no-files-found: error`** turns a silently-missing exe into a red run (defence-in-depth alongside the existing verify step, which still logs the size).
  - The exe is **unsigned** → SmartScreen "More info → Run anyway" still applies (code signing remains out of scope for v1).

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
