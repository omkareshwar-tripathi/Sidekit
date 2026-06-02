# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### Adapters (real OS integration — thin, manual-verified)

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
  - **Provide the real `IClock` (Stopwatch-backed) and `IAutoStopTimer` (`System.Threading.Timer`, one-shot via `Timeout.Infinite` period) adapters** (deferred from Brick 3b — no real impls exist yet).
  - **Own the threading model.** The orchestrator is synchronous in v1; the real auto-stop timer fires `OnAutoStop` on a thread-pool thread, so its `State` guard + `_pressTimestamp` are **not thread-safe** today. A release racing the 60 s fire could double-run the cycle. Marshal hotkey + timer callbacks onto one thread (or lock) here, and offload the capture→transcribe→paste work off the UI thread.
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

### Brick 5 — Audio capture adapter + silence gate (2026-06-02)
- **What:** The microphone half of the pipeline. `NAudioCapture` (Windows-only, `SpeakType.App`) implements `IAudioCapture` over NAudio's `WaveInEvent`: it records mono 16-bit PCM at the device's native 44.1 kHz, accumulates the chunks (the `DataAvailable` callback appends under a lock since it runs on an NAudio background thread), and on `Stop()` converts → resamples → gates the buffer into a `CapturedAudio`. No microphone present → `Start()` throws `InvalidOperationException` (the orchestrator's press-path try/catch already resets state; the user-facing balloon is Brick 9). The actual signal processing lives in the pure, Mac-tested `AudioMath` (Core): `Pcm16ToFloat` (little-endian 16-bit → float[-1,1]), linear-interpolation `Resample` to 16 kHz, and an RMS `HasSpeech` silence gate, with tunable `DefaultRmsThreshold` (0.01) and `TargetSampleRate` (16000) consts.
- **Files:** `SpeakType.Core/Audio/AudioMath.cs` (new); `SpeakType.App/Audio/NAudioCapture.cs` (new, Windows-only); `SpeakType.App/SpeakType.App.csproj` (added `NAudio 2.2.1` PackageReference); tests `SpeakType.Tests/Audio/AudioMathTests.cs` (new).
- **Verified:** Core part on Mac → `dotnet test SpeakType.Tests/...` **98/98 pass** (14 new AudioMath tests: PCM decode incl. the negative-max `0x00 0x80`→-1.0 sign case, RMS gate silent→false / speech-level sine→true / empty→false, resample same-rate/empty/up/down with endpoint preservation). App part is **Windows-only — cannot build on Mac**; the Windows x64 **CI build is the compile gate** (green: run 26819123900, NAudio 2.2.1 restored). **Manual M3 deferred to the laptop** (real mic → speech-level audio proceeds, silence is gated).
- **Notes / decisions:**
  - **Resample in-app, not via NAudio** — the spec's "resample on a known tone" unit test wants a testable resampler, and Core takes zero external NuGet deps, so resampling is a pure Core function (linear interpolation), not NAudio's Windows-only resampler. The adapter requests mono 16-bit so no channel down-mix is needed (skipped as YAGNI; the device is forced to mono).
  - **NAudio API verified against the v2.2.1 source** (code review) since it can't compile on Mac — `WaveInEvent`, `DataAvailable`/`WaveInEventArgs`, `StartRecording`/`StopRecording`, `static DeviceCount` all confirmed; `List<byte>.AddRange(ReadOnlySpan<byte>)` is a real .NET 8 overload.
  - **Code review confirmed no must-fix**; applied two /simplify nits: pre-size `_buffer` to ~1 s to avoid repeated reallocation during capture, and an inline note on `Resample`'s documented same-rate by-reference return (callers treat it read-only).
  - **Deferred to Brick 14:** a final in-flight `DataAvailable` can fire after `Stop()` snapshots the buffer (its samples are harmlessly dropped); precise flush + the capture→transcribe threading is Brick 14's job. Device is hardcoded to default (#0) — v1 scope.

### Brick 4b — Win32 hotkey hook adapter + settings hotkey resolution (2026-06-02)
- **What:** The real OS binding for push-to-talk. `Win32HotkeyListener` (Windows-only, `SpeakType.App`) installs a `WH_KEYBOARD_LL` low-level keyboard hook implementing `IHotkeyListener`: it tracks held modifiers, raises `Pressed` when the bound trigger goes down with every required modifier satisfied (unsided Ctrl/Alt/Shift match either side), raises `Released` on trigger-up, and **suppresses the bound trigger key — first press and every auto-repeat — while held** so it never leaks into the focused app. `Rebind(Hotkey)` swaps the binding live (hook stays installed); `Pause()`/`Resume()` stop reacting for the session (not persisted). `KeyCodes` is the pure VK lookup (bare modifiers, F1–F24, Pause, named keys, A–Z, 0–9). Also adds the Core seam `Hotkey.Resolve(persisted, fallback)` — turns a stored settings string into a valid binding, falling back to the default when it's null/blank/invalid (the settings-validation follow-up from Brick 4a; `AppSettings.Normalize()` only null-guards).
- **Files:** `SpeakType.App/Input/Win32HotkeyListener.cs`, `SpeakType.App/Input/KeyCodes.cs` (new, Windows-only); `SpeakType.Core/Input/Hotkey.cs` (added `Resolve`); `SpeakType.App/SpeakType.App.csproj` (added `AllowUnsafeBlocks`); tests `SpeakType.Tests/Input/HotkeyResolveTests.cs` (new).
- **Verified:** Core part (`Hotkey.Resolve`) on Mac → `dotnet test SpeakType.Tests/...` **84/84 pass** (6 new resolve cases: valid persisted, invalid/null/blank → fallback, invalid fallback → throws). App part is **Windows-only — cannot build on Mac**; the Windows x64 **CI build is the compile gate** (green: run 26818625307). **Manual M1 deferred to the laptop** (hold Right Ctrl → dictation; quick tap → nothing; rebind to Ctrl+Space; bind "E" → rejected) — needs the Brick 14 wiring to dictate end-to-end.
- **Notes / decisions:**
  - **Code review caught two real issues (fixed) + CI caught a third:** (1) auto-repeat trigger key-downs were leaking into the focused app for combo triggers (e.g. Ctrl+Space would stream repeated Space into the document during a long hold) — now the trigger-down is suppressed on the first press *and* every repeat while held; (2) the hook callback marshalled the whole `KBDLLHOOKSTRUCT` on every system-wide keystroke when only `vkCode` (offset 0) is needed → now a single `Marshal.ReadInt32`; (3) **CI build failure**: `[LibraryImport]` source-generated P/Invoke emits unsafe code (SYSLIB1062/CS0227), so the App project needed `<AllowUnsafeBlocks>true</AllowUnsafeBlocks>` — added (scoped to App; Core/Tests stay safe-only).
  - **`[LibraryImport]` vs `[DllImport]`:** used source-generated `[LibraryImport]` for the simple imports (avoids SYSLIB1054 under `TreatWarningsAsErrors`); `SetWindowsHookEx` takes a managed delegate the generator can't marshal (SYSLIB1051), so it stays `[DllImport]` with a local `#pragma warning disable SYSLIB1054`.
  - **Suppress only the trigger, never standalone modifiers** — for `Ctrl+Space` the Ctrl modifier still reaches the app (it's a normal modifier the user pressed); only Space is swallowed. Suppression keys off `_active`, which `Pause`/`Rebind`/`Dispose` clear mid-hold — so **`Released` is NOT guaranteed after `Pressed`** if a hold is interrupted; documented on those methods for the Brick 14 consumer to treat as a cancel.
  - **Deferred to Brick 14 (noted there):** the hook callback and `Pause`/`Rebind` touch shared mutable state with no synchronization — fine only while they run on the single hook/UI thread; Brick 14 owns the threading model and must construct the listener on a message-pump thread.

### Brick 4a — Hotkey model + parse/validate (pure) (2026-06-02)
- **What:** The pure, OS-agnostic hotkey parser/validator (spec Feature 1 "Rebinding"; the unit-test deliverable). `Hotkey.TryParse(string?, out Hotkey?, out string? error)` turns a string like `"RightCtrl"`, `"Ctrl+Space"`, `"F13"` into a validated `Hotkey(HotkeyModifiers Modifiers, string TriggerKey)`, or returns false with a user-facing message. **Allows** bare modifiers, bare F13–F24, bare Pause/Break, and any modifier+key combo; **rejects** bare letters/digits, bare F1–F12, bare other named keys, modifier-only combos, two main keys, and empty/unknown tokens. `ToString()` gives a canonical round-trippable form. Win32 virtual-key mapping is deliberately **not** here — that's the Brick 4b adapter (Core stays dependency-free).
- **Files:** `SpeakType.Core/Input/Hotkey.cs` (new); tests `SpeakType.Tests/Input/HotkeyTests.cs` (new).
- **Verified (on Mac):** `dotnet test SpeakType.Tests/...` → **78/78 pass** (26 new: accept matrix incl. case-insensitive + `Alt+5`/`Ctrl+Shift+F1`, reject matrix incl. bare `E`/`5`/`F1`/`Space`/`Ctrl+Shift`/`Ctrl+A+B`/`Ctrl+`/`Ctrl+Foo`/null, and ToString round-trip). Critically, the `AppSettings` default `"RightCtrl"` parses. Pure logic → no manual M# (the hook's M1 is Brick 4b). CI on Windows covers it too.
- **Notes / decisions:**
  - **Brick 4 was split (4a + 4b)** by both §2a sizing and platform routing: the pure parser (here, Mac-verified) vs the Windows-only `WH_KEYBOARD_LL` hook (4b, App). Same seam as Brick 3.
  - **`TriggerKey` is a `string`, not an enum** (altitude-reviewed): keeps Core OS-agnostic and lets the 4b adapter own the single VK lookup table; an enum would force Core to enumerate every key and need a serialization shim for the string-typed `AppSettings.Hotkey`.
  - **Simplify pass:** merged the duplicate letter/digit branches into one `char.IsAscii*` check (dropped the regex + the duplicated error literal), renamed `Modifiers_`→`ModifierAliases`, replaced an unused `List` with a single field, and trimmed speculative modifier alias short-forms (kept canonical spellings + `control`). Kept the full `NamedKeys` table — the spec's "any modifier + key combo" makes `Ctrl+Enter` etc. valid, so trimming would wrongly reject them.
  - **Deliberate leniencies (documented, per spec interpretation; not bugs):** bare unsided `Ctrl`/`Alt` are accepted (spec enumerates sided, but this mirrors the spec's own unsided bare `Shift`; 4b maps unsided→either side); duplicate modifiers collapse idempotently; `Shift+E` is accepted (it *is* "modifier + key"); the literal `+` key can't be bound (`+` is the separator) and yields an "empty key" message. The Settings UI (Brick 11) uses key-capture, not free text, so these edge spellings are unlikely in practice.
  - **Follow-up recorded on Brick 4b:** `AppSettings.Normalize()` doesn't run `TryParse`, so a hand-edited invalid hotkey survives settings load — wire validation+fallback where the setting becomes a real binding.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
