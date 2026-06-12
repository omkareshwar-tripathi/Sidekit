# TESTING.md (Mac)

Manual test plan for the **Sidekit Mac app** (the native Swift fork on `feat/mac-app`).
The pure logic is covered by `swift test` (152 automated tests); this file covers everything
that only a human in front of a running Mac can verify — the floating pill, the Fn hotkey,
real audio, paste, the scratchpad window, settings, permissions, and app lifecycle.

> **How to use this:** work top to bottom. Each item is one observable behavior with the exact
> steps and what "pass" looks like. Tick the box when it matches; if it doesn't, jot what you saw
> in the **Notes** column of the sign-off table at the bottom and tell me.

---

## 0. Build & launch the app under test

The pill and permissions only work from the signed `.app` bundle, **not** `swift run`.

```bash
cd mac
./Scripts/build-app.sh release      # builds, bakes in the Whisper model, signs
open Sidekit.app
```

- Automated baseline (optional, fast): `swift test` → expect **140 tests passed**.
- This is a **self-signed local dev** build. On first open, if macOS Gatekeeper blocks it
  ("unidentified developer"), right-click the app → **Open**, or approve it in
  **System Settings → Privacy & Security**. Expected for a dev build — not a bug.

---

## 1. First launch & permissions  _(gating — do this once, first)_

- [ ] **A 🎙 mic icon appears in the menu bar** (top-right). No Dock icon yet, no window.
- [ ] A **Microphone** permission prompt appears → click **Allow**.
- [ ] An **Accessibility** prompt (or the menu-bar "⚠︎ Grant Accessibility…" item) appears →
      open System Settings, enable **Sidekit** under Privacy & Security → Accessibility.
- [ ] After granting Accessibility, the menu-bar **⚠︎ warning item disappears** (re-open the
      menu to check). Accessibility is required for the Fn key and for pasting.
- [ ] Because the build is signed with a **stable** identity, these grants **persist across
      rebuilds** — rebuild with `build-app.sh` and confirm you are **not** re-prompted.

---

## 2. The floating pill  _(spec §2.1 — always-present state indicator)_

- [ ] **Idle:** a glass pill sits **bottom-center** of the screen and gently **"breathes"**
      (slow dim pulse). It does **not** intercept clicks — click straight through it.
- [ ] The pill stays put when you **switch Spaces / desktops** and over **full-screen** apps
      (it floats above everything, on every Space).
- [ ] **Recording:** hold **Fn (🌐)** → the pill expands to show a **red dot** and a **live
      waveform** that visibly reacts to your voice (louder = taller bars).
- [ ] **Transcribing:** release Fn → the waveform is replaced by a **spinner** for a moment.
- [ ] **Done:** a **green ✓** pops, holds for ~1 second, then the pill **collapses back** to the
      breathing idle state.
- [ ] Multi-monitor: the pill is on the **main** display; behavior there is the one that matters.

---

## 3. Push-to-talk dictation → paste at cursor  _(spec §3, default destination)_

Test in a normal text field first (e.g. **TextEdit**, a browser address bar, or Notes — anything
that is **not** Sidekit).

- [ ] Click into a text field. **Hold Fn, say "hello world", release** → after a beat,
      **"hello world "** appears at the cursor (note the **trailing space**).
