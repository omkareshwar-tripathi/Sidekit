# TESTING.md

Test plan for Sidekit's Windows dictation app (v1). Derived from `Sidekit-v1-spec.md`.

Two layers:

1. **Automated** (in `Sidekit.Tests`, xUnit) — covers all pure/core logic and one gated real-Whisper check. Run with `dotnet test`.
2. **Manual** (`M#` checklist below) — covers the OS-bound adapters that can't be unit-tested (global hook, real audio, clipboard, paste, tray, overlay, lifecycle). Each brick's `BRICKS.md` "Verified" line cites the `M#` items it exercised.

> **Status:** stub. Items are written against intended v1 behavior; check them off as each brick lands. An item for unbuilt behavior stays unchecked.

> **Shelf drag-tests (Mac): never drag repo files.** Use the disposable samples in `~/SpeakType-TestFiles/` (sample.txt / sample.sh / sample.png / sample-folder). A fumbled Finder drag of a repo file/folder silently *moves* it (this is how `windows/Sidekit.App` kept vanishing from the worktree — see the BRICKS.md note; a hook now auto-restores it).

---

## Automated tests (summary — authoritative copy is the test project)

| Area | Type | Asserts |
|---|---|---|
| Settings store | unit | round-trip; missing/partial file → defaults; invalid hotkey rejected |
| Cleanup pipeline | unit (`[Theory]` corpus) | filler removal, phrase guards, fixups, formatting, hallucination filter, toggle off |
| Orchestrator state machine | unit (fakes + fake clock) | normal flow; <300 ms discard; 60 s auto-stop; busy = ignore; silence-skip; no-target leave-on-clipboard |
| Hotkey parse/validate | unit | accept safe keys/combos; reject bare letters/digits |
| Silence gate | unit | silent buffer → skip; speech-level → proceed |
| Model verify | unit | valid passes; truncated/corrupt fails; keep-old-on-failed-switch |
| Logging | unit | metadata-only by default; transcript only when debug on |
| **Whisper engine** | **integration (gated/slow)** | real Whisper on `test-assets/hello.wav` → transcript contains "hello world" |

Run automated tests: `dotnet test`
Run only fast tests (exclude the slow Whisper integration test): _filter TBD once the trait/category is set (see `run-tests` skill)._

---

## Manual checklist

Default hotkey below is **Right Ctrl**. Reset to a clean user profile where a test says "fresh".

### M1 — Push-to-talk hotkey & dictation _(Bricks 4, 14)_
- [ ] Focus Notepad. Hold Right Ctrl, say "hello", release → **"Hello "** appears at the cursor (note the trailing space).
- [ ] Tap Right Ctrl quickly (<300 ms) → **nothing happens** (no overlay, no paste).
- [ ] Hold Right Ctrl ~5 s while speaking → overlay shows 🎙 Listening then ⚙ Transcribing; text appears.
- [ ] Hold Right Ctrl and keep talking past 60 s → recording **auto-stops at 60 s** and transcribes what was captured.
- [ ] In Settings, rebind to **Ctrl+Space** → dictation works on the new combo; Right Ctrl no longer triggers.
- [ ] Try to bind a bare letter (e.g. **E**) → **rejected** with an inline message.
- [ ] While the bound key is held, it does **not** leak into the focused app (suppressed).

### M2 — On-device model: first run, switch, failure _(Bricks 6, 12)_
- [ ] **Fresh** launch → **Welcome window** with how-to + progress bar downloading `base.en`; hotkey is **inert** until done → **"Ready!"** balloon.
- [ ] After download, disconnect network → dictation **still works** (fully offline).
- [ ] Settings → switch model to **small.en** → downloads with progress; the **current model keeps working** during download; swaps when verified.
- [ ] Kill the network mid-download → **"Download failed — Retry"**; app **stays on the previous model**.
- [ ] Corrupt/truncate a cached model file, restart → app detects bad file and **re-downloads** it.

### M3 — Audio capture & silence _(Brick 5)_
- [ ] Disable/unplug the microphone, hold the hotkey → tray balloon **"No microphone found"**, returns to Idle.
- [ ] In a quiet room, hold the hotkey and say nothing → overlay **"No speech detected"**, **nothing pasted** (no "Thank you." hallucination).
- [ ] Change the Windows default input device while running → next dictation uses the new device (no restart).

### M4 — Clipboard-safe paste _(Brick 8)_
- [ ] Copy the text **ORIGINAL** to the clipboard. Dictate into Slack → dictated text pastes correctly.
- [ ] Immediately press **Ctrl+V** in another field → **ORIGINAL** is still there (clipboard restored).
- [ ] _(Known tradeoff)_ Copy an **image**, then dictate → image is **lost** (text-only restore — expected in v1).
- [ ] Dictate into a **modern** app where the old caret check used to fail (browser address bar, VS Code, Slack, Win11 Notepad) → text types directly into the field (no longer just left on the clipboard).
- [ ] Click the desktop (no editable field) and dictate → text is typed nowhere but **remains on the clipboard** (pressing Ctrl+V in a real field afterward yields it). If the foreground window blocks injection (e.g. an elevated app), overlay shows **"Copied — paste manually"**.

### M5 — Tray icon & overlay _(Bricks 9, 10)_
- [ ] Tray icon reflects state: Idle → Recording → Busy during a dictation, back to Idle.
- [ ] Overlay appears bottom-center of the **active monitor**, shows the right state text, and **fades out** on completion.
- [ ] With a text field focused and caret blinking, trigger dictation → the field **keeps focus/caret** (overlay never steals focus); paste lands in that field.
- [ ] Settings → turn **overlay off** → no overlay on next dictation; tray icon still changes.

### M6 — Settings persistence & autostart _(Bricks 11, 12)_
- [ ] Change each setting (hotkey, model, filler toggle, overlay toggle, autostart, debug logging) → each takes effect **immediately** (no Save button).
- [ ] Restart the app → all settings **persisted** (`%APPDATA%\Sidekit\settings.json`).
- [ ] Toggle **Start with Windows** off then on → `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` entry is **removed then re-added**.
- [ ] Turn **Remove filler words** off → dictate "um I think" → fillers are **retained**.

### M7 — App lifecycle _(Brick 9)_
- [ ] With the app running, launch a **second instance** → **"Sidekit is already running"** balloon, second instance exits; the first keeps working (no double paste).
- [ ] Pause listening from the tray → hotkey does nothing; restart the app → it comes back **active** (pause does not persist).
- [ ] _(If reproducible)_ Force an error during a dictation → app **logs it, shows a balloon, and recovers to Idle** rather than crashing.

### M8 — End-to-end across apps _(Brick 14)_
- [ ] Dictate a 1–2 sentence message with a couple of "um"s and a comma-bounded "you know" into **Notepad**, **Slack**, and a **browser text box** → in each, fillers are removed, capitalization/punctuation look natural, trailing space present.
- [ ] Observe the latency log line (release→paste) → roughly **< 2 s** on this machine for a short utterance with `base.en` (goal, not a hard gate).

---

## Notes
- The slow Whisper integration test and the manual M2 first-run test need a model file; keep a known-good `tiny.en`/`base.en` available locally (don't commit large `.bin` files).
- There is no skill for local Whisper / audio capture — those bricks are verified against library docs + these manual items (see `CLAUDE.md` §6 known gap).
