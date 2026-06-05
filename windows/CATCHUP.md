# Windows Catch-Up Plan

**Read this first when starting Windows development.** This note captures the agreed plan to bring the Windows app to feature parity with the Mac app, then continue all future development here on Windows.

## Why this exists

SpeakType has two codebases — this Windows C#/WinForms app (the lead app going forward) and a native macOS Swift app (`feat/mac-app` branch). The Mac app pulled ahead on user-facing features during a UI redesign. The decision (2026-06-06): **bring those features over to Windows, then develop on Windows for a smoother dev/test loop.** The Mac app is left as-is until we choose to sync it back.

This branch (`chore/windows-folder`) only did the **repo reorg**: the whole .NET solution now lives under `windows/` so the Windows app is self-contained. No feature work has started yet.

## Where things are now

- `windows/SpeakType.sln` — the solution (App, Core, Whisper, Tests, Whisper.Tests + `Directory.Build.props`).
- `.github/workflows/ci.yml` stays at repo root (GitHub requires it there); its paths were updated to point at `windows/`.
- Project-to-project references and the `.sln` were untouched by the move — they moved together, so relative paths stayed valid.
- Inter-app docs (`BRICKS.md`, `CLAUDE.md`, `docs/`, spec, TESTING.md) stayed at repo root.

**First thing on Windows:** open `windows/SpeakType.sln`, restore, build, run the test suite — confirm the reorg didn't break anything (CI should already prove this, but verify locally too).

## What the Windows app has today

Tray + hold-hotkey (Right Ctrl, configurable) push-to-talk → NAudio capture → Whisper.net → transcript cleanup (filler removal + fixups) → clipboard-safe paste at the cursor. Recording overlay (plain text states). Settings (hotkey, model size, filler toggle, overlay toggle, autostart, debug logging). First-run model download. Single-instance guard, global exception handling. Ports-and-adapters: pure `SpeakType.Core` + WinForms adapters in `SpeakType.App`.

## What to build (the catch-up) — phased, in order

Each phase = its own spec → plan → build → verify cycle (brick-led, see `CLAUDE.md`). Ship and verify each before starting the next.

### Phase 1 — Notes scratchpad
A real app window: left sidebar list of notes (title = first non-empty line, + preview + relative time, newest-updated-first), right multiline editor. Create / edit / delete. Persist to `%APPDATA%\SpeakType\notes.json`. Opened from a new tray menu item "Notes…". **No dictation changes in this phase.**
- Core (pure, tested): `Note` record (Id, Body, CreatedAt, UpdatedAt, computed `Title`); `NotesStore` (NewNote / Append / SetBody / Select / Delete, newest-first, injectable clock); `INotesRepository` port.
- App: `JsonNotesRepository` (mirror `JsonSettingsStore` conventions — camelCase, tolerant load); `NotesForm` (SplitContainer UI).
- Reference implementation: Mac `SpeakTypeMac/Sources/SpeakTypeCore/{Note,NotesStore}.swift` and `Adapters/JSONNotesStore.swift` — port the rules line-for-line.

### Phase 2 — Dictation routing into notes
When the SpeakType notes window is the foreground window, append the cleaned transcript to the active note (creating one if none) instead of pasting; otherwise paste as today. Mirror Mac's `RoutingSink` / `PasteSink` (a `DictationSink` port + a foreground-window check). Keep the routing decision pure/testable.

### Phase 3 — History trail
Log every delivered dictation (time + cleaned text + outcome: Pasted / LeftOnClipboard / AddedToNote / NoSpeech). Persist to `history.json`, newest-first, cap 50. A History view (dialog/sheet) with relative time, outcome, and a Copy button. Mirror Mac's `HistoryStore` / `HistoryRecordingSink` / `HistoryCodec`.

### Phase 4 — Overlay upgrade
Evolve the existing click-through recording overlay to show a **live waveform** while recording plus clean state/outcome labels (Listening / Transcribing / outcome). Custom-drawn but **static states — no morph animations** (decided: low-risk path, not the full Mac pill). Honors the existing overlay on/off toggle.

## Decisions locked

- **Direction:** Windows catches up to Mac; Mac left as-is for now.
- **Pill UI:** upgrade the existing overlay (waveform + labels), *not* a full animated pill.
- **Packaging:** phased sub-projects, each shipped + verified before the next.
- **Persistence:** `notes.json` / `history.json` under `%APPDATA%\SpeakType\` (next to `settings.json`), mirroring `JsonSettingsStore`.

## Reference: Mac files to port from (on `feat/mac-app` branch)

```
SpeakTypeMac/Sources/SpeakTypeCore/Note.swift
SpeakTypeMac/Sources/SpeakTypeCore/NotesStore.swift
SpeakTypeMac/Sources/SpeakTypeCore/{DictationHistory,HistoryStore,HistoryRecordingSink,HistoryCodec}.swift
SpeakTypeMac/Sources/SpeakTypeCore/{RoutingSink,PasteSink}.swift
SpeakTypeMac/Sources/SpeakTypeApp/Adapters/{JSONNotesStore,JSONHistoryStore}.swift
SpeakTypeMac/Sources/SpeakTypeApp/{MainWindow,HistoryView,PillView}.swift
```
