# Sidekit for Mac — Mirror: one-click front-camera self-view

**Date:** 2026-06-09
**Status:** Design resolved (via grill on the user's Mirror vision), pending spec review
**Scope:** A small live **self-view** that rides at the top of the Shelf panel — a one-tap "how do I
look?" check before a call. One of the three launch features (SpeakType dictation · Shelf ·
**Mirror**). It is **not** a camera app: live view only, no capture, no recording.

Companion to `2026-06-09-sidekit-shelf-design.md` — the Mirror lives **on the Shelf panel** and shares
its surface, lifecycle, and glass design language. Read that spec first. Capability intent:
`vision/pillars/5-shelf.md#mirror`.

---

## 1. Goal & non-goals

**Goal.** Before a meeting, tap the Mirror at the top of the Shelf, glance at yourself (fix your hair,
straighten your collar, check the lighting), and dismiss it — in one click, then gone. A quick
utility, not an app.

**Resolved product decisions (from the grill, 2026-06-09):**

| # | Decision | Resolution |
|---|---|---|
| 1 | **Camera lifecycle** | Camera is **on only while the Mirror is open**; collapsing/dismissing **releases it immediately** (green light off). macOS camera permission requested **on first open**. |
| 2 | **Default size** | Opens as a **small inline preview** at the top of the Shelf; **one click expands** to a larger panel; collapses back. Three states: button (off) → small (on) → expanded (on). |
| 3 | **Flip** | **Mirrored** (true left-right reflection, like FaceTime self-view). **No flip toggle** in v1. |
| 4 | **Camera source** | **Default built-in camera**; a **source picker appears only when multiple cameras exist** (external webcam, iPhone Continuity Camera). |
| 5 | **Summon** | **Only via the Shelf panel** — tap the Mirror strip once the panel is showing. **No dedicated Mirror hotkey/menu.** |
| 6 | **Startup state** | **Always starts collapsed** (camera off) when the panel appears; **always opens to small**; **no size memory.** |

**Non-goals (v1).**
- **No capture or recording** — ever. No photo button, no save, no frames written to disk.
- No filters, no background blur, no beauty adjustments.
- No flip toggle, no expanded-size memory, no dedicated summon.
- No Windows (later horizon).

---

## 2. Behavior & states

The Mirror occupies the **top strip of the Shelf panel** (`2026-06-09-sidekit-shelf-design.md` §2).

- **Button (collapsed, default)** — a small Mirror affordance; **camera is OFF**. This is always the
  state when the Shelf panel first appears.
- **Small (open)** — tapping the button starts the camera and shows a small live, **mirrored**
  self-view inline at the top of the panel. A green camera light is on (system-enforced).
- **Expanded** — one click enlarges the self-view to a larger panel for a proper look; click again
  (or a collapse control) returns to small.
- **Dismiss** — collapsing to the button, closing the Shelf panel, or app deactivation **stops the
  capture session and releases the camera** (green light off).

**Source picker:** when `AVCaptureDevice` discovery finds more than one video device, show a small
dropdown to choose the source; with one device, no picker is shown. Default = the system default /
built-in front camera.

---

## 3. Architecture (ports-and-adapters)

Thin feature — almost entirely an adapter, since a live camera view is inherently AppKit/AVFoundation.

### 3.1 Pure core (`SpeakTypeCore`) — tested
Minimal. A small **`MirrorState`** (`collapsed` / `small` / `expanded`) + transition rules, and the
invariant the tests pin down: **camera runs iff state ≠ collapsed**. Keeping this rule in the pure core
lets us unit-test "collapse always releases the camera" without a real device.

### 3.2 Adapters (`SpeakTypeApp`)
- **`CameraPort`** (protocol) — `start(device:)`, `stop()`, publishes a preview layer/frames;
  `availableDevices()`. The core/UI depend on this protocol; tests use a fake.
- **`AVFoundationCamera`** — real implementation over `AVCaptureSession` +
  `AVCaptureVideoPreviewLayer`. Mirroring via the preview connection
  (`isVideoMirrored = true`). Discovers devices via `AVCaptureDevice.DiscoverySession`.
- **`MirrorView`** — SwiftUI/AppKit view hosting the preview layer; lives in the Shelf panel's top
  strip; drives `start`/`stop` strictly from `MirrorState` so the lifecycle invariant holds.
- **Permission** — `AVCaptureDevice.requestAccess(for: .video)` on first open; if denied, show a small
  inline "Camera access needed" prompt with a button to open System Settings (mirrors how the app
  already surfaces the microphone/Accessibility prompts).

### 3.3 Info.plist
Add **`NSCameraUsageDescription`** ("Sidekit shows a live self-view mirror; video is never recorded or
saved."). Update `AppBundle/Info.plist`.

---

## 4. Privacy & security

- **Live view only** — frames are displayed, never captured, saved, or transmitted. On-device.
- **Camera on only while open** — the strongest privacy posture: no idle camera, green light tracks
  real use, collapse/close/deactivate all release it.
- The usage string states plainly that nothing is recorded. Consistent with Sidekit's "privacy is the
  product" principle.

---

## 5. Risks

1. **Camera lifecycle correctness** — the camera MUST stop on every exit path (collapse, panel close,
   app deactivate, display sleep). The pure-core `MirrorState` invariant + a fake `CameraPort` test
   guard this; manual verification confirms the green light goes out.
2. **Continuity Camera** — appears/disappears dynamically; the device picker must handle hot-plug
   (refresh discovery on session start). Acceptable to default to built-in if Continuity isn't ready.
3. **Preview-layer in SwiftUI** — bridging `AVCaptureVideoPreviewLayer` into the SwiftUI panel
   (NSViewRepresentable); standard but needs care for mirroring + resize between small/expanded.

---

## 6. Brick plan (outline — full plan lands in BRICKS.md)

Depends on the Shelf panel existing (`SHELF-PANEL`), since the Mirror lives on it.

1. **MIRROR-CORE** — `MirrorState` + transitions + the "camera runs iff not collapsed" invariant, unit-tested.
2. **MIRROR-CAM** — `CameraPort` + `AVFoundationCamera` (start/stop, mirrored preview, device discovery); fake for tests.
3. **MIRROR-UI** — Mirror strip on the Shelf panel: button → small → expanded; permission prompt; source picker when >1 device.
4. **MIRROR-LIFECYCLE** — wire stop() to every exit path (collapse, panel close, app deactivate); verify green light releases.
5. **MIRROR-POLISH** — animation between sizes (Reduce-Motion aware), glass styling, empty/denied states.

Each brick: TDD on the pure core + fake camera; manual Mac verification for the live-view/lifecycle
bricks (confirm the camera green light turns on only when open and off on every exit). Domain `Skill:`
lines are `none` (no Swift skill, per CLAUDE.md §6); process skills (TDD, verification) apply.
