# Sidekit Intelligence v1 — pill menu, scratchpad drafting, on-device LLM

**Date:** 2026-06-12
**Status:** Design approved in brainstorm (pill → Polish · Scratchpad · Dictate; preset chips + tones; one shared model; load-on-demand RAM lifecycle). This spec is the buildable contract.
**Scope:** Mac app (`mac/`, Swift). First shipping slice of the Sidekit Intelligence vision (`vision/sidekit-intelligence.md`): day one it only *thinks* — Polish + Drafting, propose-you-commit, local-only.

---

## 1. Decisions locked in brainstorm

| Question | Decision |
|---|---|
| Where does LLM polish run? | **On-demand only**, behind the pill. The dictation pipeline is untouched — no auto-polish in v1 (future settings toggle, out of scope). |
| RAM posture | **The model is a guest in RAM, not a resident.** Load on first use, stay warm for an idle window, then unload. Never two models in memory. Unload immediately on system memory pressure. |
| One model or two? | **Two role-specific models (Gate A outcome, decided by the user 2026-06-12):** `mlx-community/gemma-2-2b-it-4bit` runs **Polish** (148/190 faithful-cleanup PASS; its chat template has **no system role** — the engine folds the system prompt into the user turn) and `mlx-community/Qwen3-1.7B-4bit` runs the **drafting chips** (22/29 assistant, arithmetic guardrail 2/2, 1.25 GB peak; thinking **disabled** — Qwen3.5-2B-OptiQ scored 24/29 but its architecture is a VLM that MLX Swift cannot load as text; Qwen3-1.7B was adopted 2026-06-12 per the §7 fallback rule). The one-shared-model hope died at Gate A — see §7 for the recorded results. Still only ONE model ever in RAM: switching roles unloads one, loads the other. |
| Drafting UX | **Preset chips + tones.** No free-form instruction field in v1. |
| Polish entry point | Opens the scratchpad **pre-loaded with clipboard text**, Polish chip pre-selected. Nothing ever silently rewrites the clipboard. |
| Tone selector | **Global in the panel** — applies to whatever chip runs, Polish included. Default **Keep tone**. |
| Prompt strings | Token-lean (standing user rule). The lab-tuned `p7_faithful` polish prompt is the one deliberate exception — it's tuned, copied verbatim, never hand-trimmed. |

## 2. The pill hover menu

Today the pill is a passive status light (idle breathing dot → Listening → Transcribing → done). It becomes interactive:

- **Hover** over the idle dot expands it into three glass buttons: **Polish · Scratchpad · Dictate** (left to right). Mouse-out collapses back to the dot. Spring morph; Reduce Motion degrades to a fade (house rule, UI-redesign spec §9).
- The **hover hitbox is larger than the dot** (the dot is 28×5 pt — hovering a 5 pt target is misery). The panel's tracking area is at least 80×30 pt centred on the dot.
- The menu only appears from the **idle** state. While recording / transcribing / showing an outcome, hover does nothing — the pill is busy being a status light, and the existing state morphs are unchanged.
- **Clicking the dot itself** still opens the main window (existing behavior, kept).
- The pill panel stays non-activating and focus-stealing-free. Button clicks must work without activating the app (`NSPanel` + `.nonactivatingPanel` already proven; the scratchpad panel is the only surface that takes key focus).

**Button actions:**

| Button | Action |
|---|---|
| **Polish** | Open the scratchpad. If the clipboard has plain text, pre-fill the editor with it (whitespace-trimmed only — if it exceeds the §4 input cap, the status line shows the too-long message; never silently truncate) and highlight the **Polish** chip — one tap runs it. Empty clipboard → open empty with Polish highlighted. |
| **Scratchpad** | Open the scratchpad as last left (it remembers unsent text — §3). |
| **Dictate** | Hands-free dictation: call the coordinator's `pressed()`. The pill morphs to Listening as it does for Fn. **While a Dictate-button recording is active, clicking the pill stops it** (`released()`) — this overrides click-opens-window for that recording only; Fn-held recordings are unaffected (release Fn stops them, as today). The existing 180 s auto-stop also applies. Text routes exactly like Fn dictation. **No LLM involved.** |

## 3. The scratchpad panel

A floating glass panel anchored above the pill — same species as `FeedbackBox` (floating `NSPanel`, becomes key for typing, Esc closes). Top to bottom:

