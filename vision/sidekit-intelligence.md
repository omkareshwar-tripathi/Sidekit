# Sidekit Intelligence

> **One line:** the **local AI brain inside the Sidekit surface** — starts small,
> gains tools over time, and **only ever runs on your own device**.

This is not a new product and not a marketplace. It's the *intelligence* part of Sidekit
(today's "Polish + Drafting"), named and given a direction: an on-device AI that does more
and more for you, while never leaving your laptop.

Status: 🔵 **Vision / direction only.** The first model is being built; the rest of the
decisions below are deliberately deferred until we actually build the intelligence.

---

## The spine (committed)

1. **The brain inside the surface — made open and tunable over time.** Sidekit Intelligence
   is the AI that powers the surface. It begins with the first local model and grows by
   gaining **tools** — small capabilities it can use (clean text, draft an email, later:
   read the shelf, etc.). It is *inside* Sidekit, not a separate app.

2. **Only ever local AI. This wall never moves.** Every bit of intelligence runs on-device.
   Local-only is not a feature or a setting — it's the boundary everything stays inside.

3. **Day one it only *thinks*, not *acts*.** At launch the intelligence is pure text work —
   **Polish** (clean what you dictated) and **Drafting** (speak an intent, get written text).
   It does **not** take actions on your machine yet. But it's built behind a clean seam, so
   the *next* capability is the first walk through a real "tool" interface.

4. **Forever human-in-the-loop: it proposes, you commit.** The AI never acts unattended. It
   *suggests* — drafts, stages, offers — and **you click to commit.** "Automate your life"
   means it removes the grunt-work and stages the action; your finger stays on the button.
   Goal-driven autonomous execution is **ruled out** of this vision.

5. **Consumer-first; openness lives underneath.** Sidekit ships a great default local model
   and Just Works — no config required. "Open / tunable / bring-your-own-model" is a
   **promise underneath** (no lock-in, runs on your hardware, swap if you care), not a wall
   of knobs on the front door. "Just put it on your laptop and get started" means installing
   *Sidekit*, not assembling your own AI from parts.

## Deferred — grill these when we build the intelligence

- **What "open-source" actually commits to:** open *ingredients* + no lock-in (proprietary
  app) vs. public app code vs. open *engine* / closed app. Stated as a *value* for now, not a
  license.
- **The tool roadmap:** the order in which the AI gains tools after launch, and what each one
  is allowed to touch.
- **The permission / trust model:** how a tool gets granted, surfaced, and revoked — including
  whether narrow, named actions could ever earn a standing "don't ask me each time."

## Where this sits

This extends [`README.md`](README.md)'s "Polish + Drafting" capability and the
"agent-open surface" principle. It does not change the launch (SpeakType + Shelf + Mirror,
2026-06-10) — it names where the *intelligence* is headed after it.
