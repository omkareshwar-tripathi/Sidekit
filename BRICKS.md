# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### Core (no OS dependencies — fully unit-testable)

- [ ] **Brick 0b — Continuous integration (the safety net).** GitHub Actions workflow on `windows-latest` (real x64): restore, build the whole solution, run `dotnet test` on every push/PR. This is what catches Windows-only breakage you can't see on the Mac. (Gate the slow Whisper integration test to a separate/optional job.)
  - Skill: dotnet-best-practices, run-tests
  - Verify: push a branch → the Actions run goes green; intentionally break a Windows-only build line → CI goes red (then revert).
  - **Watch (from Brick 0 review):** `TreatWarningsAsErrors=true` is solution-wide (`Directory.Build.props`). The first time real WinForms code lands (Brick 9/10), generated designer/`ApplicationConfiguration` partials could surface a warning-as-error that only shows on Windows. This CI run is where it'll first appear — if red on a generated-code warning, scope `TreatWarningsAsErrors` off generated files rather than disabling it.

- [ ] **Brick 1 — Settings model + JSON store (`ISettingsStore`).** POCO settings (hotkey, modelSize, fillerRemoval, overlay, autostart, debugLogging) with defaults; load/save `%APPDATA%\SpeakType\settings.json`; tolerate missing/partial file.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify (unit): round-trip serialize/deserialize; missing file → defaults; partial file → defaults fill gaps; invalid hotkey rejected.

- [ ] **Brick 2 — Cleanup pipeline (pure).** Composable stages: filler removal (safe set + comma-bounded phrases; NOT like/actually/etc.), fixups (spacing/commas/`I`), formatting (trim + trailing space), hallucination filter (empty / `[BLANK_AUDIO]` / short-clip `you`/`Thank you.`). Filler stage toggleable.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests
  - Verify (unit, table-driven `[Theory]`): the corpus from spec Feature 4 (e.g. `"Um, I think, you know, we should ship it."` → `"I think we should ship it. "`; `"I mean it."` kept; `"i like pizza"` → `"I like pizza "`; toggle OFF retains fillers; hallucinations → empty).

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

## Done

_(Newest first.)_

### Brick 0 — Project scaffold (cross-platform split) (2026-06-02)
- **What:** Three-project .NET 8 solution. `SpeakType.Core` (`net8.0`, holds `AppInfo.Name`), `SpeakType.App` (`net8.0-windows` WinForms, `AssemblyName=SpeakType`, minimal `Main` — no UI yet), `SpeakType.Tests` (xUnit, refs Core) with one smoke test. Root `Directory.Build.props` (shared `Nullable`/`ImplicitUsings`/`LangVersion`/`TreatWarningsAsErrors`) + `SpeakType.sln`. Self-contained single-file `win-x64` publish profile on the App.
- **Files:** `SpeakType.sln`, `Directory.Build.props`, `SpeakType.Core/{SpeakType.Core.csproj,AppInfo.cs}`, `SpeakType.App/{SpeakType.App.csproj,Program.cs,Properties/PublishProfiles/win-x64.pubxml}`, `SpeakType.Tests/{SpeakType.Tests.csproj,AppInfoTests.cs,GlobalUsings.cs}`.
- **Verified (on Mac):** `dotnet build SpeakType.Core` → 0 errors; `dotnet test SpeakType.Tests/SpeakType.Tests.csproj` → 1/1 passing; `dotnet build SpeakType.App` → fails **only** with the expected `MSB4019` (Windows-Desktop SDK absent on macOS), proving the split. **App build/run on Windows is NOT yet verified** — deferred to Brick 0b CI / the Windows laptop. (No tray UI exists yet — that's Brick 9; the earlier "empty tray icon" verify wording was wrong for a scaffold and is corrected here.)
- **Notes / decisions:**
  - **Mac test command targets the Tests project, not the solution** (`dotnet test SpeakType.Tests/SpeakType.Tests.csproj`). `dotnet build/test SpeakType.sln` fails on Mac because it pulls in the Windows-only App. Use the project-scoped command locally; CI/Windows builds the whole `.sln`.
  - **x64 is achieved via the `win-x64` publish RID, not an MSBuild `Platform`.** Brick-0 review flagged that a `<Platforms>x64</Platforms>` on the App forced a fragile hand-edited `Any CPU→x64` remap in the `.sln`. Removed it; App now builds `Any CPU` (uniform `.sln`) and ships x64 via `RuntimeIdentifier=win-x64` in the pubxml. Simpler and still spec-compliant.
  - Simplify pass removed duplicated `ImplicitUsings`/`Nullable` from the test csproj and a redundant `using Xunit;` (uses the template's `global using`).
  - **Follow-up (Brick 15 packaging):** when NAudio/Whisper native libs arrive, the single-file publish will need `<IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>`.
  - The hand-authored `.sln` App entry (GUID `C7A2E1F4-…`) could not be CLI-validated on macOS; it's now standard `Any CPU` mappings, but Brick 0b CI is the first real proof the full solution builds on Windows.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
