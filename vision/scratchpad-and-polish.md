# Feature — Scratchpad + Polish (Mac + Windows)

**Status:** Scratchpad 🟢 shipped (Mac, plain-text) · Polish 🟡 proven in the lab, not yet wired ·
**Platforms:** macOS + Windows (desktop) · **Rides on:** [Pillar 1](pillars/1-mvp-desktop-dictation.md)
(dictation) + a small on-device LLM

Part of **Sidekit's on-device intelligence** — it sits on top of the dictation feature and uses a small
local model. Two halves of one idea. (The heavier, generative half — writing *new* text — is
[Drafting](pillars/2-desktop-local-llm.md); together they're the "Polish + Drafting" capability in the
[Sidekit bracket](README.md).)

## What it is

- **Scratchpad** — a floating notes surface where dictated text lands and *accumulates*, instead of
  going straight into whatever app you're in. A holding pen you can read and edit before the text goes
  anywhere. (Shipped on Mac today as plain text.)
- **Polish** — a one-action, on-device cleanup of whatever's in the scratchpad. It removes fillers,
  fixes casing and punctuation, resolves spoken self-corrections ("send it to John, no Sarah" →
  "Sarah"), and — on request — formats a spoken list or steps into bullets/numbers. It reshapes *your*
  words; it never answers, summarizes, or invents, and never changes a number, name, or date.

Together: speak freely into the scratchpad, then Polish it into clean, well-laid-out text ready to copy
anywhere.

## Two modes

- **Clean (default, fast):** faithful cleanup — fillers out; casing, punctuation, and homophones
  fixed; self-corrections resolved; every other word preserved exactly. The everyday pass.
- **Format (opt-in):** restructure a spoken brain-dump into bullets, numbered steps, or a
  "Label: value" layout — turning *"low is 0.2 medium 0.3 high 0.4"* into a tidy list, numbers kept
  exact.

Clean is safe to run on anything; Format deliberately *reshapes*, so it's a separate action, never the
silent default.

## How it differs from the other two on-device "AI" layers

Three distinct layers — don't conflate them:

- **Text-correction pipeline** ([Pillar 1](text-correction-pipeline.md)) — fixes typos/punctuation
  deterministically *as you dictate*. Small, non-generative, runs on every platform.
- **Polish** (this feature) — a small on-device *LLM* doing a smarter cleanup + optional formatting on
  a whole note. Desktop only. Reshapes words you already said.
- **Drafting** ([Pillar 2](pillars/2-desktop-local-llm.md)) — writes *new* text from an instruction
  ("write the email"). A bigger generative model.

The short version: the pipeline *corrects*, Polish *reshapes*, Draft *writes*. Polish is the lighter,
lower-risk cousin of Pillar 2 — same on-device-LLM muscle, but it only ever rearranges your own words.

## The model behind it (decided 2026-06-09)

Runs fully on-device. **Gemma-2-2B is primary; Qwen2.5-1.5B is the speed/RAM backup** — chosen on a
190-case cleanup battery (Gemma led **148 vs 134**) and a 16-note formatting battery (**12 vs 9**),
with every decimal/price/version kept exact on both. The tuned cleanup instruction is `p7_faithful`
("clean, don't summarize — remove only fillers and the abandoned half of a correction"); a separate
permissive prompt drives Format mode. Trade-off: Gemma is more faithful but ~2–3× slower and ~0.7 GB
heavier than Qwen. Bench, prompts, and evidence live in `lab/whisper-compare/`.

## Where we are today

- **Scratchpad:** shipped on Mac (plain text — the [UI redesign spec](../docs/superpowers/specs/2026-06-04-speaktype-mac-ui-redesign-design.md)
  parks rich formatting as future work). Windows: not yet.
- **Polish:** the cleanup + formatting capability is **proven in the lab** (model picked, prompts
  tuned) but **not yet wired into the apps** — that integration is the next step.

## Open questions (unresolved — don't silently decide)

- **Trigger:** a Polish button on the scratchpad vs. auto-clean on dictation-stop vs. both. (Clean
  could be automatic; Format is almost certainly a deliberate button.)
- **Always keep the original:** Polish must be undoable / show the raw text — it's an LLM touching your
  words, so the unpolished version can never be silently lost.
- **Scope:** scratchpad-only, or also an inline "polish what I just dictated" before paste in any app?
- **Rich text:** does Format emit markdown, or does the scratchpad gain real rich-text so bullets
  render?
- **Default model per mode:** Gemma (better) vs Qwen (faster) — which backs Clean vs Format?

## What "done" looks like

You hold to talk; your words pile into the scratchpad rough and unpunctuated; you hit Polish; a moment
later it's clean, correctly cased, and — if you asked — laid out as a tidy list with every number
intact, all on your own machine. Then you copy it wherever it's going.
