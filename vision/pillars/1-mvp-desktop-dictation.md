# SpeakType — Desktop dictation (inside Sidekit)

**Status:** 🟠 Building (Mac launching 2026-06-10, Windows next) · **Platforms:** macOS + Windows · **In Sidekit:** ✅ — the surface's voice

## What it is

The foundation: the **Whisper-based dictation app we already have**, finished and shipped on **both
Mac and Windows**. Hold a key, speak, and clean text appears where you're typing — fully on-device.
"Clean" means it runs through the [text-correction pipeline](../text-correction-pipeline.md)
(Whisper → SymSpell → CNN-BiLSTM → GECToR), so the output reads like written English, not a raw
transcript.

This is the **MVP** — the smallest complete product that stands on its own and that everything else
builds on.

## Why it's first

It's the base of the whole vision. The local LLM (Pillar 2), the mobile keyboard (Pillar 3), and the
cross-device features (Pillars 4–5) all assume a working, trustworthy dictation product exists. Ship
the core, on both desktops, before adding anything on top.

## Where we are today

- **macOS:** native Swift app (`SpeakTypeMac/`) — dictation + floating pill + scratchpad **shipped**
  (plain text today; gaining a one-tap **Polish** — see [Scratchpad + Polish](../scratchpad-and-polish.md)).
- **Windows:** native C# app (`SpeakType.*/`) — dictation exists; **finishing/shipping is the open
  work** for this milestone.
- **Text correction:** today's apps do a *basic* cleanup; maturing it into the full three-model
  [pipeline](../text-correction-pipeline.md) is part of completing the MVP.

## Scope of "done" for the MVP

- Reliable hold-to-speak dictation on **both** platforms, at parity.
- The full text-correction pipeline producing clean, punctuated, grammatical text.
- On-device and private — no transcript leaves the machine.
- Shippable: installer/bundle, permissions, launch-at-login, the basics a real user needs.

## Dependencies

- None upstream — this is the starting point.
- Establishes the **portable text-correction core** that Pillar 3 (mobile) will reuse, so building it
  cleanly here pays off later.

## Open questions

- What's the remaining gap to call **Windows** "shipped" at parity with Mac?
- How much of the full pipeline (SymSpell / CNN-BiLSTM / GECToR) lands in the MVP vs. as a fast follow?
- Distribution: signing/notarization (Mac) and installer/SmartScreen (Windows) for real users.

## What "done" looks like

A person on either a Mac or a Windows PC installs SpeakType, holds a key, talks, and gets clean,
correctly-punctuated text in any app — privately, on their own device. The product is genuinely
usable and shippable on its own, before a single advanced feature is added.
