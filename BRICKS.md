# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### Core (no OS dependencies — fully unit-testable)

- [ ] **Brick 3 — Orchestrator state machine.** Define the ports (`IHotkeyListener`, `IAudioCapture`, `ITranscriber`, `IModelStore`, `IClipboard`/`IPasteService`). Implement the `Idle→Recording→Transcribing→Pasting→Idle` orchestrator wiring capture→transcribe→cleanup→paste, with hold guards (<300 ms discard, 60 s auto-stop) and busy = ignore. Inject a fake clock.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify (unit, all fakes): normal flow pastes cleaned text; <300 ms hold discards; 60 s auto-stops; press during non-Idle ignored; silence-gate skip path; no-target → leave-on-clipboard path.

### Adapters (real OS integration — thin, manual-verified)

- [ ] **Brick 4 — Hotkey adapter (`IHotkeyListener`).** `WH_KEYBOARD_LL` low-level hook; default Right Ctrl; suppress bound key while held; hotkey string parse/validate (allow safe keys + combos, reject bare letters/digits); live re-register on rebind.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — parse/validate accept/reject cases. Manual — **M1**.

- [ ] **Brick 5 — Audio capture adapter (`IAudioCapture`) + silence gate.** NAudio capture from Windows default device; resample to 16 kHz mono float; RMS silence gate; no-mic → abort + balloon signal.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — silence gate on synthetic buffers (silent → skip, speech-level → proceed); resample on a known tone. Manual — **M3**.

- [ ] **Brick 6 — Model store (`IModelStore`).** Resolve `%LOCALAPPDATA%\SpeakType\models`; download a chosen ggml `.en` model with progress; verify size + checksum; retry on failure; re-download on corrupt-on-load; keep prior model active during a switch.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — verification passes valid / fails truncated; keep-old-on-failed-switch logic (fakes/temp dir). Manual — **M2** (download + switch + failure).

- [ ] **Brick 7 — Whisper transcriber (`ITranscriber`).** Whisper.NET adapter; `language="en"`; threads = `max(1, cpu-1)`; runs on a background thread; takes a model path from the model store.
  - Skill: dotnet-best-practices, run-tests
  - Verify: integration (gated/slow) — real Whisper on `test-assets/hello.wav` asserts transcript contains "hello world" (fixture provides tiny.en locally; skip if model/offline). Note: no skill for local Whisper — work against Whisper.NET docs.

- [ ] **Brick 8 — Clipboard-safe paste (`IClipboard`/`IPasteService`).** Save (text only) → set our text → `SendInput` Ctrl+V → ~150 ms delay → restore. Best-effort editable-target detection; if unsure, skip restore and leave our text on the clipboard.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — save/restore and leave-on-clipboard branch (fake clipboard); restore-after-delay ordering. Manual — **M4**.

### App shell, UI & polish

- [ ] **Brick 9 — Tray app + lifecycle.** `NotifyIcon` with Idle/Recording/Busy/Error icons; menu (Settings…, Pause, Start with Windows, About, Quit); single-instance mutex `SpeakType.Single`; global exception handlers (log + balloon + recover to Idle). Wire Pause (session-only) and tray state to the orchestrator.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M5**, **M7**.

- [ ] **Brick 10 — Recording overlay.** No-activate, click-through, always-on-top window at bottom-center of the active monitor; states 🎙 Listening / ⚙ Transcribing / "No speech detected" / "Copied — paste manually"; fade out; overlay on/off setting. Must never steal focus.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M5** (focus not stolen; overlay shows/hides per state).

- [ ] **Brick 11 — Settings window.** WinForms form: hotkey rebind, model dropdown, Remove-filler toggle, overlay toggle, Start-with-Windows toggle, Debug-logging toggle. Apply-on-change → `ISettingsStore`; hotkey rebind re-registers hook; model change triggers store download/switch.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M6**.

- [ ] **Brick 12 — First-run + autostart.** Welcome window (how-to + `base.en` download progress; hotkey inert until ready → "Ready!" balloon); `HKCU\…\Run` autostart (default ON), toggled from tray/Settings.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M2** (first-run), **M6** (autostart registry key add/remove).

