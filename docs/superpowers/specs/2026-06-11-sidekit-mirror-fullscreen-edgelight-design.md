# Sidekit for Mac — Mirror: full-screen overlay + edge light

**Date:** 2026-06-11
**Status:** Design resolved (via brainstorm on the user's Mirror additions), pending spec review
**Scope:** Two additions to the shipped Mirror feature — a **full-screen self-view** and a **manual
edge light** (a bright-white fill-light frame for dim rooms). Builds directly on the v1 Mirror
(`2026-06-09-sidekit-mirror-design.md`, all five bricks shipped 2026-06-11). Read that first.

The Mirror is a one-tap live front-camera self-view that rides on the Shelf panel. v1 has three
states (button → small → expanded). This adds a fourth presentation (full screen) reachable by a
toggle, plus an optional bright-white frame around the preview that acts as a ring/fill light.

---

## 1. Goal & non-goals

**Goal.** Before a call, the user can blow the self-view up to **fill the whole screen** for a proper
look, and — in a dim room — flip on a **bright-white edge frame** that lights their face like a cheap
ring light. Both are one click, and both tear down the moment the Mirror collapses.

**Resolved product decisions (from the brainstorm, 2026-06-11):**

| # | Decision | Resolution |
|---|---|---|
| 1 | **What "full screen" means** | A **borderless full-display overlay** — a non-activating, always-on-top window sized to the active screen, over the current Space (NOT native macOS fullscreen / a separate Space, NOT a resizable window). Exit via a visible **✕** *and* **click-anywhere**. |
| 2 | **Full-screen entry/exit** | A **toggle** in the windowed preview's controls enters full screen; ✕ / click exits. Exiting always returns to **`.expanded`** (deterministic — no size memory, consistent with v1 decision #6). |
| 3 | **Edge light trigger** | **Manual toggle only** (a ☀ button). **No frame sampling / no auto-detect** — this preserves the Mirror's "frames are displayed, never read/captured/saved" posture. "For dim areas" describes its purpose, not an auto-trigger. |
| 4 | **Edge light look** | A **solid bright-white inset frame** around the preview: thin in the windowed preview, a **thick screen-hugging frame** in the full-screen overlay (where it does real work as fill light). |
| 5 | **Edge light persistence** | A **session preference** held in `MirrorModel` (`edgeLightOn`); it carries across small/expanded/full-screen while the Mirror stays open, and **resets to off when the Mirror collapses** (fresh each open — mirrors how `permissionDenied` resets on `dismiss()`). |
| 6 | **Camera lifecycle** | Unchanged invariant: **camera runs iff `state != .collapsed`**. Full screen is an open state, so it runs the camera; every existing exit (collapse ×, panel close, app deactivate) already collapses → camera off and overlay hidden, for free. |

**Non-goals.**
- No capture/recording (unchanged from v1 — full screen and edge light are display-only).
- No automatic dim detection, no brightness/warmth sliders, no colored light (bright white only).
- No native-fullscreen Space, no resizable detached window, no multi-display "show on all screens"
  (the overlay targets the screen the Mirror is summoned on / the main screen).
- No full-screen size memory; exit always returns to `.expanded`.

---

## 2. Behavior & states

`MirrorState` gains a fourth case: **`fullScreen`**.

- **From small/expanded** — tapping the **full-screen toggle** (`arrow.up.left.and.arrow.down.right`)
  enters `fullScreen`: a borderless overlay fades up covering the active screen with the mirrored
  self-view; the Shelf panel's strip shows a compact "Mirror is full screen" placeholder.
- **In full screen** — a visible **✕** (top-right) and **click anywhere** on the overlay exit back to
  `.expanded` (overlay fades out, the windowed preview returns). The ☀ edge-light toggle is also
  shown in the overlay.
- **Edge light** — the ☀ (`sun.max` / filled when on) toggle flips `edgeLightOn`. When on, a solid
  bright-white inset frame draws around the preview (thin windowed, thick in the overlay). Independent
  of size — toggling size keeps it on; collapsing turns it off.
- **Every v1 exit still wins** — collapse ×, Shelf panel close, and app-deactivate all call
  `dismiss()` → `.collapsed`, which hides the overlay, stops the camera, and clears `edgeLightOn`.

---

## 3. Architecture (ports-and-adapters)

### 3.1 Pure core (`SpeakTypeCore`) — tested
`MirrorState` adds `case fullScreen`. `cameraShouldRun` stays `self != .collapsed` (full screen runs
the camera). New transition **`toggledFullScreen() -> MirrorState`**: `.fullScreen → .expanded`
(exit); every other state → `.fullScreen`. `tapped()` and `dismissed()` extend to cover the new case
(`tapped()` from `.fullScreen` → `.expanded`; `dismissed()` → `.collapsed` unchanged). Unit-tested,
including that `toggledFullScreen()` round-trips and that the camera invariant holds for `.fullScreen`.

### 3.2 Adapters (`SpeakTypeApp`)
- **Second preview layer.** A single `AVCaptureVideoPreviewLayer` can live in only one view hierarchy,
  so the overlay does **not** reuse the panel's layer. `AVFoundationCamera` gains a factory
  `makePreviewLayer() -> AVCaptureVideoPreviewLayer` that builds an additional mirrored preview layer
  on the **same `AVCaptureSession`** (AVFoundation supports multiple preview layers per session). The
  overlay hosts its own; the panel keeps its own. No session is duplicated, so no second green light.
- **`MirrorOverlayPanel`** — a new borderless, `.nonactivatingPanel`, always-on-top window (same family
  as `ShelfPanel`/`PillPanel`), sized to the target screen's full frame. Shown when `state ==
  .fullScreen`, hidden otherwise; fade in/out (Reduce-Motion aware, like `ShelfPanel`). Hosts a SwiftUI
  view with the overlay preview + edge-light frame + ✕ + ☀, and a click-catcher that exits full screen.
  Owned by `MirrorModel` (or alongside it) so state drives show/hide and every `dismiss()` hides it.
- **`MirrorModel`** gains `@Published var edgeLightOn` (reset in `dismiss()`), `toggleFullScreen()`
  (routes through `MirrorState.toggledFullScreen()` + drives the overlay), and `toggleEdgeLight()`.
  The overlay's lifecycle is bound to `state == .fullScreen`.
- **`MirrorView`** (windowed strip) gains the full-screen toggle + ☀ button in the preview controls,
  the bright-white frame overlay when `edgeLightOn`, and a "Mirror is full screen" placeholder while
  `state == .fullScreen`.

### 3.3 Lifecycle wiring
`MIRROR-LIFECYCLE` already funnels every external exit through `mirror.dismiss()`. Because `dismiss()`
→ `.collapsed`, the overlay (bound to `state == .fullScreen`) hides automatically on panel close and
app-deactivate. The only new wiring is showing/hiding the overlay panel as `state` enters/leaves
`.fullScreen`, and creating it lazily (no overlay window until first full-screen entry).

---

## 4. Privacy & security
- **Still display-only.** Full screen and edge light add no capture path. The edge light is a manual
  toggle precisely so we never sample frames — the "frames are never read or saved" posture is intact.
- **One session, one green light.** The second preview layer shares the existing session; entering full
  screen does not open a second camera.
- **Tear-down unchanged.** Full screen is an open state under the same invariant, so collapse / panel
  close / app deactivate release the camera and hide the overlay.

---

## 5. Risks
1. **Two preview layers on one session.** Must confirm the overlay's layer renders mirrored and the
   panel's layer keeps working; stop displaying (remove from host) when the overlay hides so no stray
   layer retains the session. Mitigation: `makePreviewLayer()` returns a fresh layer per overlay; the
   overlay removes/releases it on hide.
2. **Click-to-exit vs. control clicks.** The overlay's click-anywhere exit must not swallow taps on the
   ✕ / ☀ controls. Mitigation: controls are buttons on top; the click-catcher sits behind them.
3. **Non-activating panel + keyboard.** A non-activating overlay may not receive key events, so **Esc
   is not relied on** — exit is ✕ + click (decision #1). Note for a later polish: a global Esc monitor
   could be added if users expect it.
4. **Overlay covering the menu bar / which screen.** Target the screen the Mirror is on (fall back to
   `NSScreen.main`); size to `screen.frame` and set a window level above normal panels. Acceptable to
   cover the menu bar while in full screen (it's a deliberate full-display mirror).

---

## 6. Brick plan (outline — full plan lands in BRICKS.md)

1. **MIRROR-FS-CORE** — `MirrorState.fullScreen` + `toggledFullScreen()` + `tapped()`/`dismissed()`
   coverage + invariant/round-trip tests (pure, TDD, local `swift test`).
2. **MIRROR-FS-UI** — `MirrorOverlayPanel` + `AVFoundationCamera.makePreviewLayer()` + the full-screen
   toggle/exit (✕ + click) + overlay show/hide bound to state + the windowed "full screen" placeholder.
   App glue → `swift build` clean + manual Mac (green light, mirrored, exit paths).
3. **MIRROR-EDGELIGHT** — `MirrorModel.edgeLightOn` (reset on `dismiss()`) + the bright-white frame in
   the windowed preview and the overlay + the ☀ toggle. App glue → `swift build` clean + manual Mac.

Each brick: TDD on the pure core; manual Mac verification for the overlay/edge-light bricks (confirm
the full-display mirror appears and exits cleanly, the green light still tracks open/closed, and the
white frame lights the face in a dim room). Domain `Skill:` lines are `none` (no Swift skill, per
CLAUDE.md §6); process skills (TDD, verification) apply.
