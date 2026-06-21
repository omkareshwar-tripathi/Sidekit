# How this project is structured

A guided tour of the Sidekit repo — what every folder is, where to start reading,
and how a feature travels from idea to shipped. **If you read one file to understand
the whole project, read this one.**

> **New here?** Sidekit is an always-on-top, **fully on-device** desktop surface: summon
> it mid-task, use your voice (**SpeakType**), a temporary file **Shelf**, and a **Mirror**,
> then let it go. Nothing leaves your machine. Product site: <https://sidekit.app>.
> The [README](README.md) is the front door; this file is the map.

## Start here, by who you are

| You are… | Start with |
|---|---|
| **A user** who just wants the app | [README → Download](README.md) — the Mac DMG, no compiling needed |
| **A curious developer** reading to learn | This file, then [`vision/README.md`](vision/README.md) for the "why", then the shipped app in [`mac/`](mac/README.md) |
| **A contributor** | [CONTRIBUTING.md](CONTRIBUTING.md) — how to build, test, and the brick-by-brick workflow we use |

## The big picture

Sidekit ships today as a **native macOS app**; Windows is a **planned** future platform:

- **`mac/`** — Swift / SwiftUI, the shipped app. On-device speech via
  [WhisperKit](https://github.com/argmaxinc/WhisperKit) on the Apple Neural Engine; on-device
  drafting via a small local LLM (MLX).
- **Windows** — on the roadmap (see [`vision/ROADMAP.md`](vision/ROADMAP.md)): a native C# / .NET app
  that will mirror the Mac one. An earlier prototype was removed to be rebuilt, so there is **no
  Windows code in the repo yet.**

When it lands, the two will be deliberate **forks** — same product, native on each OS — with Mac
leading and Windows following it to parity.

## Repository map

| Path | What it is | Start file |
|---|---|---|
| `mac/` | The macOS app (Swift / SwiftUI). The shipped product. | [`mac/README.md`](mac/README.md) |
| `agents/` | Voice-driven **task agents** built on Sidekit (listen→decide→act→verify). First: `agents/audiobook/`. | `agents/audiobook/` |
| `vision/` | Where the product is going and why — north star, roadmap, per-capability intent, website brief. | [`vision/README.md`](vision/README.md) |
| `docs/` | Design specs (`superpowers/specs/`) and implementation plans (`superpowers/plans/`) for things actually being built, plus backend setup. | `docs/superpowers/specs/` |
| `.claude/` | The AI-assisted dev setup — project skills, hooks, and settings used while building. | `.claude/settings.json` |

**`agents/`** holds the new voice-agent framework work: standalone SwiftPM packages that prove
the listen→decide→act→verify loop end-to-end. The first agent is a functional audiobook player;
its action schema (play, pause, skip chapter, set speed, set sleep timer) is the harness the
voice layer targets. Architecture details and the full design are in
`docs/superpowers/specs/2026-06-22-voice-agent-audiobook-shell-design.md`.

(There's no CI workflow today — the old Windows-only `.github/workflows/ci.yml` was removed with the
Windows prototype; a macOS CI can be added when needed.)

**Root files worth knowing:**

- [`README.md`](README.md) — the front door: what Sidekit is, and how to download or build it.
- [`Sidekit-v1-spec.md`](Sidekit-v1-spec.md) — the original **Windows** v1 spec (parked; kept for the future Windows rebuild). The shipped macOS app's design lives in `docs/superpowers/specs/`.
- [`BRICKS.md`](BRICKS.md) — the session-by-session build log (see "How we build" below).
  [`BRICKS-ARCHIVE.md`](BRICKS-ARCHIVE.md) holds the older entries.
- [`TESTING.md`](TESTING.md) — the original **Windows** v1 manual test plan (parked). The shipped macOS app's tests are in [`mac/TESTING.md`](mac/TESTING.md).
- [`CLAUDE.md`](CLAUDE.md) — the working agreement for development on this repo (our engineering rules).
- `LICENSE` — MIT.

> **Not in the repo:** `lab/` (multi-gigabyte local model-evaluation scratch) and `bip-posts/`
> (build-in-public drafts) are gitignored — they live only on the maintainer's machine.

## Inside the app (the short version)

The macOS app follows **ports-and-adapters**: a pure, fully-tested core that knows nothing about the
OS, plus thin "adapter" layers that plug it into real hardware (mic, hotkey, clipboard, camera).
That is why the core is testable without the hardware actually attached.

**`mac/Sources/`**
- `SidekitCore/` — pure, unit-tested logic: the dictation state machine, transcript cleaner,
  Shelf model, Intelligence session.
- `SidekitApp/` — the SwiftUI menu-bar app and the native adapters (mic, the 🌐 / Fn key,
  clipboard, WhisperKit, camera).
- `SidekitIntelligence/` — the on-device LLM (MLX): text engine + model downloader.
- `SidekitNet/` — the sign-up / feedback client (Supabase, insert-only by design).
- `*Selftest/` — headless dev tools that exercise the speech/LLM models end-to-end.

Deeper architecture lives in the design specs under `docs/superpowers/specs/`
(e.g. `2026-06-04-speaktype-mac-design.md`).

## How we build (so the repo makes sense)

We work in **bricks** — one small, self-contained change at a time: make it, review it, test it,
verify it, then move on. A feature travels through four stages, and you can follow any feature
across them:

```
vision/             →   docs/superpowers/specs/    →   BRICKS.md        →   shipped
(where we're going)     (decision-resolved design)     (the build log)      (in mac/)
```

1. **Vision** — a capability is described in `vision/` (the "what and why").
2. **Spec** — when we commit to building it, it gets a decision-resolved design in
   `docs/superpowers/specs/` and a plan in `docs/superpowers/plans/`.
3. **Bricks** — the work is logged brick-by-brick in `BRICKS.md` as it's built and tested.
4. **Shipped** — the code lands in `mac/`, and the status tables in `vision/README.md` move to 🟢.

The full rules of this loop are in [`CLAUDE.md`](CLAUDE.md). `BRICKS.md` is the best place to see
**what's happening right now**; `vision/` is the best place to see **where it's all going**.

---

This map is kept current as the project grows — when the structure changes, this file changes with it.
