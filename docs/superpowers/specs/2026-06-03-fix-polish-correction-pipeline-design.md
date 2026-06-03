# Fix & Polish — Correction Pipeline (Design)

**Date:** 2026-06-03
**Status:** Approved (design); sub-project 0 ready to plan.
**Source request:** Add the "Fix & Polish" text-correction pipeline (SymSpell → Punctuation → GECToR → CoEdIT) from the Fix & Polish spec to the existing **Windows** SpeakType app.

---

## 0. Context & scope decisions

The Fix & Polish spec is written generically for a *raw acoustic recognizer* whose output is "unpunctuated and lowercased." SpeakType uses **Whisper.NET (ggml)**, which already emits **punctuated, capitalized, real-word English**. This makes two of the three Fix stages largely redundant *against Whisper specifically* (SymSpell rarely fires; punctuation/caps restore overlaps Whisper). This was surfaced to the user.

**User decisions (2026-06-03):**

1. **Scope:** build the **full 4-stage spec** (SymSpell + Punctuation + GECToR + CoEdIT), despite the redundancy.
2. **Model delivery:** **bundle** model assets in the single-file exe (no on-demand download). *Caveat recorded:* this differs from how the Whisper model is handled today (downloaded, not bundled); large bundled native assets are extracted to a temp dir on launch (startup + disk cost) and push the CI artifact toward GitHub size limits. Revisit per stage if CoEdIT's size bites.
3. **SymSpell behavior:** default **ON, conservative** (edit-distance 1, frequency-gap gate, skip Capitalized/ALLCAPS tokens).

Because four ML/NLP components + ONNX Runtime + four tokenizers is far too large for one spec, the work is **decomposed into sub-projects**, each with its own spec → plan → bricks. This document fully specifies **sub-project 0** and records the decomposition for the rest.

### Decomposition (build order)

| # | Sub-project | New infra |
|---|---|---|
| **0** | **Correction-pipeline scaffold + SymSpell** (this spec) | SymSpell NuGet + dict asset |
| 1 | ONNX Runtime foundation (shared tokenizer/inference helper + asset embedding) | ONNX Runtime |
| 2 | Punctuation stage (CNN-BiLSTM ONNX tagger) | model asset |
| 3 | GECToR grammar stage (ONNX edit-tagger) | model asset |
| 4 | CoEdIT Polish (seq2seq + "Polish" UI button + tone presets, off the auto path) | model asset + UI |

Stages 1–4 each get their own design doc when reached. The pipeline built in sub-project 0 is the spine they plug into.

---

## 1. Sub-project 0 — goal

Add a **correction-pipeline spine** to the dictation path and ship its first concrete stage (**SymSpell** spelling correction), running automatically after the existing `TranscriptCleaner`, gated by a user setting (default on, conservative).

Success criteria:

- A pure-Core `ITextCorrector` port + `TextCorrectionPipeline` that chains stages, each gated by an `AppSettings` toggle.
- A `SymSpellCorrector` stage that fixes obvious typos **without** touching names, acronyms, jargon, known words, punctuation, or the trailing space the cleaner adds.
- Wired into `DictationOrchestrator` after `TranscriptCleaner`, before paste.
- A `SpellCorrection` setting (default `true`) and a Settings-form checkbox.
- All 179 existing tests stay green; new stages are TDD'd.

---

## 2. Architecture

New pure-Core namespace `SpeakType.Core/Correction/`.

```csharp
public interface ITextCorrector
{
    string Correct(string text);   // one Fix stage; pure, synchronous
}

public sealed class TextCorrectionPipeline
{
    // ordered list of (stage, isEnabled-from-settings)
    public TextCorrectionPipeline(
        IReadOnlyList<(ITextCorrector corrector, Func<AppSettings, bool> isEnabled)> stages);

    public string Correct(string text, AppSettings settings);
    // runs each stage in order, skipping any whose isEnabled(settings) == false
}
```

- Each future Fix stage is just another `ITextCorrector` added to the list — this is what makes stages 2–4 drop-in.
- Toggles are read **per run** from the current `AppSettings`, so changing a setting at runtime (Settings form) takes effect on the next dictation with no rewiring.
- The pipeline is **pure Core**, fully unit-testable with trivial fake correctors.

### Placement in the flow

```
Whisper raw → TranscriptCleaner.Clean(raw, FillerRemoval)
            → (empty / hallucination ⇒ NoSpeech, short-circuits here)
            → TextCorrectionPipeline.Correct(cleaned, settings)   ← NEW
            → IPasteService.Paste(corrected)
```

In `DictationOrchestrator.ProcessRecording()`: insert the pipeline call **after** `_cleaner.Clean(...)` and **before** paste. The empty/hallucination short-circuit already runs before this point, so the pipeline only ever sees real, non-empty text.

---

## 3. SymSpell stage

`SymSpellCorrector : ITextCorrector`, in `SpeakType.Core/Correction/`.