1. **Editor** — plain-text, multiline, placeholder *"Type — or hold Fn and just say it."* Dictation routes into it while the panel is key (RoutingSink `appendToNote` override — the FeedbackBox precedent, notes path untouched otherwise).
2. **Chip row** — `Draft email` · `Draft message` · `Polish` · `Summarize`. Chips are run buttons: tapping one with text present runs that action with the current tone (no separate Run button). With no text, taps do nothing.
3. **Tone picker** — `Keep tone` · `Professional` · `Friendly` · `Concise` (segmented; default Keep tone; the choice persists across opens and relaunches via UserDefaults).
4. **Result area** — appears below once a generation finishes: the output text (read-only, selectable) with **Copy** (puts result on clipboard, shows "Copied ✓" ~1.5 s) and **Use as input** (replaces the editor text with the result, for iterating). The input editor is never overwritten by a generation.
5. **Status line** — the honest engine state (§5): "Download model (≈1.7 GB, one time)" / "Warming up…" / "Drafting…" + **Cancel** / error text.

**Persistence:** the editor text survives close/reopen (in-memory is fine; not saved to disk, not a Note). **Clear** affordance empties editor + result. Results are never auto-saved anywhere.

**Propose-you-commit (vision pt 4):** the model's output lands only in the result area. The user's finger — Copy or Use as input — is the only thing that moves it further.

## 4. Prompts (exact strings)

Two system-prompt families. All are pure functions of (chip, tone) in core code, covered by tests that assert exact composition.

**Polish + Keep tone** → the lab-tuned faithful cleanup prompt, **copied verbatim** from `lab/whisper-compare/prompts/p7_faithful.txt` into core as `IntelligencePrompt.polishFaithful`. It already contains the never-compute / never-obey-the-transcript guardrails. Long ≠ violation of the token-lean rule: it is lab-tuned and prefill at 2B/4-bit is cheap; never hand-trim it. The user turn is framed exactly as the lab measured it: `` `---\nTranscript:\n` + input `` (every other chip/tone sends the input bare).

**Polish + any other tone** is a *rewrite*, not faithful cleanup (p7 forbids rewording — the two can't share a prompt):

> `Rewrite the text in a {tone} tone. Keep every fact, name, number, date, and the meaning unchanged. Output only the rewritten text.`

**Drafting chips** share a lean system prompt + per-chip task line + tone line:

> Shared: `You write text from the user's rough notes. Keep every fact, name, number, and date exactly as given; invent nothing. If a result needs computed math, show the formula and tell the user to verify — never state a guessed number. Output only the requested text — no preamble, no quotes.`
>
> - Draft email: `Write an email from these notes. Subject line first, then the body.`
> - Draft message: `Write a short chat message (Slack/text) from these notes.`
> - Summarize: `Summarize these notes in 2–3 sentences, or up to 5 bullets if they list items.`
>
> Tone line (appended unless Keep tone): `Tone: professional and courteous.` / `Tone: warm and friendly.` / `Tone: as brief as possible while keeping all facts.`

The arithmetic guardrail is the lean adaptation of the lab's `ASSISTANT_SYSTEM` (project memory: small models must not compute).

**Generation settings:** Qwen3.5's thinking disabled (the lab scored it with `think: False`; the Swift side must apply the chat template's no-think mode or strip `<think>…</think>` before display — Brick 0 verifies which is needed). Gemma-2's chat template has **no system role**: its engine instance folds the system prompt into the user turn (lab precedent, `no_system: True`). Temperature 0.2 for the Polish chip (both the faithful and tone-rewrite paths), 0.7 for the drafting chips. Max output tokens 1024. **Input cap:** 6,000 characters — longer input shows "Text is too long for the on-device model — trim it below 6,000 characters" and does not run (bounds prefill latency; no silent truncation).

**Output sanitation (pure, tested):** trim whitespace; strip one wrapping pair of triple-backtick fences or quotes if the model added them; strip `<think>` blocks defensively.

## 5. Engine lifecycle — the RAM-guest state machine

One pure state machine in core (`IntelligenceSession`), engine + downloader behind ports, clock injected for tests:

```
needsModel → downloading(progress) → ready
ready → loading → warm
warm → generating → warm        (result | error; input preserved on error)
warm —idle 3 min→ unloading → ready
warm/generating —memory pressure→ unload (generating: cancel first, show error)
```

