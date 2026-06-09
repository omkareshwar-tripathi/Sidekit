# Shelf + Mirror (inside Sidekit)

**Status:** 🟠 Building — **launching on Mac 2026-06-10** · **Platforms:** macOS (now) + Windows (next) · **In Sidekit:** ✅ — two of the three launch features

## What it is

A temporary **shelf for files**. When you're moving files around, you drop them onto the shelf — a
small, always-reachable holding spot — and later drag or copy them out into **any folder or any app**.
Pick things up here, drop them there, on your own schedule, without juggling two windows.

**Retention:** the shelf holds items **temporarily** — roughly **1–2 days**, and/or **until you've
used (copied/moved) the file out**. Then it clears itself. It's a transient staging area, not storage.

(Prior art people will recognize: Dropover / Yoink / the iPadOS drag-and-hold shelf.)

## Why it's flexible in the order

The shelf depends on **nothing** and **nothing depends on it** — it's a self-contained desktop
quality-of-life feature. So it's listed last because it never *blocks* anything, **but it can be
pulled forward** and built earlier (e.g. as a satisfying, lower-risk win between the heavier phases)
whenever there's appetite.

## How it might work (high level — not a design)

- A floating, dismissible **shelf surface** (a sibling in spirit to the desktop floating pill) that
  appears when you start dragging files, or via a hotkey/menu.
- Drag files **in** → the shelf holds them temporarily (copies or references — see open questions).
- Drag/copy files **out** to any folder or app → placed there.
- **Auto-expiry:** items clear after ~1–2 days or once they've been taken out.

<a id="mirror"></a>

## Mirror — quick self-view (camera)

The shelf surface also hosts a small **mirror** at the top. Click it and the shelf shows a live
**front-camera** view — a one-click "how do I look?" check. **Expand** it to a larger panel when you
want a proper look (fix your hair, straighten your collar, check the lighting) **right before a
meeting**, then collapse it back to the shelf. It's a *glance* tool, not a camera app — no capture, no
recording, just a live self-view you summon in one click and dismiss just as fast.

**Why it lives on the shelf:** the shelf is already the always-reachable, floating surface you summon
mid-task and let go of. A pre-meeting touch-up is the same kind of "quick, then gone" moment — so it
rides the same surface instead of becoming yet another app or window to manage. (The pillar grows from
a *file* shelf into a small **"quick utilities" surface**; files are the first and primary citizen,
the mirror the second.)

## Dependencies

- Native drag-and-drop integration on each desktop OS (deep, platform-specific work).
- *Could* later ride the [universal clipboard](4-universal-clipboard.md) transport so the shelf spans
  devices ("shelve on the laptop, grab on the phone") — a stretch goal, not the first version.

## Open questions

- **Copies vs. references:** hold temporary copies of files, or pointers to their originals? (Affects
  what happens if the source moves/deletes before the shelf clears.)
- **Exact retention rule:** fixed ~1–2 day timer, clear-on-use, or both (whichever comes first)?
- **Invocation:** appear automatically on drag-start, summoned by hotkey/menu, or both?
- **Cross-device shelf:** later, or kept strictly local to one machine for v1?
- **Mirror — camera permission & privacy:** request the camera *only* when the mirror is opened, show
  a clear in-use indicator, and never record or store frames (macOS prompts for camera access on first
  use). Does the mirror ship with v1 of the shelf, or arrive as a fast follow-on?
- **Mirror — default size & flip:** small inline preview by default with one click to expand (remember
  last size?); show a true left-right mirrored image like a real mirror?

## What "done" looks like

You start dragging a cluster of files, a shelf slides in, you drop them and let go. Minutes (or a
day) later, in a different app, you flick them off the shelf into place — and anything you never used
quietly clears itself out. And just before a call, you tap the mirror at the top of the shelf, glance
at yourself, fix your collar, and dismiss it — no camera app, no fuss.
