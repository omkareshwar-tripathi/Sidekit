# BRICKS.md

Session handoff log. **Read this first when starting a session.** Update the moment a brick is reviewed + tested + verified. See `CLAUDE.md` §2b for rules (and archiving to `BRICKS-ARCHIVE.md`).

Plan derived from `SpeakType-v1-spec.md` (the complete, decision-resolved spec). Manual test IDs (`M1`–`M8`) refer to `TESTING.md`. Architecture is **ports-and-adapters**: the pure core (Bricks 1–4) is built and unit-tested with fakes *before* any OS adapter exists.

---

## Next up

_(Top item is what to work on now. Sized per CLAUDE.md §2a — split any brick that grows past ~150 LOC / 5 source files.)_

### Adapters (real OS integration — thin, manual-verified)

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
  - **`WhisperTranscriber.Transcribe` must run OFF the UI thread (Brick 7 review).** It bridges Whisper's async stream synchronously (`ToBlockingEnumerable`). Verified it will NOT deadlock (Whisper.net uses `ConfigureAwait(false)` + a thread-pool worker), but calling it inline on the WinForms UI thread **freezes the window** for the whole transcription. Wrap the cycle in `Task.Run`. Also: `WhisperTranscriber.Dispose()` throws if a transcription is still in flight — only dispose when idle (or switch to `DisposeAsync`), which the single-cycle + off-UI-thread design already ensures.
  - **Reference `Whisper.net.Runtime` from the App (Brick 7).** The `SpeakType.Whisper` adapter references only managed `Whisper.net`; the deployable app must add `Whisper.net.Runtime` (native libs) so Whisper actually runs — a packaging concern shared with Brick 15.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — **M1** end-to-end + **M8** (full happy path across Notepad/Slack/browser).

- [ ] **Brick 15 — Packaging.** Finalize self-contained single-file `win-x64` publish; confirm it runs on a clean machine (first-run download + autostart). Document SmartScreen-warning expectation.
  - Skill: dotnet-best-practices, run-tests
  - Verify: manual — copy `.exe` to a clean profile/VM, launch → Welcome → download → dictation works.

### Backlog (optional — needs a user decision, not in the v1 critical path)

- [ ] **Shared test temp-dir helper (revealed by Brick 6b review).** The temp-dir scaffolding (`_tempDir` field + ctor + `Dispose`) is now duplicated across `JsonSettingsStoreTests`, `ModelStoreTests`, and `HttpModelDownloaderTests` (rule-of-three met). Extract a tiny `TempDir`/`TempDirFixture` IDisposable helper and have the three classes use it (~12 lines saved each). Deferred from Brick 6b to keep that brick from editing already-shipped test files; do it as its own small test-only brick.
  - Skill: dotnet-xunit, run-tests

- [ ] **Cleanup-pipeline real-world hardening (revealed by Brick 2 review).** Decide whether to: (a) trim the always-filler list so it stops eating real tokens — `mm` (millimeter), `er` (ER), and possibly `ah` collide with genuine words/units; (b) make `i`→`I` skip abbreviation/list contexts like `i.e.` / `Section i` / `for i`; (c) fix the two niche defects — stacked leading fillers losing capitalization (`"Um er,"`) and hyphen-joined clusters (`"Mm-hmm."`). All three currently behave per spec lines 121/129; changing them is a spec decision, hence parked here rather than done autonomously.
  - Skill: dotnet-best-practices, dotnet-xunit, run-tests

## Done

_(Newest first. Older entries archived to `BRICKS-ARCHIVE.md`.)_

