# Drafting — Desktop local LLM (inside Sidekit)

**Status:** 🔵 Vision · **Platforms:** macOS + Windows (desktop only) · **In Sidekit:** ✅ — the surface's intelligence (with [Polish](../scratchpad-and-polish.md))

## What it is

Add an **on-device language model** to the desktop apps — the intelligence layer that **drafts**:
emails, messages, documents, replies, summaries, rewrites — from a spoken instruction, all running
**locally** (no cloud, nothing leaves the machine). This is the leap from *"type what I said"*
(Pillar 1) to *"write this for me."*

It builds directly on the MVP: dictation captures your **instruction**, and the LLM acts on it
instead of just transcribing it.

## Why it's second

It's the **headline differentiator** — a private, on-device assistant that drafts for you — and it
reuses everything the MVP established (the desktop apps, the model-bundling muscle, the privacy
story). No new platform, so it's the highest-value next step at the lowest new risk.

## How it differs from the text-correction pipeline

Don't confuse the two on-device "AI" layers:

- The [text-correction pipeline](../text-correction-pipeline.md) (Pillar 1) **cleans what you said** —
  small, fast, non-generative models. Runs on every platform.
- This **LLM generates new text** — "write the email." Bigger, generative, **desktop-only**.

There's also a **third, lighter layer between them**: [Polish](../scratchpad-and-polish.md) uses a
*small* on-device LLM to clean and optionally format dictated text you already spoke. The short version
— the pipeline **corrects**, Polish **reshapes** your words, this pillar's model **writes** new ones.
Polish is the lower-risk cousin and can land before full drafting.

## Where we are today

- Speech-to-text already runs locally (Whisper). **No text-generation LLM yet** — this capability is
  entirely ahead of us.
- We already **bundle, store, and load on-device models**, so shipping a local LLM extends a pattern
  we understand.

## Dependencies

- **Pillar 1 (MVP)** — needs the working dictation product to sit on.
- An on-device generation model good enough to draft acceptably (the gating risk — see below).

## Open questions & the gating risk

- **The spike:** *Is a desktop-runnable local model actually good enough to draft an email someone
  would send?* Answer this before committing — it decides how ambitious this pillar can be.
- **Trigger model:** a separate "agent" mode/hotkey vs. interpreting intent automatically?
- **How much agency:** draft-and-confirm (human always sends) vs. taking real actions. Privacy +
  trust argue for draft-first.
- **App integration:** placing a draft into Mail / Outlook / Slack via accessibility/paste (shallow,
  universal) vs. per-app integrations (deep, costly).
- **Model size vs. machine:** one model across all desktops, or scale by hardware.

## What "done" looks like

You speak an intent in plain language on your Mac or PC; a model running entirely on your own
hardware drafts the email/message/document and hands it to you ready to edit or send — fast, private,
no cloud.
