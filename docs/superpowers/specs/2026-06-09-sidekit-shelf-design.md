# Sidekit for Mac — Shelf: temporary file/snippet staging surface

**Date:** 2026-06-09
**Status:** Design resolved (via grill on the user's Shelf vision), pending spec review
**Scope:** A new always-on-top **Shelf** surface inside Sidekit — a transient staging tray you drop
files, folders, text selections, and images onto, then drag/copy back out into any app. One of the
three launch features (SpeakType dictation · **Shelf** · Mirror). The **Mirror** rides on this same
surface but is specified separately (next brainstorm).

Builds on `2026-06-04-speaktype-mac-ui-redesign-design.md` (the floating pill + glass design system).
The dictation pipeline, ports-and-adapters architecture, `MenuBarExtra` home, and signing/build setup
all carry over unchanged. Capability intent: `vision/pillars/5-shelf.md`.

---

## 1. Goal & non-goals

**Goal.** Give Sidekit a temporary **shelf**: a small, always-reachable holding spot. You drop a
cluster of things onto it mid-task and, minutes or a day later — in a different app — drag or copy
them back out, on your own schedule, without juggling two Finder windows. Items clear themselves over
time so the shelf never becomes clutter. Everything is on-device.

**Resolved product decisions (from the grill, 2026-06-09):**

| # | Decision | Resolution |
|---|---|---|
| 1 | **What it holds** | Files & folders, **plus** text selections and image snippets. Files are the primary citizen; text/images are first-class but secondary. |
| 2 | **Copies vs references** | **Always copies** into an app-managed store. Self-contained — survives the source moving/deleting, and handles snippets uniformly (no original file). |
| 3 | **Retention** | **~48h wall-clock timer (configurable) + manual remove / clear-all.** Dragging an item OUT does **not** delete it (reuse-safe — drop the same file in several places). |
| 4 | **Invocation** | **Auto-appears the moment a file drag starts** anywhere on the system, **and** summonable via global hotkey + menu-bar item. |
| 5 | **Surface model** | Its **own floating panel** in the shared "Sidekit family" visual language; the Mirror rides on top of it. Distinct from the dictation pill (different trigger moments). |
| 6 | **Position** | Appears **at/near the cursor** on auto-drag; returns to its **remembered position** on hotkey/menu summon. User-draggable. |
| 7 | **Organization** | **Single pile** for v1 (one shelf). Multiple named stacks = a later power feature. |
| 8 | **Persistence** | **Survives quit/reboot** in an on-device store until the timer expires. Never uploaded. |

**Non-goals (v1).**
- No multiple stacks / named shelves.
- No cross-device shelf (that waits on the universal-clipboard transport).
- No editing of staged content (it's a holding spot, not an editor).
- No agent access yet (the shelf is *designed* to become the human↔agent handoff zone later, but no
  agent API ships in v1 — see §8).
- No cloud, no accounts. Mac only (Windows parity is a later horizon).

---

## 2. The surface

A floating, dismissible **Shelf panel** — a sibling in spirit to the dictation pill, sharing the same
frosted-glass design language (`DesignSystem.swift`), always-on-top, appears on every Space, **never
steals focus** (a non-activating panel, like `PillPanel`).

**Anatomy (top → bottom):**
- **Mirror strip** (top) — collapsed by default; the Mirror feature lives here (separate spec).
- **Item area** — the single pile of staged items as a compact grid/list. Each item shows a
  **QuickLook thumbnail** (files) or a **content preview** (text snippet → first line; image → the
  image), with the filename/label beneath. Hovering an item reveals a **×** (remove) and a small
  **⋯** for per-item actions (copy, reveal in Finder).
- **Footer** — item count + total store size, a **"Save all to…"** action, and **"Clear all."**

**States:**
- **Hidden** — not on screen (the default).
- **Drop target (auto-drag)** — slides in at the cursor the instant a file drag begins; the whole
  panel is a highlighted drop zone ("Drop to shelve"). Dismisses shortly after the drag ends if
  nothing was dropped and the user didn't summon it.
- **Open (summoned)** — appears at its remembered position via hotkey/menu; stays until dismissed
  (click-away, Esc, or toggle).

**Getting items out (resolved defaults):**
- **Drag out** — primary. Drag an item (or a multi-select) from the panel into any app/folder; macOS
  performs the file promise / paste. Drag-out does **not** remove the item.
- **Per-item actions** — **Copy** (puts the file/text/image on the system clipboard) and **Reveal in
  Finder** (for file items).
- **Save all to…** — a folder picker that writes every current item into the chosen folder.

---

## 3. Architecture (ports-and-adapters)

Follows the existing split: a **pure, unit-tested `SpeakTypeCore`** model + behavior, with macOS
specifics behind ports implemented in `SpeakTypeApp`.

### 3.1 Pure core (`SpeakTypeCore`) — tested with fakes, no AppKit

- **`ShelfItem`** — value type: `id`, `kind` (`.file(path)` / `.folder(path)` / `.text` / `.image`),
  `displayName`, `byteSize`, `addedAt`, `storedRelativePath` (location inside the store). Codable.
- **`ShelfStore`** — the in-memory model + business rules over a list of `ShelfItem`:
  - `add(...)`, `remove(id)`, `clearAll()`
  - **expiry**: `pruneExpired(now:)` removes items older than the configured TTL (default 48h) and
    returns the set of stored payloads to delete. Pure function of `(items, now, ttl)`.
  - never auto-removes on drag-out (no "use" mutation).
- **`ShelfRetentionPolicy`** — `ttl: Duration` (default 48h), surfaced in Settings.
- Ports (protocols) the core calls:
  - **`ShelfPayloadStore`** — persist/read/delete the actual bytes for an item (file copy, text,
    image) under an app-managed directory; list survivors on launch.
  - **`Clock`** — already exists (`SystemClock`); reused for expiry.

### 3.2 Adapters (`SpeakTypeApp`) — macOS specifics

- **`FileSystemShelfPayloadStore`** — copies dropped files/folders into
  `~/Library/Application Support/Sidekit/Shelf/<uuid>/…`; writes text/image snippets as files;
  deletes on expiry/remove. Restores the item list on launch from an index file (Codable).
- **`DragStartMonitor`** — detects a system-wide file-drag beginning, to auto-summon the panel.
  *Technical risk — spike first (§7).* Likely an `NSEvent` global monitor for left-mouse-drag combined
  with reading the dragging pasteboard, or an `NSPasteboard(name: .drag)` poll. Fallback if
  unreliable: ship hotkey/menu summon for v1 and treat auto-on-drag as a fast-follow.
- **`ShelfPanel`** — the non-activating `NSPanel` (mirrors `PillPanel`): always-on-top, all-Spaces,
  non-focus-stealing, draggable, remembers last frame in `UserDefaults`.
- **Drag in/out** — SwiftUI `.dropDestination` / `.draggable` (or `NSItemProvider` file promises) on
  the item grid for receiving drops and serving drag-outs.
- **Hotkey** — a global shortcut to toggle the panel (reuse the app's existing shortcut plumbing).

### 3.3 Wiring
`AppController` owns the `ShelfStore` + adapters, mirrors the pattern used for dictation. On launch:
restore items → `pruneExpired(now)` → schedule a periodic prune (and prune on each app activation).

---

## 4. Retention & expiry (precise rules)

- Each item stamps `addedAt`. An item is **expired** when `now - addedAt > ttl` (default **48h**).
- Pruning runs **on launch, on app activation, and on a periodic timer** (e.g. hourly). Expiry is
  **wall-clock** — a reboot mid-window still expires items correctly on next launch.
- Pruning deletes both the model entry and its stored payload (via `ShelfPayloadStore`).
- **Manual:** per-item **×** and footer **Clear all** remove immediately (and delete payloads).
- **No clear-on-use:** dragging/copying out never removes — explicitly reuse-safe.
- TTL is **configurable** in Settings (e.g. 1 day / 2 days / 1 week / never), default 2 days.

---

## 5. Privacy & security

- Everything is **on-device**, under the app's Application Support container; **nothing is uploaded**.
- Copies are real files on disk for the retention window — the footer's **store-size readout** keeps
  this visible, and expiry/Clear-all delete them.
- Text/image snippets captured from drags are treated identically (stored locally, expire on the same
  timer).
- Consistent with Sidekit's "privacy is the product" principle.

---

## 6. Visual language

Reuse `DesignSystem.swift`: dark frosted glass, accent purple **#6D5EFC**, the same materials as the
pill and branded window, respecting **Reduce Motion** for the slide-in/out. The Shelf reads as the
same product as the dictation pill without being the same window.

---

## 7. Risks & spikes (gate before building)

1. **Auto-on-drag detection** *(highest risk)* — reliably detecting a system-wide file-drag start to
   summon the panel is the hardest macOS piece. **Spike it first.** If it can't be made reliable
   without fragile hacks, ship **hotkey/menu summon for v1** and add auto-on-drag as a fast-follow —
   the rest of the feature is unaffected.
2. **Folder copies** — copying large folders can be slow/space-heavy; copy on a background queue with
   progress, and surface store size. (References were explicitly rejected for self-containment.)
3. **Drag-out fidelity** — serving file drag-outs to arbitrary apps (file promises) needs testing
   across Finder, Mail, chat apps.
4. **Non-activating panel focus** — the panel must accept drops/clicks without stealing focus from the
   app you're working in (proven pattern in `PillPanel`).

---

## 8. Designed for agents (direction, not v1)

The shelf is the vision's intended **human↔agent handoff zone**. v1 ships human-only, but the
`ShelfStore` + `ShelfPayloadStore` are kept as a clean, inspectable model so a later local API can let
an agent drop/take items through the same store — no v1 commitment, just don't architect it shut.

---

## 9. Brick plan (outline — full plan lands in BRICKS.md)

Pure core first, then adapters, then UI, then the drag-start spike, then polish — same discipline as
the dictation app.

1. **SHELF-CORE-1** — `ShelfItem` + `ShelfStore` (add/remove/clearAll) with unit tests.
2. **SHELF-CORE-2** — expiry: `pruneExpired(now:)` + `ShelfRetentionPolicy`, fully tested.
3. **SHELF-STORE** — `FileSystemShelfPayloadStore` adapter (copy in, delete, restore on launch).
4. **SHELF-PANEL** — non-activating `ShelfPanel` + remembered position + summon (hotkey/menu).
5. **SHELF-UI** — item grid (thumbnails/previews), hover remove, footer (count/size, Save all, Clear all).
6. **SHELF-DROP** — drag files/text/images IN; multi-select drag OUT; copy / reveal-in-Finder.
7. **SHELF-DRAGSTART** *(spike → build or defer)* — auto-summon on system drag-start.
8. **SHELF-SETTINGS** — TTL configuration + store-size management in Settings.
9. **SHELF-POLISH** — animations (Reduce-Motion aware), empty state, glass styling pass.

Each brick: TDD on the pure core, manual verification on the Mac for UI/drag bricks; domain `Skill:`
lines are `none` (no Swift skill, per CLAUDE.md §6); process skills (TDD, verification) apply.