- [ ] **Brick 13 — Logging + performance timing.** Rolling log at `%APPDATA%\SpeakType\logs`; metadata + timings only by default; transcript text only when Debug logging on; log release→paste latency each run.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify: unit — log line formatting; transcript absent by default, present when debug on. Manual — latency line appears, observe vs <2 s goal.

### Integration & ship

- [ ] **Brick 14 — End-to-end wiring.** Compose the real adapters into the orchestrator behind composition root; full dictation works in a real app.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M1** end-to-end + **M8** (full happy path across Notepad/Slack/browser).

- [ ] **Brick 15 — Packaging.** Finalize self-contained single-file `win-x64` publish; confirm it runs on a clean machine (first-run download + autostart). Document SmartScreen-warning expectation.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — copy `.exe` to a clean profile/VM, launch → Welcome → download → dictation works.

### Backlog (optional — needs a user decision, not in the v1 critical path)

- [ ] **Cleanup-pipeline real-world hardening (revealed by Brick 2 review).** Decide whether to: (a) trim the always-filler list so it stops eating real tokens — `mm` (millimeter), `er` (ER), and possibly `ah` collide with genuine words/units; (b) make `i`→`I` skip abbreviation/list contexts like `i.e.` / `Section i` / `for i`; (c) fix the two niche defects — stacked leading fillers losing capitalization (`"Um er,"`) and hyphen-joined clusters (`"Mm-hmm."`). All three currently behave per spec lines 121/129; changing them is a spec decision, hence parked here rather than done autonomously.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests

## Done

_(Newest first. Older entries archived to `BRICKS-ARCHIVE.md`.)_

### Brick 2 — Cleanup pipeline (pure) (2026-06-02)
- **What:** `TranscriptCleaner.Clean(string? raw, bool removeFillers = true)` — turns a raw Whisper transcript into paste-ready text. Ordered stages in one class: (1) filler removal (toggleable) — always-words `um/uh/er/ah/hmm/mm` stripped even bare, phrase markers `you know/I mean/sort of/kind of` stripped only when comma-bounded or at a sentence boundary (so real uses survive); (2) always-on fixups — collapse comma/space debris, capitalize standalone `i`→`I`; (3) trim + single trailing space (no forced terminal punctuation); (4) hallucination/empty filter → returns `""` for empty, `[BLANK_AUDIO]`, and whole-output `you`/`Thank you.`.
- **Files:** `SpeakType.Core/Cleanup/TranscriptCleaner.cs`, `SpeakType.Tests/Cleanup/TranscriptCleanerTests.cs`.
- **Verified (on Mac):** `dotnet test SpeakType.Tests/...` → **38/38 pass**. Corpus covers the spec Feature-4 cases (filler ON, filler OFF still runs fixups, hallucinations→empty) plus a `Clean_guards_each_filler_pass` theory added during review to exercise the previously-untested passes: `sort of`/`kind of` *removal*, multi-sentence fillers after a period, filler-before-terminator, leading-filler-before-digit, stacked bare fillers. Pure logic → no manual M#. CI on Windows covers it too.
- **Notes / decisions:**
  - **No `ICleanupStage` interface / per-stage files in v1.** The spec's "composable, individually addressable stages" is forward-looking (for the Phase-2 LLM rewrite stage). v1 implements stages as ordered private methods in one class (`RemoveFillers` / `Fixups` + the filter) — a future stage slots in as another method off `Clean`. Avoids speculative abstraction (§2) and the 5-file ceiling.
  - **Simplify pass:** dropped `RegexOptions.Compiled` (net-negative JIT cost for a run-once-per-utterance path), tidied `[,]?`→`,?`, and split the hallucination list into named `Sentinels` (`[BLANK_AUDIO]`) vs `SilencePhrases` (`you`/`Thank you.`) so the membership rule is explicit, not accretive.
  - **Code review — confirmed real-world edge cases that are NOT code defects but spec-level tradeoffs (left as the spec dictates; flagged for the user, see follow-up below):** the always-filler list deletes real standalone tokens — `mm` (millimeter: "5 mm wide" → "5 wide"), `er` (ER), `ah` — because spec line 121 declares them "never real words"; and `\bi\b`→`I` (spec line 129) over-capitalizes `i.e.` / `for i` / `Section i`. These are the spec author's documented decisions; I did **not** silently override them mid-ship.
  - **Known niche defects (no spec answer; documented, not fixed):** two stacked *leading* always-fillers with a comma drop the re-capitalization (`"Um er, it works."` → `"it works. "`); a hyphen-joined cluster leaves debris (`"Mm-hmm."` → `"-hmm. "`). Rare Whisper outputs; fixing needs invented behavior or added pass complexity — deferred to the follow-up.

