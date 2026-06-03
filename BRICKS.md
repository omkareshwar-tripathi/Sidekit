# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### CoEdIT Polish

_On-device text improvement: CoEdIT (Flan-T5-large) runs **automatically on every dictation** before paste (toggle, default-on), fail-open. Replaces the abandoned 4-stage "Fix & Polish" — we dropped Punctuation/GECToR/SymSpell as redundant-with-Whisper. Spec: `docs/superpowers/specs/2026-06-03-coedit-polish-design.md`. **CE-1 (tokenizer) + CE-2 (engine) + CE-3 (real ONNX inference) shipped & verified end-to-end** — `"he go to school every days." → "He goes to school every day."` runs on the Mac (Onnx tests 22/22 with the model, 19+3-skip without)._

- **Next: CE-4 — wire CoEdIT into the app.** (a) **Model acquisition on first run** — download the model from the Release + reassemble + unpack into the model store. The store is single-file (`ggml-{name}.bin`); add a small sibling/extension for a multi-part zip. (b) **Orchestrator wiring** — inject `ITextPolisher`; in `ProcessRecording`, after `_cleaner.Clean(...)` and before paste, `try { polished = polisher.Polish(cleaned) } catch { polished = cleaned }` (fail-open). Gate on the new setting. **Spacing watch:** the cleaner adds a trailing space; the model output won't have it — re-add it for paste. (c) **`CoEditPolishing` bool setting (default true) + Settings toggle.** (d) **Logging** (PolishingComplete duration). Windows-verified (App layer).
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
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

### Brick CE-3 — real ONNX inference (OnnxCoEditModel) (2026-06-03)
- **What:** The real `ICoEditModel`: two ONNX Runtime sessions (fp16 encoder + fp32 merged decoder) running the KV-cache greedy decode. Proven end-to-end on the Mac — `"he go to school every days." → "He goes to school every day."`. This is the first time CoEdIT actually polishes text in the app's code.
- **Files:** `SpeakType.Onnx/Inference/OnnxCoEditModel.cs`; `SpeakType.Onnx/SpeakType.Onnx.csproj` (+`Microsoft.ML.OnnxRuntime` 1.20.1); `SpeakType.Onnx.Tests/SpeakType.Onnx.Tests.csproj` (+`Xunit.SkippableFact`); `SpeakType.Onnx.Tests/Inference/OnnxCoEditModelTests.cs` (3 integration `SkippableFact`s, gated on `COEDIT_MODEL_DIR`).
- **Verified:** With the model → **Onnx 22/22**; without → **19 pass + 3 skip** (CI-safe). Core **179/179**. Manual: the full greedy loop emits He→goes→to→school→every→day→.→EOS.
- **Notes / decisions:** Two bugs the real model exposed, both fixed: (1) **don't reuse a `DenseTensor` across `Run()` calls** (build fresh per step, else "broadcast on dim 0"); (2) **the merged decoder doesn't re-emit encoder/cross-attention KV on cached steps** — preserve the first-step encoder KV, grow only decoder KV. Default ORT graph optimization is fine (the fusion isn't the bug). See the CoEdIT "Next up" section for the model/Release/gotcha details CE-4 needs.

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

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