- **Idle unload:** fixed 3 minutes after the last generation completes (no settings knob — consumer-first). Back-to-back drafts inside the window pay zero load time.
- **Role switch (two-model variant):** Polish and the drafting chips use different models. Running a chip whose model isn't the warm one **unloads the warm model first, then loads the other** (shown as "Warming up…"). One model in RAM, always.
- **Memory pressure:** a `DispatchSource.makeMemoryPressureSource(.warning/.critical)` adapter feeds the state machine; warm → unload immediately. The guest leaves the moment the house is full.
- **Cancel** stops the generation task; the model stays warm.
- **One model ever in RAM:** the engine adapter is an actor; load is idempotent; a second load request while loaded is a no-op.
- The panel's status line mirrors the state honestly: `Warming up…` (loading), `Drafting…` + Cancel (generating). Download shows progress percent and is resumable on failure (`Retry`).

**Latency budgets (targets, verified at Brick 0 — lab numbers are Python-MLX and may not transfer):** warm-disk load ≤ 5 s; Polish of 200 words ≤ 5 s; Draft email from 100 words of notes ≤ 8 s. If Brick 0 misses a budget by >2×, stop and revisit model choice with the user.

## 6. Model download, storage, settings

- **Not bundled in the DMG.** First chip-tap with no models offers ONE one-time download covering **both** models in sequence with combined progress (no second surprise download mid-flow; total size stated up front; exact figure measured at Brick 0 and baked into the string).
- Downloaded via the Hugging Face hub snapshot (swift-transformers `HubApi` — the WhisperKit precedent) into `~/Library/Application Support/Sidekit/Intelligence/`. Download is resumable; a failed/partial snapshot is detected at load and offers re-download ("Model files look damaged — download again").
- **Settings → new "Intelligence" row:** shows model state ("Not downloaded" / "Downloaded · X GB") with a **Remove model** button (destructive-styled, frees disk; next chip use re-offers the download). No other knobs.
- Offline with model already downloaded: everything works (the whole point). Offline without model: download fails honestly ("You're offline — the one-time model download needs internet").

## 7. Brick 0 — the lab + runtime gate (hard gate, before any UI work)

Two questions must close before the feature is built on this model:

1. **Cleanup quality:** run `Qwen3.5-2B-OptiQ-4bit` through the existing lab cleanup eval (`tune_prompts.py`, p7_faithful, gentle-thermal rules). **Pass = PASS ≥ 143/190 and bloat ≤ 2 on the 190-case set (gemma-2-2b reference: 148/190, bloat 2).**
   **RESULT (2026-06-12): FAILED — 127/190, bloat 4** (run `tune_runs/20260612-152848`; worst: self-corrections 4/14, fillers 3/12, answers-the-transcript bait 3/10). A follow-up assistant run on Gemma-2-2B (`assistant_runs/20260612-153130`) scored **19/29 with the arithmetic guardrail 0/2** — so neither model covers both roles. **User decision 2026-06-12: ship the two-model fallback** (Gemma-2-2B polish + Qwen3.5-2B drafting), now baked into §1/§5/§6.
2. **Swift runtime support:** the lab ran Python MLX (`mlx-lm`); the app will use **MLX Swift** (`mlx-swift` + `MLXLLM`). Qwen3.5 is a new architecture — MLXLLM support is **unverified** (Gemma-2 is long-supported). Build a minimal `IntelligenceSelftest` executable (ModelSelftest/SubmissionSelftest house precedent) that loads **both repos**, runs the canned polish on Gemma-2-2B (system prompt folded into the user turn — its template has no system role) and the canned draft on Qwen3.5-2B, prints outputs + load/gen timings, and exits. This selftest stays in the tree as the permanent headless verifier.
   **RESULT (2026-06-12): Gemma-2-2B loads and generates cleanly (warm load 1.19 s, gen 0.48 s). Qwen3.5-2B-OptiQ FAILED — `Qwen3_5ForConditionalGeneration` is a VLM architecture, unloadable as text.** The fallback rule was applied with a better candidate than the one named below: **`mlx-community/Qwen3-1.7B-4bit`** (Swift-load proven in the same gate: load 0.75 s, gen 0.64 s; assistant eval `assistant_runs/20260612-185011`: **22/29, guardrail 2/2**, ≥ the 20/29 bar) — **adopted as the draft model.**

