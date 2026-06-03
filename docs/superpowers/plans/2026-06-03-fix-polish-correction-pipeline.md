# Fix & Polish — Correction Pipeline (sub-project 0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable correction-pipeline spine to the dictation path and ship its first stage — conservative SymSpell spelling correction — running automatically after `TranscriptCleaner`, gated by a default-on `SpellCorrection` setting.

**Architecture:** Pure-Core `ITextCorrector` port + `TextCorrectionPipeline` that chains stages, each gated by an `AppSettings` predicate read per run. `SymSpellCorrector` is the first stage (in Core, unit-testable on CI/Mac). The orchestrator calls the pipeline between `TranscriptCleaner.Clean(...)` and paste via a trailing **optional** ctor param (null ⇒ passthrough), so all 179 existing tests stay untouched.

**Tech Stack:** .NET 8, C#, xUnit, SymSpell NuGet (MIT) + `frequency_dictionary_en_82_765.txt` embedded resource, WinForms (settings checkbox only).

**Spec:** `docs/superpowers/specs/2026-06-03-fix-polish-correction-pipeline-design.md`

---

## File Structure

- `SpeakType.Core/Correction/ITextCorrector.cs` (new) — the one-method port.
- `SpeakType.Core/Correction/TextCorrectionPipeline.cs` (new) — chains stages, gates by settings.
- `SpeakType.Core/Correction/SymSpellCorrector.cs` (new) — SymSpell stage, conservative rules.
- `SpeakType.Core/Correction/frequency_dictionary_en_82_765.txt` (new asset, embedded).
- `SpeakType.Core/SpeakType.Core.csproj` (modify) — SymSpell PackageReference + EmbeddedResource.
- `SpeakType.Core/Settings/AppSettings.cs` (modify) — add `SpellCorrection`.
- `SpeakType.Core/Orchestration/DictationOrchestrator.cs` (modify) — optional pipeline param + call site.
- `SpeakType.App/Program.cs` (modify) — build pipeline, pass to orchestrator.
- `SpeakType.App/Settings/SettingsForm.cs` (modify) — checkbox.
- `SpeakType.Tests/Correction/TextCorrectionPipelineTests.cs` (new).
- `SpeakType.Tests/Correction/SymSpellCorrectorTests.cs` (new).
- `SpeakType.Tests/Orchestration/DictationOrchestratorTests.cs` (modify) — one wiring test.

