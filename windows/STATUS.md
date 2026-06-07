# Windows app — STATUS (parked)

**State: dormant / parked.** We are building the **Mac app first** (`SpeakTypeMac/`), to a meaningful slice of the vision. The Windows app resumes **after the Mac app launches** — then we replicate the polished Mac experience here and bring it to parity.

> ⚠️ **The files in this `windows/` folder are a pre-split BASELINE** of the C#/.NET app — the copy that happened to live on the `feat/mac-app` branch. **It is not the latest Windows work.** When you resume Windows, start from the branches below, not from this baseline.

## Where the live Windows work actually is (git branches)

- **`chore/windows-folder`** — the .NET solution already reorganized into `windows/` (the clean folder layout). Base: current `main`.
- **`feat/correction-pipeline`** — the first stage of the text-correction pipeline, on the Windows side:
  - `ITextCorrector` port + `TextCorrectionPipeline` (staged-correction scaffold)
  - **`SymSpellCorrector`** — SymSpell typo correction + an 82,765-word frequency dictionary
  - wired into the Windows `DictationOrchestrator`, plus a **"Spelling correction"** toggle in Settings
  - full unit tests + the `docs/.../2026-06-03-fix-polish-correction-pipeline` spec & plan

These branches are pushed to `origin` and are safe; nothing here is lost.

## Resume plan (after Mac launch)

1. Start from `main` consolidated with `chore/windows-folder` (windows/ layout) + `feat/correction-pipeline` (correction work).
2. **Replicate the Mac UX to parity** — floating pill, scratchpad/notes, dictation **History trail**, settings sheet, push-to-talk, and the **honest paste status** ("Copied to clipboard" when no editable field is focused). See `SpeakTypeMac/` for the reference behavior and `BRICKS.md` for the brick history.
3. Continue the text-correction pipeline beyond SymSpell (→ CNN-BiLSTM punctuation/casing → GECToR grammar), per `vision/text-correction-pipeline.md`.
4. Consolidate everything onto `main` once Windows reaches the target slice.

## Why parked, not deleted
The design is still settling on Mac (paste behavior, the History trail, toolbar all changed recently). Replicating mid-flux means building twice. Stabilize on Mac → port a proven design.