- **Library:** `SymSpell` NuGet (Wolf Garbe, **MIT**). **Decision:** this is the first NuGet dependency added to `SpeakType.Core` (previously dependency-free). Justified: SymSpell is a deterministic, platform-agnostic algorithm; keeping the stage in Core keeps it unit-testable on CI/Mac (the App project is Windows-only WinForms and cannot host testable logic).
- **Dictionary asset:** `frequency_dictionary_en_82_765.txt` (MIT, ships with SymSpell), embedded as a resource and loaded once at construction. (Aligns with the "bundle in exe" decision.)
- **Conservative correction rules:**
  - Tokenize via regex over word tokens so **all surrounding punctuation and the cleaner's trailing space are preserved** (token-replace in place; do **not** split/rejoin on spaces).
  - For each word token, **skip** (leave verbatim) when it is: ≤2 chars, **not all-lowercase** (skips `Capitalized`, `ALLCAPS`, `MixedCase` → protects names/acronyms/jargon), or already present in the dictionary.
  - For a remaining unknown lowercase word, `Lookup` at **max edit-distance 1**, `Verbosity.Top`; replace **only** when the best suggestion's frequency clears a **frequency floor** (guards against swapping a real-but-rare word for a common near-match). Exact floor pinned during TDD.
- **Pure & synchronous:** in-memory, microsecond-class; no IO on the hot path after construction.

---

## 4. Settings

- Add `public bool SpellCorrection { get; set; } = true;` to `AppSettings`. No `Normalize()` change needed (bool). `JsonSettingsStore` serializes it automatically (camelCase `spellCorrection`); older settings files lacking the key fall back to the default `true`.
- Settings form gains a **"Spelling correction"** checkbox bound to this field (Windows-only brick).

---

## 5. Bricks

| Brick | Scope | Files (approx.) | Verify | Testable |
|---|---|---|---|---|
| **0a** | `ITextCorrector` + `TextCorrectionPipeline` (no SymSpell yet) | `Core/Correction/ITextCorrector.cs`, `Core/Correction/TextCorrectionPipeline.cs`, tests | unit: stage ordering, toggle gating on/off, empty-list passthrough | CI/Mac |
| **0b** | `SymSpellCorrector` + embedded dict + conservative rules | `Core/Correction/SymSpellCorrector.cs`, `Core/SpeakType.Core.csproj` (SymSpell ref + embedded dict), tests | unit: fixes a clear typo; **leaves names/ACRONYMS/known words/short words alone**; preserves punctuation + trailing space; frequency-floor gate | CI/Mac |
| **0c** | Wire pipeline into orchestrator; add `SpellCorrection` setting; composition root registers SymSpell stage gated on the toggle | `Core/Settings/AppSettings.cs`, `Core/Orchestration/DictationOrchestrator.cs`, `App/Program.cs`, orchestrator tests | orchestrator test: corrected text reaches paste; toggle off ⇒ SymSpell skipped; **179 existing green** | CI/Mac |
| **0d** | Settings-form "Spelling correction" checkbox | `App/Settings/SettingsForm.cs` | M-test / laptop screenshot; persists to settings.json | Windows |

Each brick stays well under the ~150-LOC / 5-file hard ceiling. TDD throughout (`test-driven-development`, `dotnet-xunit`); verify with `run-tests`; code quality per `dotnet-best-practices`.

### Skills per brick

- **0a** — Skill: `test-driven-development`, `dotnet-xunit`, `dotnet-best-practices`, `run-tests`
- **0b** — Skill: `test-driven-development`, `dotnet-xunit`, `dotnet-best-practices`, `run-tests` (SymSpell lib: no skill — use its docs)
- **0c** — Skill: `test-driven-development`, `dotnet-xunit`, `dotnet-best-practices`, `run-tests`
- **0d** — Skill: `dotnet-best-practices`, `run-tests` (Windows-only UI; verify by hand)

---

## 6. Error handling & edge cases

- **Pipeline:** a stage that throws must not crash dictation. The orchestrator already wraps the cycle in its exception handling; additionally, `SymSpellCorrector` is defensive — any internal failure returns the input unchanged (fail-open: never lose the user's text).
- **Empty / whitespace text:** never reaches the pipeline (short-circuited to NoSpeech upstream), but `Correct("")` returns `""` regardless.
- **Trailing space:** the cleaner appends a single trailing space; the pipeline and SymSpell must preserve it (token-replace approach guarantees this) so paste spacing is unchanged.
- **Dictionary load failure:** if the embedded dict can't be read, `SymSpellCorrector` construction fails fast at startup (composition root) rather than silently disabling correction — a packaging bug should be loud in dev/CI, not silent in prod.

---

## 7. Out of scope (this sub-project)

- ONNX Runtime, Punctuation, GECToR, CoEdIT (sub-projects 1–4).
- Text *generation* from sparse context (separate task per the Fix & Polish spec §7).
- Per-stage "undo to raw" UI beyond the existing paste behavior.
