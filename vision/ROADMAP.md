# Roadmap — Sidekit

The **order** we build [Sidekit](README.md) in, and why. The capability docs say *what* and *why*;
this says *when*.

> **Living document.** This roadmap evolves as we learn — reorder, split, drop, or add. What stays
> fixed is the **north star**: one on-device, agent-open companion surface. When you move a step,
> update its status here **and** in the [README tables](README.md).

**Status legend:** 🔵 Vision · 🟡 Designing / proven-in-lab · 🟠 Building · 🟢 Shipped

---

## Step 0 — Launch (macOS), 2026-06-10

**Ship the first Sidekit:** the always-on-top surface on **macOS**, with the three features that make
it a surface worth opening —

| Feature | What ships at launch |
|---|---|
| [**SpeakType** — dictation](pillars/1-mvp-desktop-dictation.md) | Hold-to-speak, clean text into any app, on-device |
| [**Shelf**](pillars/5-shelf.md) | Drop files/folders in, drag/copy out, auto-clears |
| [**Mirror**](pillars/5-shelf.md#mirror) | One-click front-camera self-view before a call |

- **Mac only.** Mac is the active branch and the shipped dictation base; Windows parity is the next
  horizon, not the launch.
- **Agent access and drafting are *not* in this build** — they're the near-term direction (below), and
  the launch already stands on its own without them.
- **Goal:** beat anything in the always-on-top-utility lane on day one — dictation + shelf + mirror in
  one trusted, on-device surface.

---

## The horizon (after launch)

| Step | Capability | What ships | In Sidekit? | Status |
|:--:|---|---|:--:|:--:|
| **1** | [Windows parity](pillars/1-mvp-desktop-dictation.md) | The Sidekit surface (SpeakType + Shelf + Mirror) on **Windows** | ✅ | 🔵 Vision |
| **2** | [Polish + Drafting](scratchpad-and-polish.md) | On-device clean/format, then *writing* new text from a spoken intent | ✅ | 🟡/🔵 |
| **3** | **Agent access** | The shelf + surface opened to local AI agents (mechanism TBD) | ✅ | 🔵 Vision |
| **4** | [Universal clipboard](pillars/4-universal-clipboard.md) | Copy on any device → available on the others; flows through the surface | ✅ | 🔵 Vision |
| **5** | [Mobile keyboard](pillars/3-mobile-keyboard.md) | **iOS + Android** voice typing, Whisper + correction, **no LLM** | ❌ sibling | 🔵 Vision |

The "In Sidekit?" column is the test from the [README](README.md): is it part of the always-on-top
desktop surface agents can drive? The mobile keyboard isn't — it's a separate sibling that **reuses the
shared dictation + correction core**.

### Step 1 — Windows parity

Bring the full Sidekit surface to **Windows** so the product is one experience across both desktops,
running the [text-correction pipeline](text-correction-pipeline.md): **Whisper → SymSpell → CNN-BiLSTM
→ GECToR**. Mac is shipped; **Windows is the open work**.

### Step 2 — Polish + Drafting (the surface's intelligence)

The on-device LLM layer of the surface. **Polish** (clean/format what you already said) is **proven in
the lab** — model picked, prompts tuned — and just needs wiring in. **Drafting** (speak an intent, get
a written email/message/doc) is the headline differentiator and the bigger lift.

- **Distinct layers:** the correction pipeline *cleans what you said* (every platform); Polish
  *reshapes* it; Drafting *writes new text* (desktop only). See [scratchpad-and-polish.md](scratchpad-and-polish.md).
- **Gating spike:** *is a desktop-runnable local model good enough to draft a send-able email?*

### Step 3 — Agent access

Open the surface to the AI agents working on your behalf, with the **shelf as the handoff zone** — an
agent drops a file for you; you shelve one for it. Committed as direction; the *mechanism* (local API
vs. MCP-style interface) and the **permission/trust model** are the open design.

### Step 4 — Universal clipboard

Copy on any device → **automatically available on all your other devices**, cross-ecosystem (Samsung
phone → Windows laptop, iPhone → Mac). It flows through the same surface the shelf lives on, and only
pays off once both a desktop and a mobile endpoint exist — the heaviest shared infra (pairing,
identity, end-to-end-encrypted transport).

### Step 5 — Mobile keyboard (sibling)

A **keyboard extension** for phones doing **voice typing**: Whisper + the same text-correction
pipeline, **no LLM**. Not part of the desktop surface, but it reuses Sidekit's core.

- **Why a keyboard:** mobile OSes forbid the desktop's global-hotkey/paste trick; being the keyboard is
  the only way to type into any app.
- **Gating spike:** *does Whisper fit inside an iOS keyboard-extension's memory budget, or must
  inference move to the containing app via an App Group?*

---

## The dependency spine

```
Step 0  LAUNCH — Sidekit on macOS (SpeakType + Shelf + Mirror)
   └─→ Step 1  Windows parity (same surface, second desktop)
   └─→ Step 2  Polish + Drafting (the surface's on-device intelligence)
   └─→ Step 3  Agent access (shelf = human↔agent handoff)
   └─→ Step 4  Universal clipboard (needs a desktop + a mobile endpoint)
Step 5  Mobile keyboard = sibling, reuses the shared core, anytime
```

## Two rules that hold across every step

1. **Spike the risk before the build.** The gating spikes — "can a local model draft an email?"
   (Step 2) and "does Whisper fit an iOS keyboard?" (Step 5) — are cheap to test and expensive to
   discover late.
2. **Keep the text-correction pipeline portable from day one.** The desktop surface *and* the mobile
   sibling both run it — it's the shared spine. Today's separate Mac/Windows forks are fine, but don't
   let them deepen the divergence.

## How a step moves through this roadmap

```
🔵 Vision  →  🟡 spec in docs/superpowers/specs/  →  🟠 bricks in BRICKS.md  →  🟢 Shipped
```

Same brick-led loop as the rest of the repo. This roadmap sets the *order*; each capability earns its
own spec, plan, and bricks when its turn comes.