**Verify test commands** with the `run-tests` skill (this project's platform/filter syntax). The filters below assume `dotnet test --filter "FullyQualifiedName~..."`; confirm via the skill before first run.

---

## Task 1 (Brick 0a): `ITextCorrector` + `TextCorrectionPipeline`

**Skill:** `test-driven-development`, `dotnet-xunit`, `dotnet-best-practices`, `run-tests`

**Files:**
- Create: `SpeakType.Core/Correction/ITextCorrector.cs`
- Create: `SpeakType.Core/Correction/TextCorrectionPipeline.cs`
- Test: `SpeakType.Tests/Correction/TextCorrectionPipelineTests.cs`

- [ ] **Step 1: Write the failing tests**

Create `SpeakType.Tests/Correction/TextCorrectionPipelineTests.cs`:

```csharp
using SpeakType.Core.Correction;
using SpeakType.Core.Settings;

namespace SpeakType.Tests.Correction;

public sealed class TextCorrectionPipelineTests
{
    // Minimal fake stage: appends a marker so order/invocation is observable.
    private static ITextCorrector Appender(string marker) =>
        new DelegateCorrector(text => text + marker);

    private sealed class DelegateCorrector(Func<string, string> f) : ITextCorrector
    {
        public string Correct(string text) => f(text);
    }

    [Fact]
    public void Runs_stages_in_order()
    {
        var pipeline = new TextCorrectionPipeline(new (ITextCorrector, Func<AppSettings, bool>)[]
        {
            (Appender("A"), _ => true),
            (Appender("B"), _ => true),
        });

        Assert.Equal("xAB", pipeline.Correct("x", new AppSettings()));
    }

    [Fact]
    public void Skips_disabled_stages()
    {
        var pipeline = new TextCorrectionPipeline(new (ITextCorrector, Func<AppSettings, bool>)[]
        {
            (Appender("A"), _ => false),
            (Appender("B"), _ => true),
        });

        Assert.Equal("xB", pipeline.Correct("x", new AppSettings()));
    }

    [Fact]
    public void Empty_pipeline_is_passthrough()
    {
        var pipeline = new TextCorrectionPipeline(Array.Empty<(ITextCorrector, Func<AppSettings, bool>)>());

        Assert.Equal("unchanged ", pipeline.Correct("unchanged ", new AppSettings()));
    }

    [Fact]
    public void Gate_reads_current_settings()
    {
        var pipeline = new TextCorrectionPipeline(new (ITextCorrector, Func<AppSettings, bool>)[]
        {
            (Appender("A"), s => s.SpellCorrection),
        });

        Assert.Equal("x",  pipeline.Correct("x", new AppSettings { SpellCorrection = false }));
        Assert.Equal("xA", pipeline.Correct("x", new AppSettings { SpellCorrection = true }));
    }
}
```

> Note: `Gate_reads_current_settings` references `AppSettings.SpellCorrection`, added in Task 3. If running Task 1 before Task 3, temporarily change its gate to `_ => true`/`_ => false` literals, or implement Task 3's one-line `AppSettings` field first. Recommended: add the `SpellCorrection` property (Task 3, Step "add field") now so this test compiles.

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test SpeakType.Tests --filter "FullyQualifiedName~TextCorrectionPipelineTests"`
Expected: FAIL — `ITextCorrector` / `TextCorrectionPipeline` do not exist.

- [ ] **Step 3: Create the port**

`SpeakType.Core/Correction/ITextCorrector.cs`:

```csharp
namespace SpeakType.Core.Correction;

/// <summary>
/// One Fix-pipeline stage: a pure, synchronous string→string transform applied
/// to dictated text after <c>TranscriptCleaner</c> and before paste.
/// </summary>
public interface ITextCorrector
{
    string Correct(string text);
}
```

- [ ] **Step 4: Create the pipeline**

`SpeakType.Core/Correction/TextCorrectionPipeline.cs`:

```csharp
using SpeakType.Core.Settings;

namespace SpeakType.Core.Correction;

/// <summary>
/// Runs an ordered list of <see cref="ITextCorrector"/> stages, applying each only
/// when its <c>isEnabled</c> predicate returns true for the current settings.
/// Predicates are evaluated per call, so a settings change (e.g. a Settings-form
/// toggle) takes effect on the next dictation with no re-wiring. Pure Core.
/// </summary>
public sealed class TextCorrectionPipeline
{
    private readonly IReadOnlyList<(ITextCorrector Corrector, Func<AppSettings, bool> IsEnabled)> _stages;

    public TextCorrectionPipeline(
        IReadOnlyList<(ITextCorrector corrector, Func<AppSettings, bool> isEnabled)> stages)
    {
        ArgumentNullException.ThrowIfNull(stages);
        _stages = stages;
    }

    public string Correct(string text, AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        foreach (var (corrector, isEnabled) in _stages)
        {
            if (isEnabled(settings))
            {
                text = corrector.Correct(text);
            }
        }
        return text;
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dotnet test SpeakType.Tests --filter "FullyQualifiedName~TextCorrectionPipelineTests"`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add SpeakType.Core/Correction/ITextCorrector.cs \
        SpeakType.Core/Correction/TextCorrectionPipeline.cs \
        SpeakType.Tests/Correction/TextCorrectionPipelineTests.cs
git commit -m "feat(correction): add ITextCorrector port + TextCorrectionPipeline (brick 0a)"
```

---

## Task 2 (Brick 0b): `SymSpellCorrector`

**Skill:** `test-driven-development`, `dotnet-xunit`, `dotnet-best-practices`, `run-tests` (SymSpell library: no skill — use its docs)

**Files:**
- Create: `SpeakType.Core/Correction/SymSpellCorrector.cs`
- Add asset: `SpeakType.Core/Correction/frequency_dictionary_en_82_765.txt`
- Modify: `SpeakType.Core/SpeakType.Core.csproj`
- Test: `SpeakType.Tests/Correction/SymSpellCorrectorTests.cs`

- [ ] **Step 1: Add the SymSpell NuGet + the dictionary asset + embed it**

```bash
dotnet add SpeakType.Core package SymSpell
curl -L -o SpeakType.Core/Correction/frequency_dictionary_en_82_765.txt \
  https://raw.githubusercontent.com/wolfgarbe/SymSpell/master/SymSpell/frequency_dictionary_en_82_765.txt
```

Confirm the file is ~2.5 MB and its first line looks like `the 23135851162`. Then add the embed block to `SpeakType.Core/SpeakType.Core.csproj` (the `dotnet add` step already added the `<PackageReference>`):

```xml
  <ItemGroup>
    <EmbeddedResource Include="Correction/frequency_dictionary_en_82_765.txt">
      <LogicalName>frequency_dictionary_en_82_765.txt</LogicalName>
    </EmbeddedResource>
  </ItemGroup>
```

- [ ] **Step 2: Write the failing tests**

Create `SpeakType.Tests/Correction/SymSpellCorrectorTests.cs`:

```csharp
using SpeakType.Core.Correction;

namespace SpeakType.Tests.Correction;

public sealed class SymSpellCorrectorTests
{
    private readonly SymSpellCorrector _sut = new();

    [Fact]
    public void Fixes_a_clear_lowercase_typo()
    {
        // "recieve" is a classic misspelling; edit-distance 1 to "receive".
        Assert.Equal("please receive it", _sut.Correct("please recieve it"));
    }

    [Fact]
    public void Leaves_known_words_unchanged()
    {
        Assert.Equal("the quick brown fox", _sut.Correct("the quick brown fox"));
    }

    [Fact]
    public void Skips_capitalized_tokens_protecting_proper_nouns()
    {
        // "Kubernetes" / a name: capitalized ⇒ never touched, even though unknown.
        Assert.Equal("Kubernetes and Omkareshwar", _sut.Correct("Kubernetes and Omkareshwar"));
    }

    [Fact]
    public void Skips_allcaps_acronyms()
    {
        Assert.Equal("the HTTP API", _sut.Correct("the HTTP API"));
    }

    [Fact]
    public void Skips_short_tokens()
    {
        // Two-letter tokens are too risky to "correct".
        Assert.Equal("go to ok", _sut.Correct("go to ok"));
    }

    [Fact]
    public void Preserves_punctuation_and_trailing_space()
    {
        // Cleaner output shape: capitalized sentence + period + trailing space.
        var result = _sut.Correct("Hello, freind. ");
        Assert.Equal("Hello, friend. ", result);
    }

    [Fact]
    public void Empty_string_returns_empty()
    {
        Assert.Equal("", _sut.Correct(""));
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `dotnet test SpeakType.Tests --filter "FullyQualifiedName~SymSpellCorrectorTests"`
Expected: FAIL — `SymSpellCorrector` does not exist.

- [ ] **Step 4: Implement `SymSpellCorrector`**

`SpeakType.Core/Correction/SymSpellCorrector.cs`:

```csharp
using System.Reflection;
using System.Text.RegularExpressions;

namespace SpeakType.Core.Correction;

/// <summary>
/// Conservative spelling correction (spec §3). Operates token-by-token via regex so
/// all surrounding punctuation and the cleaner's trailing space survive. A word is
/// only changed when it is all-lowercase, longer than two letters, unknown to the
/// dictionary, and a single-edit suggestion clears a frequency floor — this protects
/// names, ACRONYMS, jargon, and rare-but-valid words. Fail-open: any internal error
/// returns the input unchanged so the user never loses text.
/// </summary>
public sealed partial class SymSpellCorrector : ITextCorrector
{
    private const int MaxEdit = 1;
    // Frequency floor: reject a suggestion whose corpus count is below this, so a real
    // but rare word isn't swapped for a common near-match. Pinned conservatively; the
    // skip rules above are the primary safety net. Tune against the dictionary if needed.
    private const long FrequencyFloor = 1_000_000;

    private readonly global::SymSpell _symSpell =
        new(initialCapacity: 82_765, maxDictionaryEditDistance: MaxEdit);

    [GeneratedRegex("[A-Za-z]+")]
    private static partial Regex WordToken();

    public SymSpellCorrector()
    {
        using var stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("frequency_dictionary_en_82_765.txt")
            ?? throw new InvalidOperationException(
                "Embedded SymSpell dictionary 'frequency_dictionary_en_82_765.txt' not found.");
        // termIndex 0, countIndex 1 — the file is "<word> <count>" per line.
        if (!_symSpell.LoadDictionaryStream(stream, termIndex: 0, countIndex: 1))
        {
            throw new InvalidOperationException("Failed to load embedded SymSpell dictionary.");
        }
    }

    public string Correct(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return text;
        }

        try
        {
            return WordToken().Replace(text, m => CorrectToken(m.Value));
        }
        catch
        {
            return text; // fail-open: never lose the user's text
        }
    }

    private string CorrectToken(string token)
    {
        if (token.Length <= 2 || !IsAllLower(token))
        {
            return token;
        }

        var suggestions = _symSpell.Lookup(token, global::SymSpell.Verbosity.Top, MaxEdit);
        if (suggestions.Count == 0)
        {
            return token;
        }

        var top = suggestions[0];
        if (top.distance == 0 || top.count < FrequencyFloor)
        {
            return token; // already a known word, or candidate too rare to trust
        }

        return top.term;
    }

    private static bool IsAllLower(string token)
    {
        foreach (var c in token)
        {
            if (char.IsUpper(c))
            {
                return false;
            }
        }
        return true;
    }
}
```

> The `global::SymSpell` prefix disambiguates the NuGet type from our `SpeakType.Core.Correction` namespace. If `LoadDictionaryStream` is unavailable in the installed SymSpell version, write the stream to a temp file and use `LoadDictionary(path, 0, 1)` instead (functionally identical; note the fallback in the commit message).

- [ ] **Step 5: Run tests to verify they pass**

Run: `dotnet test SpeakType.Tests --filter "FullyQualifiedName~SymSpellCorrectorTests"`
Expected: PASS (7 tests). If `Fixes_a_clear_lowercase_typo` or `Preserves_punctuation_and_trailing_space` fail because the chosen typo's correction sits below `FrequencyFloor`, pick a typo whose target is high-frequency (e.g. "teh"→"the", "freind"→"friend") and/or lower the floor — keep the skip-rule tests authoritative.

- [ ] **Step 6: Commit**

```bash
git add SpeakType.Core/Correction/SymSpellCorrector.cs \
        SpeakType.Core/Correction/frequency_dictionary_en_82_765.txt \
        SpeakType.Core/SpeakType.Core.csproj \
        SpeakType.Tests/Correction/SymSpellCorrectorTests.cs
git commit -m "feat(correction): add conservative SymSpellCorrector stage (brick 0b)"
```

---

## Task 3 (Brick 0c): wire pipeline into orchestrator + add setting

**Skill:** `test-driven-development`, `dotnet-xunit`, `dotnet-best-practices`, `run-tests`

**Files:**
- Modify: `SpeakType.Core/Settings/AppSettings.cs`
- Modify: `SpeakType.Core/Orchestration/DictationOrchestrator.cs`
- Modify: `SpeakType.App/Program.cs`
- Test: `SpeakType.Tests/Orchestration/DictationOrchestratorTests.cs`

- [ ] **Step 1: Add the `SpellCorrection` field**

In `SpeakType.Core/Settings/AppSettings.cs`, after the `FillerRemoval` line, add:

```csharp
    public bool SpellCorrection { get; set; } = true;
```

(No `Normalize()` change — bools need none. `JsonSettingsStore` serializes `spellCorrection` automatically; older files lacking the key fall back to `true`.)

- [ ] **Step 2: Write the failing wiring test**

In `SpeakType.Tests/Orchestration/DictationOrchestratorTests.cs`, add `using SpeakType.Core.Correction;` to the usings, then add:

```csharp
    [Fact]
    public void Correction_pipeline_runs_between_clean_and_paste()
    {
        // Pipeline stage uppercases, gated on SpellCorrection.
        var stage = new UpperCorrector();
        var pipeline = new TextCorrectionPipeline(new (ITextCorrector, Func<AppSettings, bool>)[]
        {
            (stage, s => s.SpellCorrection),
        });
        var settings = new AppSettings { FillerRemoval = true, SpellCorrection = true };
        var sut = new DictationOrchestrator(
            _hotkey, _audio, _transcriber, _paste, new TranscriptCleaner(), settings,
            _clock, _timer, correctionPipeline: pipeline);

        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Um, hello.";

        _hotkey.Press();
        _hotkey.Release();

        // Cleaner ⇒ "Hello. " ; pipeline uppercases ⇒ "HELLO. "
        Assert.Equal("HELLO. ", _paste.ReceivedText);
    }

    [Fact]
    public void Correction_pipeline_skipped_when_setting_off()
    {
        var pipeline = new TextCorrectionPipeline(new (ITextCorrector, Func<AppSettings, bool>)[]
        {
            (new UpperCorrector(), s => s.SpellCorrection),
        });
        var settings = new AppSettings { SpellCorrection = false };
        var sut = new DictationOrchestrator(
            _hotkey, _audio, _transcriber, _paste, new TranscriptCleaner(), settings,
            _clock, _timer, correctionPipeline: pipeline);

        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Um, hello.";

        _hotkey.Press();
        _hotkey.Release();

        Assert.Equal("Hello. ", _paste.ReceivedText); // unchanged by the (disabled) stage
    }

    private sealed class UpperCorrector : ITextCorrector
    {
        public string Correct(string text) => text.ToUpperInvariant();
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `dotnet test SpeakType.Tests --filter "FullyQualifiedName~DictationOrchestratorTests.Correction"`
Expected: FAIL — `DictationOrchestrator` has no `correctionPipeline` parameter.

- [ ] **Step 4: Add the optional pipeline param + call site**

In `SpeakType.Core/Orchestration/DictationOrchestrator.cs`:

1. Add `using SpeakType.Core.Correction;` to the usings.
2. Add a field next to `_cleaner`: `private readonly TextCorrectionPipeline? _correctionPipeline;`
3. Add a **trailing optional** ctor param after `logger` and assign it. The ctor tail becomes:

```csharp
        ICycleDispatcher? dispatcher = null,
        AppLogger? logger = null,
        TextCorrectionPipeline? correctionPipeline = null)
    {
        // ... existing null checks ...
        _dispatcher = dispatcher ?? new SynchronousCycleDispatcher();
        _logger = logger;
        _correctionPipeline = correctionPipeline;
```

4. In `ProcessRecording()`, after the `if (cleaned.Length == 0) return NoSpeech;` block (currently line ~311), insert the correction call and use its result for logging + paste:

```csharp
        var corrected = _correctionPipeline?.Correct(cleaned, _settings) ?? cleaned;

        _logger?.Transcript(corrected);
```

Then change the paste line from `_pasteService.Paste(cleaned)` to `_pasteService.Paste(corrected)`. (Leave the earlier `_logger?.Transcribed(transcribeDuration, cleaned.Length)` untouched — it reports the pre-correction length, which is fine.) Remove the old standalone `_logger?.Transcript(cleaned);` line so the transcript is logged exactly once, post-correction.

- [ ] **Step 5: Run the full suite**

Run: `dotnet test SpeakType.Tests`
Expected: PASS — the two new tests plus all 179 existing (181 total). The shared `_sut` (built without `correctionPipeline`) stays passthrough, so nothing regresses.

- [ ] **Step 6: Wire the real pipeline in the composition root**

In `SpeakType.App/Program.cs`, add `using SpeakType.Core.Correction;`, then just before the `var orchestrator = new DictationOrchestrator(...)` call (line ~151) build the pipeline:

```csharp
        var correctionPipeline = new TextCorrectionPipeline(
            new (ITextCorrector, Func<AppSettings, bool>)[]
            {
                (new SymSpellCorrector(), s => s.SpellCorrection),
            });
```

and pass it as a trailing arg:

```csharp
        var orchestrator = new DictationOrchestrator(
            hotkey, capture, swappable, pasteService, new TranscriptCleaner(), settings,
            new SystemClock(), autoStopTimer, dispatcher, logger, correctionPipeline);
```

- [ ] **Step 7: Build the app to confirm composition compiles**

Run: `dotnet build SpeakType.App`
Expected: build succeeds (the embedded dictionary resolves; `SymSpellCorrector` constructs). Full app run is Windows-only and covered by brick 0d's manual verify.

- [ ] **Step 8: Commit**

```bash
git add SpeakType.Core/Settings/AppSettings.cs \
        SpeakType.Core/Orchestration/DictationOrchestrator.cs \
        SpeakType.App/Program.cs \
        SpeakType.Tests/Orchestration/DictationOrchestratorTests.cs
git commit -m "feat(correction): run correction pipeline in orchestrator + SpellCorrection setting (brick 0c)"
```

---

## Task 4 (Brick 0d): Settings-form checkbox

**Skill:** `dotnet-best-practices`, `run-tests` (Windows-only UI — verify by hand)

**Files:**
- Modify: `SpeakType.App/Settings/SettingsForm.cs`

- [ ] **Step 1: Add the toggle row**

In `SpeakType.App/Settings/SettingsForm.cs`, next to the `FillerRemoval` row (line ~66), add:

```csharp
        AddRow(layout, "Spelling correction", MakeToggle(_settings.SpellCorrection, v => _settings.SpellCorrection = v));
```

(`MakeToggle` already persists via `_store.Save(_settings)` on change — same pattern as the other toggles.)

- [ ] **Step 2: Build**

Run: `dotnet build SpeakType.App`
Expected: build succeeds.

- [ ] **Step 3: Manual verification (Windows / laptop)**

Per `TESTING.md` (M-series): open Settings, confirm the **"Spelling correction"** toggle shows (default ON), toggle it off and back, and confirm `%APPDATA%\SpeakType\settings.json` gains `"spellCorrection": false`/`true`. Dictate a sentence with a clear typo-prone word and confirm correction applies when ON and not when OFF. Screenshot the Settings row.

- [ ] **Step 4: Commit**

```bash
git add SpeakType.App/Settings/SettingsForm.cs
git commit -m "feat(correction): add Spelling correction toggle to Settings (brick 0d)"
```

---

## After all tasks

- Update `BRICKS.md` per CLAUDE.md §2b: add a `Done` entry for each brick (newest first), remove them from `Next up`, archive if `Done` exceeds 3. Add a `Next up` pointer to **sub-project 1 (ONNX Runtime foundation)** with this plan's spec as the parent.
- Run `/code-review` and `/simplify` on the branch per the project's brick loop before merge.

## Self-Review notes

- **Spec coverage:** §2 architecture → Task 1; §3 SymSpell rules → Task 2; §4 settings → Task 3 (field) + Task 4 (UI); §6 fail-open/empty/trailing-space → Task 2 tests + `Correct` try/catch; placement after `TranscriptCleaner` → Task 3 Step 4. ✓
- **Type consistency:** `ITextCorrector.Correct(string)`, `TextCorrectionPipeline.Correct(string, AppSettings)`, ctor param `correctionPipeline`, field `_correctionPipeline`, setting `SpellCorrection` — used identically across Tasks 1, 3, 4. ✓
- **Known deferrals (intentional, not placeholders):** `FrequencyFloor` exact value is tuned in Task 2 Step 5 against the real dictionary; `[A-Za-z]+` tokenization splits contractions (their parts are ≤2 chars and skipped) — acceptable for v1, recorded in spec.
