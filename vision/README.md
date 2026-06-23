# Vision — Sidekit

> **🚀 Launching 2026-06-10 (macOS):** the first **Sidekit** — **SpeakType** dictation +
> the **Shelf** + the **Mirror**, in one always-on-top surface. Built to beat anything in its lane.

> **North star:** **Sidekit** is the **always-on-top companion surface** for your desktop — one place,
> always a click away, where you **speak, stage, and check** before you act, with every bit of
> intelligence running **on your own device**. And the whole surface is **open to your AI agents**.

This folder is the long-horizon record of *where we're going* — deliberately separate from the
day-to-day build log (`BRICKS.md`) and the shipped-feature specs (`docs/superpowers/specs/`).
`BRICKS.md` answers "what are we building this week"; this folder answers "what are we building
toward, and why." Read this when a decision needs to be checked against the bigger picture.

> **This is a living document — and the vision we commit to.** The *path* can change; the
> *destination* is the commitment: a single, on-device, agent-open companion surface called Sidekit.
> When something changes, update the status table below.

---

## What changed (and why this doc was rewritten)

**SpeakType is no longer the product — it's a feature inside the product.** The product is **Sidekit**:
an always-on-top side surface you summon mid-task and let go of. Open it and you get three things at
once — your **dictation** (SpeakType), a temporary **Shelf** for files, and a **Mirror** for a
pre-call glance. Sidekit is the bracket; SpeakType, the Shelf, and the Mirror live inside it. Nothing
from the old vision was deleted — capabilities that fit the surface moved *into* the Sidekit bracket,
and the one that doesn't (the mobile keyboard) is kept as a separate sibling that shares the same core.

## The one-paragraph pitch

**Sidekit sits at the top of your screen, always within reach.** Click it and the surface opens: a
**mirror** to check yourself before a call, a **shelf** to park files and folders for a few minutes
(or a day) and grab them wherever you need, and your **voice** — hold a key, talk, and clean,
correctly-written text appears wherever you're typing, processed entirely on your device. Over time
the surface gains on-device **drafting** (speak an intent, get a written email) and a **universal
clipboard** so what you copy on one device shows up on the others. And because it's a surface — not a
black box — **your AI agents can use it too**: they hand files to you and take files from you through
the very same shelf you do. One trusted surface, on every desktop you own.

## What's inside the Sidekit bracket

Everything here is part of the **always-on-top surface** and is **on-device** and (as it matures)
**agent-accessible**.

