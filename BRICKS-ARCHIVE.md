# BRICKS-ARCHIVE.md

Append-only archive of completed bricks, moved out of `BRICKS.md` to keep the active handoff file small (see `CLAUDE.md` §2b). Newest-first. Rarely read — the active `BRICKS.md` always holds the last 3 completed bricks plus all pending ones.

---

### Brick 1 — Settings model + JSON store (2026-06-02)
- **What:** `AppSettings` POCO (hotkey, modelSize, fillerRemoval, overlay, autostart, debugLogging) with spec defaults (RightCtrl / base.en / on / on / on / off), an `ISettingsStore` port, and `JsonSettingsStore` (System.Text.Json, camelCase keys) reading/writing `%APPDATA%\SpeakType\settings.json` (path is constructor-injected for testability; `DefaultFilePath` static for the real location). Robust load: missing file, partial file, corrupt JSON, and blank/explicit-null string fields all fall back to defaults via `AppSettings.Normalize()`.
- **Files:** `SpeakType.Core/Settings/{AppSettings.cs, ISettingsStore.cs, JsonSettingsStore.cs}`, `SpeakType.Tests/Settings/JsonSettingsStoreTests.cs`.
- **Verified (on Mac):** `dotnet test SpeakType.Tests/...` → **10/10 pass** — round-trip (non-default values through disk), missing→defaults, partial→defaults, corrupt→defaults, literal-`null`→defaults, blank/explicit-null hotkey & modelSize→defaults, Save-creates-dir, camelCase keys (all six, no PascalCase leak). No manual M# (pure logic). CI on Windows covers it too.
- **Notes / decisions:**
  - **Normalization lives on the model (`AppSettings.Normalize()`), not in the store** — review flagged that putting it in `JsonSettingsStore.Load()` duplicated the default and coupled the port to field semantics (any future store impl would have to re-implement it). Single-source defaults via `DefaultHotkey`/`DefaultModelSize` consts.
  - **Boundary:** "invalid hotkey rejected" here means **blank/null → default only**. Full hotkey-grammar validation (which keys/combos are legal) is **Brick 4** (the hotkey listener). Don't duplicate it here.
  - Code review caught a real latent NRE: an explicit JSON `null` on a non-nullable string (e.g. `{ "modelSize": null }`) would survive deserialization as null; `Normalize()` now coerces it, with tests.
  - **Possible later hardening (not done, §2):** `Save()` is a non-atomic `File.WriteAllText`; a crash mid-write yields a corrupt file (which `Load()` already degrades to defaults). A temp-file+rename swap would make it atomic — revisit if corruption is ever observed, since settings are rewritten on every change (apply-on-change).

---

### Brick 0b — Continuous integration (2026-06-02)
- **What:** GitHub Actions CI (`.github/workflows/ci.yml`) on `windows-latest` (real x64): checkout → setup .NET 8 → restore → build the full solution → test, on every push/PR to `main`. Has a `concurrency` group to cancel superseded runs.
- **Files:** `.github/workflows/ci.yml`.
- **Verified:** pushed to `main`; the run went **green in ~1m24s** (run 26778664115). The **Build step passing is the first real proof the `net8.0-windows` App compiles on Windows x64** — it retroactively validates Brick 0's deferred App build. Test step ran the smoke test green.
- **Notes / follow-ups:**
  - Test step filters `Category!=Integration` so the on-device Whisper test (Brick 7) is already excluded from the fast job; Brick 7 adds its own optional integration job.
  - **Dated follow-up — by 2026-06-16:** GitHub deprecates Node 20 actions; `actions/checkout@v4` and `actions/setup-dotnet@v4` will be forced to Node 24 (may break). Bump to the Node-24 major versions before then (verify the tags exist first).
  - The Brick 0 "warnings-as-errors on WinForms generated code" watch-point now lives with this CI run — it'll surface here first when Brick 9/10 lands real WinForms code.

---

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