### Brick 1 — Settings model + JSON store (2026-06-02)
- **What:** `AppSettings` POCO (hotkey, modelSize, fillerRemoval, overlay, autostart, debugLogging) with spec defaults (RightCtrl / base.en / on / on / on / off), an `ISettingsStore` port, and `JsonSettingsStore` (System.Text.Json, camelCase keys) reading/writing `%APPDATA%\SpeakType\settings.json` (path is constructor-injected for testability; `DefaultFilePath` static for the real location). Robust load: missing file, partial file, corrupt JSON, and blank/explicit-null string fields all fall back to defaults via `AppSettings.Normalize()`.
- **Files:** `SpeakType.Core/Settings/{AppSettings.cs, ISettingsStore.cs, JsonSettingsStore.cs}`, `SpeakType.Tests/Settings/JsonSettingsStoreTests.cs`.
- **Verified (on Mac):** `dotnet test SpeakType.Tests/...` → **10/10 pass** — round-trip (non-default values through disk), missing→defaults, partial→defaults, corrupt→defaults, literal-`null`→defaults, blank/explicit-null hotkey & modelSize→defaults, Save-creates-dir, camelCase keys (all six, no PascalCase leak). No manual M# (pure logic). CI on Windows covers it too.
- **Notes / decisions:**
  - **Normalization lives on the model (`AppSettings.Normalize()`), not in the store** — review flagged that putting it in `JsonSettingsStore.Load()` duplicated the default and coupled the port to field semantics (any future store impl would have to re-implement it). Single-source defaults via `DefaultHotkey`/`DefaultModelSize` consts.
  - **Boundary:** "invalid hotkey rejected" here means **blank/null → default only**. Full hotkey-grammar validation (which keys/combos are legal) is **Brick 4** (the hotkey listener). Don't duplicate it here.
  - Code review caught a real latent NRE: an explicit JSON `null` on a non-nullable string (e.g. `{ "modelSize": null }`) would survive deserialization as null; `Normalize()` now coerces it, with tests.
  - **Possible later hardening (not done, §2):** `Save()` is a non-atomic `File.WriteAllText`; a crash mid-write yields a corrupt file (which `Load()` already degrades to defaults). A temp-file+rename swap would make it atomic — revisit if corruption is ever observed, since settings are rewritten on every change (apply-on-change).

### Brick 0b — Continuous integration (2026-06-02)
- **What:** GitHub Actions CI (`.github/workflows/ci.yml`) on `windows-latest` (real x64): checkout → setup .NET 8 → restore → build the full solution → test, on every push/PR to `main`. Has a `concurrency` group to cancel superseded runs.
- **Files:** `.github/workflows/ci.yml`.
- **Verified:** pushed to `main`; the run went **green in ~1m24s** (run 26778664115). The **Build step passing is the first real proof the `net8.0-windows` App compiles on Windows x64** — it retroactively validates Brick 0's deferred App build. Test step ran the smoke test green.
- **Notes / follow-ups:**
  - Test step filters `Category!=Integration` so the on-device Whisper test (Brick 7) is already excluded from the fast job; Brick 7 adds its own optional integration job.
  - **Dated follow-up — by 2026-06-16:** GitHub deprecates Node 20 actions; `actions/checkout@v4` and `actions/setup-dotnet@v4` will be forced to Node 24 (may break). Bump to the Node-24 major versions before then (verify the tags exist first).
  - The Brick 0 "warnings-as-errors on WinForms generated code" watch-point now lives with this CI run — it'll surface here first when Brick 9/10 lands real WinForms code.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
