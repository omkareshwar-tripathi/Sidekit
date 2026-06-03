# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### CoEdIT Polish

_On-device text improvement: CoEdIT (Flan-T5-large) polishes each dictation before paste. **PIVOT (2026-06-04): CoEdIT is now OPT-IN, off by default** — its ~2.4 GB model downloads only when the user enables "Improve text (CoEdIT)" in Settings, so the app launches/dictates with no large download (the old required-on-first-run gate was crashing on the user's laptop). Fail-open everywhere. Spec: `docs/superpowers/specs/2026-06-03-coedit-polish-design.md`. **CE-1..CE-4f shipped** (tokenizer → engine → real ONNX inference → app wiring → single-file packaging: 76.8 MB compressed exe, Windows CI green on PR #4). **CE-5a (off-by-default + SwappableTextPolisher) + CE-5b (download-on-enable, fatal gate removed) just shipped.**_

- **CE-5a/b/c all shipped & CI-green (PR #4). The CoEdIT feature + packaging is code-complete.** Only the manual M-test on a real Windows box remains.
- **M-TEST (needs a Windows box — the one thing CI can't prove):** download `SpeakType.exe` (218 MB) from PR #4's latest green run → double-click → **dictation works with ZERO download** (speech model baked in) → enable "Improve text (CoEdIT)" in Settings → it downloads 2.4 GB once → dictation is polished → toggle flips it live. If CoEdIT crashes *on enable*, grab the **Event Viewer → Windows Logs → Application** ".NET Runtime" error (most likely a missing **Visual C++ Redistributable** that ONNX Runtime needs) — now non-fatal + logged (`coedit load failed: …` in `%APPDATA%/SpeakType/logs/speaktype.log`).
  - Skill: dotnet-best-practices, run-tests
- **Model is hosted (Release `coedit-large-v1`):** two split assets `coedit-large-fp16.zip.part00` (1.99 GB) + `.part01` (0.40 GB) + `coedit-large-fp16.metadata.txt` (sha256+size of the reassembled zip). Reassemble: `cat coedit-large-fp16.zip.part* > coedit-large-fp16.zip` (sha256 `d74ee0e1…a918ef`), unzip → `encoder_model.onnx` (651 MB **fp16**) + `decoder_model_merged.onnx` (1.8 GB **fp32**) + config.json. **Total ~2.4 GB on disk.** Set `COEDIT_MODEL_DIR` to that folder to run the CE-3 integration tests locally; a copy is at `/tmp/coedit-rel/model` this session.
- **Hard-won gotchas (do not relearn):**
  - **NOT int8** — int8 dynamic-quant breaks T5 cross-attention in ORT (`DynamicQuantizeMatMul cannot broadcast on dim 0`). **NOT full fp16** — fp16-converting the merged decoder's `If` subgraph yields an invalid model. **Use fp16 encoder + fp32 merged decoder** (export script on `main` does this; `scripts/export_coedit_onnx.py`).
  - **ORT C# tensor reuse**: do NOT feed the same `DenseTensor` to multiple `Run()` calls — build fresh per step (else "broadcast on dim 0").
  - **Encoder KV cache is computed once** (first decode step, use_cache_branch=false); cached steps don't re-emit it — preserve it, grow only decoder KV. (Both fixed in `OnnxCoEditModel`.)
  - Export → **HF rate-limits the runner (429)** after a few runs. To republish without re-exporting, use the **`Promote model artifact to Release`** workflow (downloads an existing artifact on the runner, splits >2 GiB, publishes). GitHub **artifact** downloads are throttled ~250 KB/s; **Release CDN** is ~2.7 MB/s — always go via the Release.
- **Seam:** `SpeakType.Onnx/Inference/ICoEditModel.cs` — `Encode(sourceIds) → IEncoderOutput` (once) + `DecodeNextLogits(encoderOutput, decodedSoFar) → float[] logits` (per token); `CoEditPolisher` is the greedy loop. `decoder_start_token_id=0`, `eos_token_id=1`, vocab 32100, instruction `"Fix the grammar: "`.
- **Branch state:** app code (CE-1/2/3) on `feat/coedit-polish` (**unpushed**); export/promote tooling on `main`. Reconcile when merging the feature (take `main`'s tooling). PR #1 (old SymSpell) still open/untouched.

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

### Brick CE-5a/b/c — CoEdIT pivot to opt-in + bake speech model into the exe (2026-06-04)
- **What:** Fixed the user's first-run crash and delivered a true "single file that just works". CoEdIT is now **opt-in, off by default** (its 2.4 GB model downloads only when the user enables "Improve text (CoEdIT)") — the old required-on-first-run gate was crashing on the user's laptop. And the **speech model is baked into the exe**, so a double-click dictates with **zero downloads**. **5a:** `CoEditPolishing` default→false + `SwappableTextPolisher` (pass-through until a model is loaded; thread-safe runtime swap). **5b:** removed the fatal CoEdIT gate; the Settings toggle downloads the model on demand and activates polishing live; load failures are logged + revert the toggle (no crash). **5c:** `ggml-base.en.bin` (~141 MB) embedded as a resource; `Program.TryInstallBundledSpeechModel` materializes it on first run via `ModelStore.InstallFromStream`.
- **Files:** Core — `AppSettings.cs` (default), `Polishing/SwappableTextPolisher.cs` (new), `Models/ModelStore.cs` (`InstallFromStream`). App — `Program.cs` (gate removal, ActivateCoEdit, bundled-model extract), `Settings/SettingsForm.cs` (toggle event + revert), `SpeakType.App.csproj` (embed), `.github/workflows/ci.yml` (pre-build model download + cache), `.gitignore`. Tests — `SwappableTextPolisherTests` (7), `ModelStoreTests` (+4), settings/orchestrator default updates.
- **Verified:** Core **203/203**, Onnx **20/20 (+3 skip)** on macOS. Windows **CI green (PR #4)** for 5b and 5c: App compiles, tests pass, single-file publish → **`SpeakType.exe` = 218 MB** (77 MB app + 141 MB speech model, compressed). The CoEdIT 2.4 GB model is the only remaining download (can't be baked: GitHub 2 GiB asset cap).
- **Notes / decisions (hard-won, do not relearn):**
  - **MSBuild embeds resources at EVALUATION** — a file created by an in-build target is NOT embedded. The model must be fetched BEFORE `dotnet build` (CI step, cached), then a static `<EmbeddedResource Condition="Exists(...)">` picks it up. Validated on a Mac net8.0 proxy.
  - **`WithCulture="false"` is REQUIRED** on the embed: the SDK reads the `.en.` in `ggml-base.en.bin` as an English culture suffix and routes it to a satellite assembly → silently not embedded. (Single-dot filenames are fine.)
  - Use **forward slashes** in the `SpeechModelFile` path (cross-platform; backslashes are literal on macOS).
  - First-run download is now **non-fatal everywhere** (the earlier "strictly required" choice was the crash). Runtime stays fail-open: a polish/load throw → unpolished paste.

### Brick CE-4f — single-file packaging: compress + Windows extraction race fix (2026-06-03)
- **What:** Made the CoEdIT-enabled exe ship sanely. `EnableCompressionInSingleFile` on the App (CoEdIT's ONNX+tokenizer natives had ~doubled the exe). Plus fixed a **Windows-only** race the cold parallel CI runner exposed: concurrent first-run tokenizer extractions threw `UnauthorizedAccessException` on `File.Move(overwrite)` because another thread held the freshly-extracted file open for reading (POSIX rename on macOS tolerates this → passed locally, failed on CI). Serialized extraction with a static lock.
- **Files:** `SpeakType.App/SpeakType.App.csproj` (`EnableCompressionInSingleFile`); `SpeakType.Onnx/Tokenization/CoEditTokenizer.cs` (`ExtractGate` lock around extract).
- **Verified:** Windows **CI green** (PR #4, run 26893461675): Test/Publish/Verify/Artifact all pass; **`SpeakType.exe` = 76.8 MB** (was 175 MB uncompressed; pre-CoEdIT was 66.6 MB → CoEdIT nets ~+10 MB compressed). macOS: cold-extract tests 20/20 (+3 skip) ×2 after the lock. Compression delta measured on a cross-platform proxy: 86 MB → 42 MB.
- **Notes / decisions:** CI caught a bug macOS structurally cannot (POSIX vs Win32 file-lock semantics on rename-over-open-file) — the value of the Windows CI loop. The OnnxRuntime 1.20.1 targets force-include the win-x64 native unconditionally (verified: leaks into a linux publish too) but that's only ~11 MB; compression made the total-size question moot, so the deeper "trim non-win runtimes" optimization was **not** pursued (YAGNI — 76.8 MB is fine).

### Brick CE-4d+e — CoEdIT wired into the app + single-file tokenizer fix (2026-06-03)
- **What:** CoEdIT now runs on every dictation in the real app. **CE-4d** (Windows App glue): `SpeakType.App` references `SpeakType.Onnx`; required first-run download of the multi-part model (cancel/fail → exit, like Whisper); `OnnxCoEditModel` + `CoEditPolisher` built once at startup and injected into `DictationOrchestrator` (fail-open: load error → null polisher), disposed last; "Improve text (CoEdIT)" Settings toggle; `WelcomeForm` refactored to a download-delegate so the CoEdIT store reuses the progress UI. **CE-4e** (packaging correctness): `tokenizer.json` was a `Content` file → emitted beside the exe, **lost** in a single-file deploy → CoEdIT silently no-op'd on a downloaded build. Now an `EmbeddedResource`, extracted to `%LOCALAPPDATA%/SpeakType/onnx/coedit-tokenizer.json` at load (Tokenizers.DotNet needs a path); new parameterless `CoEditTokenizer()` ctor is the production entry point.
- **Files:** `SpeakType.App/{SpeakType.App.csproj, Program.cs, Startup/WelcomeForm.cs, Settings/SettingsForm.cs}`; `SpeakType.Onnx/{SpeakType.Onnx.csproj, Tokenization/CoEditTokenizer.cs}`; tests `SpeakType.Onnx.Tests/Tokenization/CoEditTokenizerTests.cs` (+parameterless-ctor test), `Inference/{CoEditPolisherTests,OnnxCoEditModelTests}.cs` (migrated off `DefaultTokenizerPath`).
- **Verified:** **CE-4d** — Windows **CI green** (PR #4, run 26892045471): App compiles, tests pass on the runner (192 Core, 19+3-skip Onnx), single-file win-x64 publish succeeds → 175 MB `SpeakType.exe`. **CE-4e** — macOS: cold tokenizer-extract **20/20 (+3 skip) ×3** no flakiness; with the real model `COEDIT_MODEL_DIR=/tmp/coedit-rel/model` → **23/23 end-to-end** (embed → extract → real polish). Core **192/192**.
- **Notes / decisions:** First-run download is **strictly required** (user's call) — contradicts the otherwise-fail-open design but matches the Whisper gate; the runtime path stays fail-open (a load/polish throw → unpolished paste). **CE-4e race fixed:** concurrent first-run extraction collided on a shared `.tmp`; now a per-caller `Guid`-suffixed temp + move (caught by parallel xUnit — 6 failures on the first warm-cache-less run). **PR #4** is the CoEdIT feature PR (reconciled with main's fp16 tooling); PR #1 (SymSpell) still untouched. Remaining: exe **size** (175 MB, cause TBD on Windows) + the **clean-Windows M-test** — see Next up.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
