# BRICKS-ARCHIVE.md

Append-only archive of completed bricks, moved out of `BRICKS.md` to keep the active handoff file small (see `CLAUDE.md` §2b). Newest-first. Rarely read — the active `BRICKS.md` always holds the last 3 completed bricks plus all pending ones.

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
