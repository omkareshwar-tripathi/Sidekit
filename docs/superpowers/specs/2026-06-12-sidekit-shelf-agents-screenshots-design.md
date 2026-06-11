# Sidekit — Shelf for Agents + Auto-Screenshots (design)

**Date:** 2026-06-12 · **Status:** approved by user (chat) · **Scope:** Mac app (`mac/`), branch `feat/mac-app`

One story: **"Screenshot it — then tell your agent to pull it from the Shelf."** Two features designed
together: the Shelf becomes readable by *any* AI agent (SHELF-AGENTS, Shelf spec §8's deferred
direction), and macOS screenshots land on the Shelf automatically (SHELF-SCREENSHOTS).

## 1. Decisions (resolved with the user)

| Question | Decision |
|---|---|
| Build order | Shelf pair first; LLM-POLISH and the lab eval follow later |
| Agent access mechanism | **Readable folder + manifest** — works with every agent that can read files (Claude Code, Antigravity, Cursor, scripts). No MCP server in v1 |
| Agent write access | **Read-only v1** (BRICKS.md note; propose-you-commit vision). Write is a future design |
| Screenshot landing | **Copy** — original stays where macOS saved it; Shelf expiry never deletes the only copy |
| Default | Auto-add screenshots **ON by default**, Settings toggle to turn off |
| Agent-facing text | **Token-budgeted** (user request): AGENTS.md ≤ ~80 tokens, clipboard prompt ≤ ~50 tokens, short manifest keys |

## 2. Agent contract (SHELF-AGENTS)

### 2.1 The folder

- **`~/.sidekit/shelf`** — short, no-spaces path agents use. It is a **symlink** to the real payload
  store `~/Library/Application Support/Sidekit/Shelf/`. No bytes are duplicated; the existing
  on-disk layout (`<uuid>/<name>` per item, `shelf.json` index) is unchanged.
- At every app launch: create `~/.sidekit/` + the symlink if missing; if the path exists as a
  symlink pointing elsewhere, repoint it; if it exists as a **real file/dir, leave it and Diag-log**
  (never delete user data). The "Copy agent instructions" prompt then falls back to the real path.

### 2.2 `manifest.json` (in the real folder, visible through the symlink)

The agent-readable index, rewritten on every shelf change. Exact shape:

```json
{
  "schema": 1,
  "updatedAt": "2026-06-12T10:30:00Z",
  "items": [
    { "id": "<uuid>", "kind": "file|folder|text|image", "name": "Screenshot….png",
      "addedAt": "2026-06-12T10:29:58Z", "expiresAt": "2026-06-14T10:29:58Z",
      "bytes": 123456, "path": "<uuid>/Screenshot….png" }
  ]
}
```

