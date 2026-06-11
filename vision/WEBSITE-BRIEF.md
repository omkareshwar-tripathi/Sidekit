# Website Brief — Sidekit (sidekit.app)

> **Purpose:** the single source of truth for the marketing site (sidekit.app). Everything a
> designer/copywriter needs to build the landing page, distilled from the [vision README](README.md),
> the [roadmap](ROADMAP.md), the per-capability [pillars](pillars/), and the shipped Mac app's
> design specs (`docs/superpowers/specs/`). When the product changes, update this **and** the source
> docs it draws from.

**Status legend:** 🔵 Vision · 🟡 Designing / proven-in-lab · 🟠 Building · 🟢 Shipped

---

## 1. The one-liner

**Sidekit is the always-on-top companion surface for your desktop** — one place, always a click away,
where you **speak, stage, and check** before you act, with every bit of intelligence running **on your
own device**. And the whole surface is **open to your AI agents**.

- **Name:** Sidekit · **Domain:** sidekit.app
- **Launched:** macOS, 2026-06-10. Windows is next, not yet shipped.
- **Category:** always-on-top desktop utility surface (the lane of Wispr Flow, Dropover, Yoink — but
  unified and on-device).

## 2. The pitch (near-verbatim hero copy)

**Elevator.** Sidekit sits at the top of your screen, always within reach. Click it and the surface
opens: a **mirror** to check yourself before a call, a **shelf** to park files for a few minutes (or a
day) and grab them wherever you need, and your **voice** — hold a key, talk, and clean, correctly-written
text appears wherever you're typing, processed entirely on your device.

**The frame to communicate.** SpeakType (the dictation app) is **no longer the product — it's a feature
inside the product.** Sidekit is the *bracket*; SpeakType, the Shelf, and the Mirror live inside it. One
trusted surface, on every desktop you own.

## 3. What's inside the surface (the launch product = 3 features)

| Feature | One line | Status at launch |
|---|---|:--:|
| **SpeakType** (dictation) | Hold a key, speak, clean text appears in any app — the surface's voice | 🟢 Shipped (Mac) |
| **Shelf** | Drop files/folders in, drag/copy out anywhere, auto-clears itself | 🟢 Shipped (Mac) |
| **Mirror** | One-click front-camera self-view before a call | 🟢 Shipped (Mac) |

All three are **on-device** and (as the product matures) **agent-accessible**.

### SpeakType — dictation
Hold a key, speak, release → clean, punctuated, grammatical text lands wherever your cursor is. Fully
on-device — no transcript ever leaves the machine. "Clean" is the differentiator: it's not a raw
transcript, it reads like written English. There's also a **scratchpad** — a floating notes surface
where dictation can accumulate and be edited before it goes anywhere.

### Shelf
A temporary holding spot for files. Drag files in while you're moving things around; later drag or copy
them out into any folder or app. **Retention:** holds items ~1–2 days and/or until you've used them,
then clears itself. A transient staging area, not storage. (Prior art people recognize: Dropover /
Yoink / the iPadOS drag-and-hold shelf.)

### Mirror
A small live front-camera self-view at the top of the shelf. One click = "how do I look?" before a
meeting. Expand for a proper look, collapse to dismiss. **It's a glance tool, not a camera app — no
capture, no recording, ever.**

## 4. The technology story (the "on-device" spine)

The most important differentiator for the site: **privacy is the product, not a setting.**

**The shared dictation core** (runs everywhere the product lives):

```
Whisper (speech → raw text)
   ↓ SymSpell      — fixes typos / misspellings
   ↓ CNN-BiLSTM    — restores punctuation + casing
   ↓ GECToR        — fixes grammar (tag-based edits, not generative)
Result: "How are you? I am fine, thank you."
```

- The **text-correction pipeline is NOT a language model** — it's a chain of three small, fast,
  special-purpose models. That's what lets the same quality engine run on a laptop *and* (future) inside
  a phone keyboard's tight memory budget. Full detail: [text-correction-pipeline.md](text-correction-pipeline.md).
- **On-device intelligence (the LLM layer), in two tiers** — see [scratchpad-and-polish.md](scratchpad-and-polish.md)
  and [pillar 2](pillars/2-desktop-local-llm.md):
  - **Polish** — a small on-device LLM (Gemma-2-2B primary, Qwen2.5-1.5B speed/RAM backup) that cleans +
    optionally reformats what you already said. It *reshapes your words — never answers, summarizes, or
    invents, and never changes a number, name, or date.* Proven in the lab, being wired in.
  - **Drafting** — a bigger on-device generative model that *writes new text* from a spoken intent
    ("write the email"). Desktop-only. The headline future differentiator.
