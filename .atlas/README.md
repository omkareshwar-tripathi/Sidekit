# Project Atlas

A small, local **re-onboarding dashboard** for this repo. Come back after weeks
away and the atlas re-orients you in about a minute: where the project is going,
what you were doing, the decisions you've locked, and the concepts worth
remembering — plus how the AI dev setup travels into the cloud.

It is a *reflection* of the repo's existing sources of truth, not a new silo:

| Layer | Reads from |
|---|---|
| Welcome-back ribbon | git (last commit) + current "doing" item |
| Vision | [`vision/README.md`](../vision/README.md) |
| Progress (kanban) | [`BRICKS.md`](../BRICKS.md) checkboxes + current branch |
| Decisions | `docs/superpowers/specs/*.md` decision tables + BRICKS notes |
| AI Operating Context | `.claude/` (committed) + `~/.claude/` (machine-local) |

## Run it

```sh
node .atlas/sync.js      # derive the latest view from the repo (idempotent)
node .atlas/server.js    # serve the dashboard
```

Then open **http://127.0.0.1:7842**.

Zero dependencies — only Node's built-in modules (Node 18+). There is no
`package.json` and nothing to install.

## How it stays current

A Stop hook re-runs `sync.js` at the end of each Claude Code session, so the
board reconciles against real git state and never drifts.

## What's committed vs. local

`.atlas/` travels with the repo. Its derived data lives in `.atlas/data/`:

- **Committed** (so the board is populated on a fresh clone): `vision.json`,
  `progress.json`, `decisions.json`, `environment.json`.
- **Volatile** (gitignored — regenerated on every sync): `git.json`.

`environment.json` is deliberately committed: it is the snapshot that carries a
*view* of your machine-local AI config (global `~/.claude/` memories, skills,
MCP) into the cloud container, which can never see `~/.claude/` itself.