- `items` newest-first (mirrors the Shelf). `path` is relative to the folder the manifest sits in.
- `expiresAt` = `addedAt` + retention TTL at write time; `null` when retention is "Never".
- Written by a **decorator on `ShelfPersisting`**: every `save(items)` already receives the full
  item list, so it writes `shelf.json` *and* `manifest.json`. Zero `ShelfStore` changes —
  add/remove/clear/expiry all funnel through the same save. Also written **once at startup** (so it
  exists on a fresh install and heals manual deletion) and **when the retention setting changes**
  (so `expiresAt` doesn't go stale).

### 2.3 `AGENTS.md` (static, written alongside the manifest)

Exact content (token-lean by design — agents read this into context):

```markdown
# Sidekit Shelf
Files the user parked in Sidekit. Read-only: do not add, edit, or delete anything here.
List items: read `manifest.json` (newest first; each `path` is relative to this folder).
Items expire (`expiresAt`) — re-read `manifest.json` before each use.
```

### 2.4 "Copy agent instructions" (Shelf panel)

A new action in the Shelf panel footer/⋯ menu. Copies this to the clipboard (path swaps to the real
App Support path if the symlink couldn't be placed):

```
The Sidekit Shelf is at ~/.sidekit/shelf. Read manifest.json there to list items
(newest first; `path` is relative to that folder), then read the files you need. Read-only.
```

Confirmation: the existing copy-feedback pattern the Shelf already uses (no new UI surface).

## 3. Screenshots auto-land (SHELF-SCREENSHOTS)

### 3.1 Detection

- **`NSMetadataQuery`** (Spotlight) with predicate `kMDItemIsScreenCapture == 1`, scoped to the home
  folder. Catches built-in macOS screenshots **wherever** the user's save location points, in any
  system language. (Rejected alternative: watching the screenshot folder + filename matching —
  breaks on custom locations and non-English filenames.)
- **Ignore the initial gather.** The query's first result set is every screenshot already on disk —
  only `NSMetadataQueryDidUpdate` *additions* after the initial gather count.
- **Stability before add:** skip hidden dot-files (the "fleeting" file shown while the floating
  thumbnail is up); after an update fires, confirm the file still exists with a stable size (short
  delay, single re-check) before shelving.
- **Dedup:** in-memory set of recently-shelved source paths (capped) — each screenshot lands once.

### 3.2 Landing

- Copy in through the **exact same path as a drag-in**: `FileSystemShelfPayloadStore.store(.file(url))`
  → `ShelfStore.record(...)`. TTL, eviction, QuickLook thumbnails, drag-out, Clear all just work.
- Kind comes out as `.file` (the `.image` kind is for raw image-data drops) — accepted; the tile
  thumbnail renders from QuickLook either way.

### 3.3 Setting + permissions

- New setting **"Auto-add screenshots to Shelf"** — Bool, default `true`, lives with the existing
  Shelf retention setting. Toggling off stops the query; on restarts it.
- First detection in `~/Desktop` triggers macOS's one-time folder-access consent prompt. If denied,
  the watcher never sees files there — the feature silently does nothing (Diag-logged once).
- Known, accepted limits: clipboard-only screenshots create no file; third-party capture tools may
  not set the Spotlight attribute; Spotlight-disabled folders won't fire.

## 4. Architecture (house style: pure core → adapters → UI)

| Unit | Layer | Responsibility |
|---|---|---|
| `ShelfManifest` (new) | `SidekitCore` | Pure codec: `[ShelfItem]` + retention → deterministic manifest JSON; `expiresAt` math; TDD'd |
| Manifest-writing `ShelfPersisting` decorator (new) | `SidekitApp/Adapters` | Wraps `JSONShelfStore`; every `save` also writes `manifest.json` + (once) `AGENTS.md`; atomic writes |
| `AgentShelfLink` (new, small) | `SidekitApp/Adapters` | Launch-time `~/.sidekit/shelf` symlink create/repair; reports the path to advertise |
| `ScreenshotWatcher` (new) | `SidekitApp/Adapters` | `NSMetadataQuery` lifecycle, initial-gather skip, stability check, dedup; calls the same ingest path as drag-in |
| Settings + Shelf panel | `SidekitApp` | The toggle; the "Copy agent instructions" action |

Pure-testable logic (manifest codec, expiry math, dedup rule, "should shelve this path" filter)
lives in core; the adapters stay thin around OS APIs.

## 5. Error rules

- `manifest.json`/`AGENTS.md` write failure → Diag-log, never crash; manifest is **derived state**,
  fully regenerated on the next shelf change.
- Symlink site occupied by a non-symlink → leave it, Diag-log, advertise the real path instead.
- Watcher/query failure → Diag-log once; dictation/Shelf unaffected (the feature degrades to off).
- Screenshot copy failure (file vanished mid-copy) → Diag-log, skip; never retry-loop.

## 6. Testing

- **Core (swift-testing, TDD):** manifest codec (shape above, newest-first, `expiresAt` incl. "Never"
  → null, deterministic output), decorator writes-both behavior, dedup guard, path filter (dot-file
  skip, own-payload-store skip so a shelved copy never re-triggers the watcher).
- **Manual (new `TESTING.md` M10):** ⌘⇧3 → tile appears (one, correct thumbnail); toggle off → no
  add; `~/.sidekit/shelf/manifest.json` matches the panel; **acceptance:** paste the copied
  instructions into Claude Code and have it list + read a shelf item; remove an item → gone from
  the manifest.

## 7. Non-goals (this iteration)

Agent **write** access; an MCP server (possible later thin layer over the same manifest); moving or
deleting screenshot originals; clipboard-screenshot capture; Windows (Mac leads, Windows catches up
per `windows/CATCHUP.md`).