- [ ] **Tap Fn quickly (under ~0.3 s)** → **nothing happens** (no paste, no ✓) — taps are ignored.
- [ ] **Hold Fn and talk past ~3 min** → recording **auto-stops at ~180 s** and transcribes
      what it captured (you don't have to release).
- [ ] **Filler removal (on by default):** say *"um, I think, uh, we should ship it"* →
      the pasted text **drops the "um/uh"** and reads cleanly.
- [ ] **Clipboard is restored:** copy the word **ORIGINAL** somewhere, then dictate into a field →
      dictated text lands, and pressing **⌘V** afterward still pastes **ORIGINAL** (your clipboard
      wasn't clobbered).
- [ ] **No speech:** hold Fn in a quiet room and say nothing → **nothing is pasted**, and the
      menu-bar status reads **"No speech heard"** (no hallucinated text).
- [ ] If paste is blocked (rare — e.g. an elevated app has focus), the text is **left on the
      clipboard** and the status says so ("Left on clipboard (paste manually)").
- [ ] **Dictation History:** after any dictation, open **Sidekit** (menu bar → Open Sidekit)
      and open **History** (toolbar History/clock button) → the dictation appears in the list with
      its time, its outcome (Pasted / Left on clipboard / Added to note), and a **Copy** button;
      clicking Copy puts that text back on the clipboard. History persists across relaunch and
      keeps the most recent ~50 dictations.

---

## 4. The scratchpad window  _(spec §2.3 — standalone voice notepad)_

- [ ] **Menu bar → "Open Sidekit"** → a window opens with a **sidebar** (notes list) on the left
      and a **text editor** on the right. A **Dock icon** now appears (app becomes a regular app).
- [ ] **Empty state:** with no notes, the sidebar shows **"No notes yet"** and a **"New note"**
      button. Click it → a new, empty note is created and selected.
- [ ] **Type** into the editor → the sidebar row updates its **title** (first non-empty line) and
      shows a **relative time** ("just now", "2 minutes ago").
- [ ] **Create a second note** (toolbar **✎** / square-and-pencil button) and type in it →
      switching between notes in the sidebar **cross-fades** the editor to each note's text.
- [ ] **Newest-first reorder:** edit an **older** note → its row **animates up to the top** of the
      list (the most recently edited note leads).
- [ ] **Delete:** **right-click** a note in the sidebar → **Delete** → the row animates out and is
      removed.
- [ ] **Persistence:** type some text, **Quit Sidekit** (menu bar → Quit, or ⌘Q), then relaunch
      and open the window → **your notes are still there**, including the last edit you made right
      before quitting (saved to `~/Library/Application Support/Sidekit/notes.json`).
- [ ] **Close the window** (red ⌘ button) → the **Dock icon disappears**; the app keeps running as
      a menu-bar utility (the pill stays, Fn still dictates).

---

## 5. Dictation routed into the focused note  _(spec §3 — in-app destination)_

- [ ] Open the Sidekit window and **click into the editor so Sidekit is the focused app**.
- [ ] **Hold Fn, speak, release** → the transcript is **appended into the open note** (not pasted
      elsewhere). The menu-bar status reads **"Added to note ✓"**.
- [ ] **Delete all notes** so the sidebar shows the empty state (this *is* the "no note exists"
      state — there's no separate deselect), then dictate → a **new note is created** and the speech
      lands in it.
- [ ] **Open another app** (e.g. TextEdit), click into its text area so Sidekit is **not** the
      front app, then hold Fn and speak → the text pastes at your cursor there (status
      **"Pasted ✓"**), NOT into a Sidekit note. (Contrast 5.1, where Sidekit's own editor is
      focused and the text goes into a note.)

---

## 6. Settings sheet  _(spec §2.3)_

- [ ] In the window, click the **⚙︎ (gear)** toolbar button → a **Settings sheet** slides down with
      **Dictation**, **General**, and **Permissions** sections.
- [ ] **Permissions badges** show **Microphone** and **Accessibility** as **Granted** (green) after
      §1. If Accessibility is not granted, an **"Open Settings…"** button appears next to it.
- [ ] **Remove filler words** toggle — dictate a sentence where the model actually transcribes a
      filler (speak slowly/clearly, e.g. *"I think, um, we should ship it"*). With the toggle
      **ON**, the "um" is dropped; toggle it **OFF** and repeat → the "um" is kept. NOTE: Whisper
      sometimes omits disfluencies by itself, so this toggle only has a visible effect when "um"
      actually appears in the raw transcript.
- [ ] Re-open Settings → the toggle is **still OFF** (persisted). Toggle it back ON.
- [ ] **Launch Sidekit at login** — toggle **ON**. _(This only actually registers from the signed
      `.app`, which you have.)_ To verify: it should appear in **System Settings → General →
      Login Items**. Toggle OFF → it's removed.

---

## 7. Menu bar & app lifecycle

- [ ] The menu-bar **icon changes with state**: mic (idle) → mic.fill (recording) → waveform
      (transcribing) during a dictation, then back.
- [ ] The menu-bar dropdown shows a **live status line** matching the last action ("Pasted ✓",
      "Added to note ✓", "No speech heard", "Recording…", etc.).
- [ ] **Quit** from the menu (or ⌘Q) → the app fully exits (icon gone). Any unsaved note edit is
      **flushed to disk first** (verified by §4 persistence).
- [ ] Relaunch → comes back as the menu-bar app with the pill; no leftover Dock icon until you open
      the window again.

---

## 8. Reduced-motion accessibility  _(optional, nice-to-have)_

- [ ] Turn **ON** macOS **System Settings ▸ Accessibility ▸ Display ▸ "Reduce motion"**, then
      trigger a dictation → pill transitions become **simple fades** (no springs); everything still
      updates. (This is a macOS system toggle, not an in-app setting.)

---

## 9. Sign-up & feedback  _(spec 2026-06-11 — the app's only network feature)_

Reset first: `rm -f ~/Library/Application\ Support/Sidekit/identity.json ~/Library/Application\ Support/Sidekit/outbox.json`

- [ ] **First launch:** welcome sheet appears over the main window (logo, email field,
      Skip / Continue). **Skip** → sheet gone; quit & relaunch (launches 2–4) → **no sheet**;
      5th launch → sheet appears **once more**; after that, never again.
- [ ] **Sign up:** enter an email → Continue. Row appears in the Supabase `signups` table
      (needs `docs/SUPABASE-SETUP.md` done). Settings → Account shows "Signed up as …".
- [ ] **Quick feedback:** menu bar → **Send Feedback…** → box opens centered, field focused.
      **Hold Fn and dictate** → transcript lands in the box (not in a note). ⌘↩ → "Thanks!"
      toast → row in the `feedback` table with type/email/versions.
- [ ] **Esc** closes without sending; reopening keeps the draft. Chips 🐞/💡 toggle; untagged
      sends as `other`.
- [ ] **Offline:** disconnect Wi-Fi → send feedback → toast says "Saved — will send when
      you're online" and the entry sits in `outbox.json`. Reconnect → relaunch → row appears
      and `outbox.json` is empty.
- [ ] **Routing regression (M5):** with the box closed and the main window focused,
      dictation still lands in the active note; with Sidekit unfocused it still pastes at
      the cursor.
- [ ] **Key safety:** the curl `select` from `SUPABASE-SETUP.md` step 5 returns an error —
      the shipped key cannot read data.

---

## 10. Shelf for agents + auto-screenshots  _(spec 2026-06-12)_

Several checks were **machine-walked on 2026-06-12** (marked ✅·machine, with the evidence);
the unmarked ones need a human — mostly because they involve the one-time macOS consent click
or the Settings UI.

- [x] **m10-1 · Screenshot lands (pipeline)** ✅·machine: a real `screencapture -x` into a home
      folder appeared on the Shelf exactly once via Spotlight → gate → 1.5 s stability check →
      the drag-in copy path, and showed up in `manifest.json`. Human remainder: one real ⌘⇧3
      to the **Desktop** (covered by m10-8's consent click) → tile appears with a thumbnail.
- [ ] **m10-2 · Toggle OFF:** Settings → Shelf → turn "Auto-add screenshots to Shelf" off →
      ⌘⇧3 → nothing lands.
- [ ] **m10-3 · Toggle back ON:** flip it back on → ⌘⇧3 → lands again. (This exercises the
      watcher's stop→start restart — the one path automation didn't cover; review 2026-06-12.)
- [x] **m10-4 · Agent path** ✅·machine: `ls -la ~/.sidekit/` shows `shelf →
      …/Application Support/Sidekit/Shelf`; `manifest.json` + `AGENTS.md` readable through it.
- [ ] **m10-5 · Removal syncs:** remove a tile (or Clear all) → the entry disappears from
      `manifest.json`. (The add→manifest sync and the startup heal are machine-proven; this
      checks the same save funnel from the UI remove.)
- [ ] **m10-6 · Retention syncs:** change Settings → "Keep items for" → every `expiresAt` in
      `manifest.json` shifts to match (cat it before/after).
- [x] **m10-7 · ANY agent can read the Shelf (acceptance)** ✅·machine: the footer prompt was
      handed cold to a fresh agent (smallest model, no other context) — it listed the items
      from the manifest with all fields and read the newest file's actual content, and called
      the instructions "complete and sufficient". Human remainder (~30 s, optional): click
      **For agents** in the Shelf footer → "Copied ✓" → paste into your own Claude Code /
      Antigravity session for the same result.
- [ ] **m10-8 · Desktop consent:** first ⌘⇧3 that saves to the Desktop → macOS asks
      "Sidekit would like to access files in your Desktop folder" **once** (our usage string
      visible). Allow → tile appears. (If you deny: no tile, no crash — re-enable later in
      System Settings → Privacy & Security → Files & Folders.)

---

## Sign-off

Fill this in as you go — it's the record of a pass.

| #  | Area                                  | Result (✅ / ❌) | Notes |
|----|---------------------------------------|:--------------:|-------|
| 1  | First launch & permissions            |                |       |
| 2  | Floating pill (states + behavior)     |                |       |
| 3  | Push-to-talk → paste at cursor        |                |       |
| 4  | Scratchpad window (CRUD + persist)    |                |       |
| 5  | Dictation routed into focused note    |                |       |
| 6  | Settings sheet                        |                |       |
| 7  | Menu bar & lifecycle                  |                |       |
| 8  | Reduced motion (optional)             |                |       |
| 9  | Sign-up & feedback                    |                |       |
| 10 | Shelf for agents + auto-screenshots   |                |       |

**Tester:** ____________  **Date:** ____________  **Build:** `build-app.sh release` @ commit ________

---

## Notes
- This plan covers the **Mac fork only**. The Windows C# plan lives in the repo-root `TESTING.md`
  (Right Ctrl hotkey, tray, registry — different app, don't cross-reference the two).
- The pure logic behind these behaviors (state machine, text cleanup, notes store, routing,
  audio level math) is already unit-tested — run `swift test` for that layer. This file is purely
  the OS-bound / visual layer that automation can't reach.
