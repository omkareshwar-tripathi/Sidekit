# CoEdIT Polish — Design

**Date:** 2026-06-03
**Status:** Approved (design); sub-project CE-1 implemented.
**Source request:** Add automatic, on-device text improvement to SpeakType. Evolved from the original 4-stage "Fix & Polish" spec.

---

## 0. How we got here (scope decisions)

The original "Fix & Polish" spec had four stages: SymSpell typo-fix, Punctuation restore, GECToR grammar, CoEdIT rewrite. Through brainstorming we **dropped three of the four** because they are redundant against Whisper.NET (which already emits punctuated, capitalized, real-word English) and/or impractical to source:

**User decisions (2026-06-03):**

1. **Drop Punctuation** — redundant with Whisper.
2. **Drop GECToR** — its grammar job is a strict subset of CoEdIT's, and there is **no public ONNX GECToR** (PyTorch-only `gotutiyan/gector-*`); exporting + the 5k-tag edit-application + verb-form dictionary is disproportionate effort for a redundant stage.
3. **Drop SymSpell** — rarely fires on clean Whisper output; risk of mangling names/jargon outweighs benefit. (It only ever lived on the unmerged PR #1 branch, so "removing" it = not merging that branch. PR #1 left as-is for now, untouched, per user.)
4. **Keep only CoEdIT**, and **run it automatically on every dictation** (not behind a button). Model **coedit-large** (770M). Latency (~1–4 s/dictation) and ~800 MB download accepted. **Default-on toggle.**
5. **Model delivery: download on first run** (reusing the existing Whisper model-store plumbing), *not* bundled in the exe — revisited from the original "bundle" choice because 800 MB in the exe is impractical.

### Resulting product

> No automatic "Fix" pipeline. Dictation stays as today (Whisper → cleanup → paste) **plus** CoEdIT runs automatically before paste when enabled. Nothing else touches the text. On error or missing model, paste the raw cleaned text (fail-open — never lose words).

```
Whisper → TranscriptCleaner → [CoEdIT polish, if toggle on] → paste
```

CoEdIT (`grammarly/coedit-large`) is **Flan-T5-large** instruction-tuned for text editing. We prepend a fixed, conservative instruction (default `"Fix the grammar: "`) since it runs on everything automatically — we don't want aggressive paraphrasing.

---

## 1. Architecture

Mirrors the existing Whisper port/adapter pattern:

- **Port (Core):** `ITextPolisher { string Polish(string text); }` — synchronous; it runs on the orchestrator's existing background dispatcher thread, so no async is needed (matches `ITranscriber`).
- **Adapter (new project `SpeakType.Onnx`, net8.0, cross-platform):** holds the tokenizer + ONNX Runtime encoder-decoder engine. Builds and tests on **Mac/CI**, unlike WinForms `SpeakType.App`.
- **Setting:** `CoEditPolishing` (bool, default `true`) + a Settings checkbox.
- **Model:** downloaded via the existing `IModelDownloader`/`ModelStore` into `%LOCALAPPDATA%\SpeakType\models\`.

### CoEdIT model facts (from `config.json`)
`T5ForConditionalGeneration`, encoder-decoder, `d_model=1024`, `num_layers=24`, `num_heads=16`, `d_kv=64`, `vocab_size=32100`, `decoder_start_token_id=0` (pad), `eos_token_id=1`, `pad_token_id=0`. Tokenizer = SentencePiece **Unigram**.

---

## 2. Tokenizer (resolved — important deviation from the brainstorm assumption)

The design assumed `Microsoft.ML.Tokenizers` would handle the T5 SentencePiece tokenizer. **It does not** — verified on 2.0.0 and 3.0.0-preview, it throws `IndexOutOfRangeException` constructing the Unigram model from `spiece.model` (independent of BOS/EOS flags). `Microsoft.ML.OnnxRuntime.Extensions` supports Unigram natively but its prerelease ships **Windows-only** binaries (no osx/linux), so it isn't testable on Mac/CI.

**Resolution: `Tokenizers.DotNet` (v1.4.1)** — a thin wrapper over the HuggingFace Rust tokenizer that loads `tokenizer.json` directly. It ships native runtimes for **osx-arm64 / osx-x64 / win-x64 / linux-x64**, so it works on the dev Mac, CI, and the shipped Windows app. Verified: it reproduces the reference HF token ids exactly (e.g. `"Fix the grammar: he go to school every days."` → `14269,8,19519,10,3,88,281,12,496,334,477,5,1`) and round-trips. This is a native dependency, but cross-platform — like the existing `Whisper.net.Runtime`.

The `tokenizer.json` (~2.4 MB) is **bundled** (`<Content>` copied to output); only the ~800 MB model downloads.

---

## 3. Decomposition (each sub-project gets its own plan → bricks)

| # | Sub-project | Delivers | Status |
|---|---|---|---|
| **CE-1** | `SpeakType.Onnx` project + `CoEditTokenizer` (Tokenizers.DotNet) | T5 encode/decode proven in C#, golden-vector tested | **Done** |
| CE-2 | CoEdIT engine: encoder + greedy decoder loop behind an `IOnnxSession` seam; `ITextPolisher` impl | `Polish(text)` logic, TDD'd against a fake session | next |
| CE-3 | Model acquisition: download + unpack the coedit-large ONNX archive on first run | real model on disk via existing downloader | pending |
| CE-4 | Orchestrator wiring + `CoEditPolishing` setting + Settings toggle + logging | feature live in the app (Windows-verified) | pending |
| — | (external) one-time model export+quantize+host — script written for the user to run | the downloadable ~800 MB artifact | pending |

---

## 4. CE-1 — implemented

**Goal:** stand up the cross-platform `SpeakType.Onnx` project and prove correct T5 tokenization in C#, since that was the #1 unknown.

- New project `SpeakType.Onnx` (net8.0): references `Tokenizers.DotNet` + its four RID runtime packages; bundles `assets/tokenizer.json` as copied content; references `SpeakType.Core`.
- `SpeakType.Onnx/Tokenization/CoEditTokenizer.cs`: `Encode(text) → token ids (EOS appended)`, `Decode(ids) → text (special tokens stripped)`, `DefaultTokenizerPath` (next to the assembly). Guards: null text, missing file.
- `SpeakType.Onnx.Tests`: 13 tests — 5 golden vectors (encode + decode round-trip), EOS-appended, missing-file throw, null-text throw. Golden vectors generated from the reference HuggingFace `tokenizers` library.

**Verified:** `SpeakType.Onnx.Tests` 13/13 green on macOS; Core 179/179 unchanged; Core/Whisper/Onnx all build.

---

## 5. Error handling & edge cases (whole feature)

- **Polish failure** (model not downloaded, ONNX/tokenizer error, timeout): fall back to pasting the un-polished cleaned text. Never lose the user's words.
- **Toggle off:** skip CoEdIT entirely; zero added latency.
- **Empty text:** never reaches the polisher (short-circuited to NoSpeech upstream).
- **Latency:** runs on the existing background dispatcher; never blocks the UI thread. Tray feedback (e.g. "Polishing…") to be decided in CE-4.

---

## 6. Out of scope

- Per-stage "undo to raw" beyond existing paste behavior.
- Tone presets / multiple instructions (single fixed instruction for v1; the prompt is one constant we can tune later).
- Re-deciding PR #1's fate (left as-is per user).