### Brick 7 — On-device Whisper transcriber (2026-06-02)
- **What:** The actual speech-to-text (spec Feature 2). New **cross-platform** `SpeakType.Whisper` project with `WhisperTranscriber : ITranscriber` over Whisper.NET: loads a ggml model once, then `Transcribe(float[] samples)` runs whisper.cpp with `language="en"` and `threads = max(1, cpu-1)` and returns the trimmed transcript (bridges Whisper's async stream via `ToBlockingEnumerable`). The adapter references only the **managed** `Whisper.net` so `Core` stays dependency-free and the engine runs on macOS/Windows/Linux. Whisper.NET was validated on this Mac (Metal-accelerated) before building — see the spike notes below.
- **Files:** `SpeakType.Whisper/{SpeakType.Whisper.csproj, WhisperTranscriber.cs}` (new); `SpeakType.Whisper.Tests/{SpeakType.Whisper.Tests.csproj, WhisperTranscriberTests.cs, assets/hello.wav}` (new integration test project); `SpeakType.sln` (both projects added). App wiring is deferred to Brick 14.
- **Verified (on Mac):** fast suite `dotnet test SpeakType.Tests/...` still **112/112**; the adapter builds warning-clean; and the gated **end-to-end integration test passes for real** — it downloads `tiny.en` via the real `ModelStore`+`HttpModelDownloader`, decodes the committed WAV via `AudioMath.Pcm16ToFloat`, transcribes, and asserts the words (produced "The quick brown fox jumps over the lazy dog."). So it exercises Bricks **5+6+7** together. The test is `[Trait("Category","Integration")]` + `[SkippableFact]` (skips offline); CI's fast job excludes `Category=Integration`, so it **builds but does not run** there (green: run 26822466951). Real-mic + the laptop is M1/M8.
- **Notes / decisions:**
  - **Separate `SpeakType.Whisper` project (not Core, not App):** Whisper.NET is a heavy native dependency; isolating it keeps `Core` pure/cross-platform and out of the fast unit suite, mirroring the `ISettingsStore`→`JsonSettingsStore` shape. The integration test references `Whisper.net.Runtime` (native libs) only in the test project.
  - **Pre-build spike validated portability:** Whisper.NET 1.9.1 runs on Apple-Silicon Mac (Metal); the runtime package ships native libs for macOS/Windows/Linux/Android in one package. A 3-model bench (tiny/base/small) + a real-voice recording confirmed **base.en is the right default** (≈small accuracy at ~3× the speed; tiny weakest), feeding the Brick 11 model dropdown. The catalog sizes/SHA256 were confirmed against real downloads.
  - **Integration test = real download path (intentional "duplication"):** code review suggested replacing the hand-rolled WAV parser with Whisper.net's `ProcessAsync(Stream)`; declined, because that would bypass `AudioMath.Pcm16ToFloat` + `Transcribe(float[])` — i.e. stop testing the *production* path (the app feeds `float[]` from the mic, never a WAV file). The robust RIFF chunk-scan was load-bearing: the `say`/`afconvert` WAV's data chunk starts at offset 4096, not 44.
  - **Threading deferred to Brick 14 (review, noted there):** `Transcribe` won't deadlock but freezes its calling thread for the transcription duration — Brick 14 must run the cycle off the UI thread; and the deployable app must add `Whisper.net.Runtime`.

### Brick 6b — HTTP model downloader (2026-06-02)
- **What:** The real network half of the model store: `HttpModelDownloader` implements `IModelDownloader` with a streaming `HttpClient` download. It fetches the URL with `HttpCompletionOption.ResponseHeadersRead`, `EnsureSuccessStatusCode()`, then copies the body to the destination file in 80 KB chunks, reporting `IProgress<double>` (received/total) when `Content-Length` is known and honouring the `CancellationToken` throughout. It **borrows** an injected `HttpClient` (the Brick 14 composition root owns/disposes it — so the type is not `IDisposable`) and performs exactly **one attempt per call**; the Brick 6a `ModelStore` owns the retry loop, size/SHA256 verify, and atomic install (and cleans up any partial temp file on failure). Cross-platform (BCL `System.Net.Http`).
- **Files:** `SpeakType.Core/Models/HttpModelDownloader.cs` (new); tests `SpeakType.Tests/Models/HttpModelDownloaderTests.cs` (new).
- **Verified (on Mac):** `dotnet test SpeakType.Tests/...` → **112/112 pass** (5 new, via a fake `HttpMessageHandler` + a no-`Content-Length` custom `HttpContent` + a synchronous progress collector): exact-body write with Content-Length; non-decreasing progress ending at 1.0 across multiple buffers; correct write when length is unknown (no progress); 404 → `HttpRequestException`; pre-cancelled token → `OperationCanceledException`. CI green on Windows too (run 26820230925). The **real network download + model switch + failure/retry is manual M2 on the laptop** (needs a live HTTP fetch). This completes Brick 6 (6a logic + 6b downloader); Brick 14 wires `new HttpModelDownloader(httpClient)` into `new ModelStore(...)`.
- **Notes / decisions:**
  - **Manual buffer-copy loop (not `Stream.CopyToAsync`)** — `CopyToAsync` gives no progress callback, and the UI needs a download progress signal, so the hand-rolled loop is required (review confirmed).
  - **Borrow, don't own, the `HttpClient`** — the recommended pattern (a long-lived client avoids socket exhaustion); the composition root owns it. Buffer size is the BCL default 80 KB.
  - **Progress is best-effort** (review): if a misbehaving server sends more/fewer bytes than `Content-Length`, the fraction can momentarily exceed 1.0 or stop short — cosmetic only, since `ModelStore.Verify` gates on exact size+SHA256. Unknown length → no progress reports (every catalog `ModelInfo` has a known size, so this only affects ad-hoc URLs).

### Brick 6a — Model store logic + verification (2026-06-02)
- **What:** The model-management core (spec Feature 2 plumbing): resolve the per-user models directory (`%LOCALAPPDATA%\SpeakType\models`), verify a model file by exact byte size **and** SHA256, download-with-retry, install atomically, and **keep the prior model untouched when a switch fails**. Behind ports: `IModelStore` (`ModelsDirectory`, `GetInstalledModelPath`, `EnsureAsync`) and `IModelDownloader` (one download attempt; the real `HttpClient` impl is Brick 6b). `ModelStore.EnsureAsync` short-circuits when a valid file is already present, else downloads to a `.download` temp, verifies, and `File.Move(overwrite)`s into place only on success (so a failed/partial download never clobbers a good model); it re-downloads a corrupt-on-disk or missing file and retries up to 3×. `ModelCatalog` holds the three ggml `.en` models (tiny/base/small) with their HuggingFace URLs + Git-LFS size/SHA256. **Cross-platform** (BCL `System.IO`/`System.Security.Cryptography` only — no NuGet, no Windows APIs).
- **Files:** `SpeakType.Core/Models/{ModelCatalog.cs, IModelDownloader.cs, IModelStore.cs, ModelStore.cs}` (new); tests `SpeakType.Tests/Models/ModelStoreTests.cs` (new); `.gitignore` (narrowed the over-broad `models/` rule that was hiding the source `Models/` folders to a repo-root anchor `/models/`; runtime `*.bin` stay ignored).
- **Verified (on Mac):** `dotnet test SpeakType.Tests/...` → **107/107 pass** (9 new: install-on-verify, truncated-download throws + cleans temp, **keep-old-on-failed-switch**, already-installed short-circuit (downloader not called), corrupt-on-disk re-download, retry-then-succeed, unknown-model throws, `GetInstalledModelPath` present/absent, and **case-insensitive name resolution**). Fully Mac-verified (the spec's unit deliverable); CI green on Windows too (run 26819768676). Real download + switch + failure is **manual M2 on the laptop** (needs Brick 6b + network).
- **Notes / decisions:**
  - **Brick 6 was split (6a + 6b)** by §2a sizing: the verify/retry/switch **logic** (here, fully Mac-tested with a fake downloader + temp dirs) vs the real `HttpClient` streaming downloader (6b). The `IModelDownloader` seam is exactly what makes the logic testable without a network.
  - **Code review caught a real cross-platform bug (fixed):** `GetInstalledModelPath` used the raw argument while `EnsureAsync` used the canonical catalog name — so a non-canonical query like `"BASE.EN"` looked for `ggml-BASE.EN.bin` and returned null on a case-sensitive filesystem (Mac/Linux/CI run plain `net8.0`) even when `ggml-base.en.bin` was installed. Now both resolve through the catalog; regression test added. Also added the last download error as the final exception's `InnerException` for M2 diagnosability.
  - **Catalog SHA256/size are the HuggingFace Git-LFS pointer values** (fetched live): tiny.en 77704715 / `921e4cf8…`, base.en 147964211 / `a03779c8…`, small.en 487614201 / `c6138d6d…`. The verify *logic* is unit-tested; the catalog *values* are confirmed at M2 against a real download.
  - **`%LOCALAPPDATA%` path is cross-platform** via `Environment.GetFolderPath(LocalApplicationData)` (maps to the OS per-user data dir); `DefaultModelsDirectory` is exposed for the Brick 14 composition root, while the dir is constructor-injected for tests.

<!-- Template for each entry:

### Brick N — <title> (YYYY-MM-DD)
- **What:** one line on what it does / what the user sees.
- **Files:** main source files touched (+ tests).
- **Verified:** how you confirmed it works (tests + manual M# items).
- **Notes:** decisions, gotchas, or follow-ups a future session needs.

-->