| Capability | One line | Platforms | Status |
|---|---|---|:--:|
| [**SpeakType** — dictation](pillars/1-mvp-desktop-dictation.md) | Hold a key, speak, clean text appears — the surface's voice | Mac (now) · Windows (next) | 🟠 Building |
| [**Shelf**](pillars/5-shelf.md) | Park files/folders temporarily; grab them anywhere; clears itself | Mac (now) · Windows (next) | 🟠 Building |
| [**Mirror**](pillars/5-shelf.md#mirror) | One-click front-camera self-view before a call | Mac (now) · Windows (next) | 🟠 Building |
| [**Polish + Drafting**](scratchpad-and-polish.md) | On-device intelligence: clean/format what you said, then *write* new text | Mac · Windows | 🟡 Polish proven · 🔵 Drafting vision |
| [**Universal clipboard**](pillars/4-universal-clipboard.md) | Copy on any device → available on the others; flows through the surface | All four | 🔵 Vision |
| **Agent access** | The shelf + surface are open to local AI agents (mechanism TBD) | Mac · Windows | 🔵 Vision |
| **Open agentic intelligence** | Fine-tune small on-device models to beat frontier models at narrow tasks, wrapped in an agentic harness — and released open-source | Mac · Windows | 🟡 proven-in-lab · 🔵 open-source vision |

**Status legend:** 🔵 Vision · 🟡 Designing / proven-in-lab · 🟠 Building · 🟢 Shipped

## Kept separate — the sibling that shares the core

| Capability | One line | Platforms | Status |
|---|---|---|:--:|
| [**Mobile keyboard**](pillars/3-mobile-keyboard.md) | iOS/Android keyboard: voice typing, Whisper + correction (**no LLM**) | iOS + Android | 🔵 Vision |

The mobile keyboard is **not** part of the Sidekit surface — a phone keyboard is a different form
factor, not an always-on-top desktop panel. But it **reuses Sidekit's shared dictation + correction
core**, so it stays in the vision as a sibling product, not a deletion.

## The agent-open surface (the new idea)

Sidekit isn't only for you. The same surface you use is **open to the AI agents working on your
behalf** — and the **shelf is the meeting point**. An agent can drop a file it produced onto your
shelf for you to pick up; you can shelve a file *for* an agent to take and act on. It's a visible,
human-readable handoff zone between you and your agents, instead of an invisible pipe.

This is **stated as direction, not a shipped mechanism** — we're committing to "the surface is open to
local agents," and leaving *how* (a local API, an MCP-style interface, etc.) open until we build it.
The mirror stays human-only (it's a live camera); the shelf, clipboard, and dictation are the parts
that make sense to share.

## How it all fits together

```
                  ┌───────────────────────────────────────┐
                  │   THE SHARED DICTATION CORE            │
                  │   Whisper → text-correction pipeline   │
                  │   (SymSpell → CNN-BiLSTM → GECToR)     │
                  └───────────────────────────────────────┘
                       │  runs everywhere this core lives  │
            ┌──────────┘                                   └──────────┐
            ▼                                                         ▼
 ┌───────────────────────────────────────────┐          ┌──────────────────────────┐
 │   SIDEKIT  — the always-on-top surface    │          │  MOBILE KEYBOARD (sibling)│
 │   (Mac now · Windows next)                │          │  iOS · Android            │
 │                                           │          │  voice typing only —      │
 │   SpeakType · Shelf · Mirror              │          │  NO LLM                   │
 │   + Polish/Drafting · Universal clipboard │          └──────────────────────────┘
 │   ───────────────────────────────────     │
 │   OPEN TO AI AGENTS (shelf = handoff)     │
 └───────────────────────────────────────────┘
```

- **The text-correction pipeline is the shared spine** — Sidekit *and* the mobile keyboard run it, so
  it must stay portable. Full detail: [text-correction-pipeline.md](text-correction-pipeline.md).
- **Drafting (the bigger LLM) is desktop-only**, added on top of dictation inside Sidekit. Phones get
  voice typing, not drafting.
- **Universal clipboard rides the surface** — files and clips flow through the same place the shelf
  lives, and it only pays off once a phone and a laptop are both in it.
- **Agent access is a property of the whole surface**, layered on once Sidekit's core features are
  solid.

## Principles that carry over

1. **On-device by default.** Dictation, correction, Polish, and any drafting LLM all stay local.
   Privacy is the product, not a setting. Any cloud touch is opt-in and named.
2. **Invisible until summoned.** Always at the top of the screen, one click away — open it, use it, let
   it go. A held key, a shelf that appears on drag, a mirror you glance at and dismiss.
3. **Open, not opaque.** The surface is legible to your agents the same way it's legible to you — the
   shelf you can see is the shelf an agent uses.
4. **Brick-led delivery.** Each capability earns its own spec → plan → bricks (the `CLAUDE.md` loop).
   This folder feeds that discipline; it never replaces it.
5. **Small, specialized, and open.** The on-device intelligence is built by *supervised fine-tuning of
   small models* (LoRA/QLoRA on Apple MLX) to **beat frontier models at narrow tasks** — wrapped in an
   agentic harness and released **open-source**. The bet, stated honestly: a tuned small model you *own*
   can beat a big one you *rent*, and giving the recipe away is the strength, not the leak.

## Open strategic questions (unresolved — don't silently decide)

- **Agent interface:** what *is* the mechanism by which agents reach the shelf/clipboard/dictation — a
  local API, an MCP server, something else? What's the permission/trust model so an agent can't take a
  file you didn't mean to share?
- **One surface, two desktops:** Mac (Swift) and Windows (C#) are separate forks today. As Sidekit
  grows, do they stay native-per-platform on a shared core, or converge — the pivotal architecture call.
- **What syncs the devices?** Universal clipboard (and a future cross-device shelf) need a transport:
  local-network P2P (most private) vs. an optional encrypted relay. No-account vs. account.
- **Local LLM quality bar:** is a desktop-runnable model good enough to draft a send-able email?
- **iOS keyboard memory limit:** can Whisper run in the keyboard extension, or must it move to the
  containing app? Shapes the mobile sibling.

## Where this lives relative to the rest of the repo

- `vision/` *(this folder)* — the Sidekit north star and per-capability intent. Evolves as we learn.
- `vision/ROADMAP.md` — the build order (launch first, then the horizon) and the risk spikes that gate it.
- `vision/WEBSITE-BRIEF.md` — the single source of truth for the marketing site (sidekit.app): pitch, features, tech story, visual identity, and messaging pillars.
- `vision/text-correction-pipeline.md` — the shared Whisper→SymSpell→CNN-BiLSTM→GECToR spec.
- `vision/scratchpad-and-polish.md` — the on-device Polish + (future) Drafting intelligence.
- `vision/pillars/` — one file per capability (kept under the old "pillar" filenames; re-bracketed here).
- `docs/superpowers/specs/` — concrete, decision-resolved designs for things we're actually building.
- `BRICKS.md` — the active build queue and handoff log.
- A capability graduates: **vision → brainstormed spec in `docs/.../specs/` → bricks in `BRICKS.md` →
  shipped.** Update the status tables above as each one moves.