- **The three layers, in one phrase:** the pipeline **corrects**, Polish **reshapes**, Drafting
  **writes**. All local, no cloud, nothing leaves the machine.

**The Mac app under the hood:** native Swift, WhisperKit (runs on the Apple Neural Engine), hold-Fn
(🌐 globe key) push-to-talk, menu-bar resident. Windows is a separate native C# app on the same
conceptual core.

## 5. The agent-open idea (the novel angle)

Sidekit isn't only for you — the same surface is **open to the AI agents working on your behalf**, and
**the shelf is the meeting point**. An agent can drop a file it produced onto your shelf for you to pick
up; you can shelve a file *for* an agent to take and act on. A visible, human-readable handoff zone
between you and your agents, instead of an invisible pipe. (Committed as *direction*; the mechanism —
local API vs. MCP-style — is still open. The Mirror stays human-only.)

## 6. Principles (the brand values)

1. **On-device by default.** Dictation, correction, Polish, drafting — all local. Any cloud touch is
   opt-in and named.
2. **Invisible until summoned.** Always at the top of the screen, one click away — open it, use it, let
   it go.
3. **Open, not opaque.** The surface is legible to your agents the same way it's legible to you.
4. **Brick-led delivery.** Each capability earns its own spec → plan → bricks.

## 7. Roadmap

- **Step 0 — Launch (macOS, 2026-06-10):** SpeakType + Shelf + Mirror. 🟢 **Shipped.**
- **Step 1 — Windows parity:** the full surface on Windows. 🔵
- **Step 2 — Polish + Drafting:** the on-device intelligence layer (Polish 🟡 proven, Drafting 🔵).
- **Step 3 — Agent access:** shelf as human↔agent handoff. 🔵
- **Step 4 — Universal clipboard:** copy on any device → available on all your others, **cross-ecosystem**
  (Samsung→Windows, iPhone→Mac), end-to-end encrypted, no account. 🔵
- **Step 5 — Mobile keyboard (sibling, not in the surface):** iOS + Android keyboard extension doing
  voice typing — same Whisper + correction core, **no LLM**. 🔵

## 8. Platforms summary

| | Mac | Windows | iOS | Android |
|---|:--:|:--:|:--:|:--:|
| Sidekit surface | 🟢 now | 🔵 next | — | — |
| Mobile keyboard (sibling) | — | — | 🔵 | 🔵 |

## 9. Visual identity (from the shipped Mac app — match this on the site)

- **Aesthetic:** **frosted glass** ("glass + waveform" visual direction). Modern, light, Apple-native.
- **Signature UI element — the floating pill:** bottom-center, always-on-top, never takes focus. States:
  - **Idle** — a faint, slowly *breathing* dot/bar, low opacity.
  - **Recording** — springs open into a frosted-glass pill: red rec dot + **live waveform** (bars driven
    by real mic amplitude) + "Listening…".
  - **Transcribing** — morphs to a small spinner.
  - **Success** — a green ✓ pops ("Pasted ✓" / "Added to note ✓"), holds ~1.2 s, collapses back.
- **Motion:** the pill morphs between states, the waveform reacts live, text reveals gently — all
  respecting Reduce Motion.
- **Website visual language to carry over:** glass surfaces, a breathing/waveform motif, green-check
  success moments, bottom-anchored floating UI.

## 10. Positioning / messaging pillars for the landing page

1. **One surface, three jobs** — speak, stage, check. (Voice + Shelf + Mirror.)
2. **100% on-device** — privacy is the product. No cloud, no account, nothing leaves your machine.
3. **Clean text, not raw transcripts** — the three-model correction pipeline.
4. **Always a click away, gone when you're done** — invisible until summoned.
5. **Open to your AI agents** — the forward-looking hook (shelf = handoff zone).

## 11. Watch-outs for whoever builds the site

- The repo's root `README.md` now describes **Sidekit** as the product (with SpeakType/Shelf/Mirror as
  features), and points to the per-OS apps in `mac/` and `windows/`. It's developer-facing setup copy,
  though — accurate for framing, but don't pull marketing hero copy straight from it.
- A few facts are deliberately **unresolved** in the vision docs (exact shelf retention rule, the agent
  mechanism, what syncs the devices). Keep the site's language on those aspirational/vague rather than
  claiming specifics.