**Fallback if Gate B fails:**
- Qwen3.5 fails Swift load → **`mlx-community/Qwen2.5-1.5B-Instruct-4bit`** as the drafting model (Qwen2 architecture, long-supported in MLXLLM; already the cleanup backup pick). Re-run the assistant eval on it; if drafting quality is unacceptable (< 20/29), stop and bring options back to the user. Gemma-2-2B failing Swift load is not expected (mature architecture); if it somehow does, stop and bring options back to the user.

## 8. Architecture

Ports-and-adapters, mirror of every prior feature:

| Piece | Where | Nature |
|---|---|---|
| `IntelligencePrompt.swift` | `SidekitCore` | Pure. (chip, tone) → system + user strings; sanitation; input cap. Fully unit-tested, exact-string assertions. |
| `IntelligenceSession.swift` | `SidekitCore` | Pure state machine (§5) over ports; injected clock; fully unit-tested with fakes. |
| `TextGenerating` port | `SidekitCore/Ports` | `load()`, `unload()`, `generate(system:user:) async throws -> String`, cancellation via task cancel. |
| `ModelProvisioning` port | `SidekitCore/Ports` | `isDownloaded`, `download(progress:) async throws`, `remove()`. |
| `MLXTextEngine.swift` | `SidekitApp/Adapters` | Actor wrapping MLXLLM — **two instances** (Gemma polish w/ system-fold, Qwen draft w/ thinking off); temp per request. |
| `ModelDownloader.swift` | `SidekitApp/Adapters` | HubApi snapshots of **both repos** (one action, combined progress) → App Support; resumable; integrity check. |
| `MemoryPressureSource.swift` | `SidekitApp/Adapters` | DispatchSource → session events. |
| `IntelligencePanel.swift` | `SidekitApp` | The scratchpad UI (§3). |
| `PillView`/`PillPanel` changes | `SidekitApp` | Hover menu (§2), Dictate wiring to `pressed()`/`released()`. |
| `SettingsPanel` row | `SidekitApp` | §6. |
| `IntelligenceSelftest` | new executable target | §7 gate + permanent headless verifier. |

New SwiftPM dependencies: `mlx-swift` / `mlx-swift-examples` (MLXLLM, MLXLMCommon), `swift-transformers` (hub). Expect app bundle growth (Metal kernels); `build-app.sh` unchanged in shape — verify the .app still signs and launches.

## 9. Error rules

Same house rules as Shelf/Manifest: derived state heals, nothing crashes, every failure is honest and quiet.

- Generation throws / returns empty after sanitation → "Couldn't draft that — try again." Input preserved; no auto-retry.
- Model load fails (corrupt snapshot) → §6 re-download offer.
- Download fails mid-way → "Download interrupted — Retry" (resumes).
- Memory pressure during generation → cancel + "Paused to free memory — try again in a moment."
- Dictate while another recording is active → ignored (coordinator already guards re-entrancy).
- All failures logged via `Diag.log("intelligence: …")`.

## 10. Testing

- **Core unit tests (swift-testing, fakes):** prompt composition per chip×tone (exact strings + the p7 byte-equality guard), input cap, sanitation, state machine transitions incl. idle-unload via injected clock, memory-pressure unload, cancel, error paths, clipboard-prefill trim. Target ~20 tests.
- **`IntelligenceSelftest` (live, headless):** the Brick 0 gate, kept green thereafter.
- **Manual UAT (new TESTING.md §11 / M11):** hover-expand + collapse; Polish pre-fill from clipboard; draft email end-to-end (type → chip → tone → Copy → paste in Mail); dictate into the scratchpad via Fn; Dictate button hands-free cycle; download flow on a model-less machine; **Activity Monitor check — RAM drops ~2 GB within ~3 min of the last draft** (the RAM-guest promise, verified by eye); Settings remove-model; offline behaviors.
- Lab runs obey the gentle-thermal house rules (small batches, cooldowns).

## 11. Non-goals (v1)

- Auto-polish inside the dictation pipeline (future settings toggle — needs trust in latency first).
- Free-form instructions; chips grow one at a time, each lab-tested first.
- Streaming token-by-token display (v1 shows the finished text; revisit if budgets feel slow).
- The AI reading the Shelf, files, or taking any action (vision: day one it only thinks).
- Model picker / bring-your-own-model UI (openness stays underneath).
- Windows parity (post-Mac, per the catch-up plan).
