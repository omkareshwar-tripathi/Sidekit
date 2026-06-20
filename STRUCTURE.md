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
| **A user** who just wants the app | [README → the Download sections](README.md) — Mac DMG or Windows build, no compiling needed |
| **A curious developer** reading to learn | This file, then [`vision/README.md`](vision/README.md) for the "why", then the platform you care about — [`mac/`](mac/README.md) or [`windows/`](windows/STATUS.md) |
| **A contributor** | [CONTRIBUTING.md](CONTRIBUTING.md) — how to build, test, and the brick-by-brick workflow we use |

## The big picture

Sidekit is **two native apps that share one design** — not one cross-platform codebase:

- **`mac/`** — Swift / SwiftUI, the **lead** platform (shipped). On-device speech via
  [WhisperKit](https://github.com/argmaxinc/WhisperKit) on the Apple Neural Engine; on-device
  drafting via a small local LLM (MLX).
- **`windows/`** — C# / .NET 8, mirrors the Mac app's behavior. On-device speech via Whisper.net.

They are deliberate **forks** that evolve independently — same product, native on each OS. The
Mac app leads; Windows follows it to parity.

## Repository map

| Path | What it is | Start file |
|---|---|---|
| `mac/` | The macOS app (Swift / SwiftUI). Lead platform, shipped. | [`mac/README.md`](mac/README.md) |
| `windows/` | The Windows app (C# / .NET 8). Mirrors the Mac app. | [`windows/STATUS.md`](windows/STATUS.md) |
| `vision/` | Where the product is going and why — north star, roadmap, per-capability intent, website brief. | [`vision/README.md`](vision/README.md) |
| `docs/` | Design specs (`superpowers/specs/`) and implementation plans (`superpowers/plans/`) for things actually being built, plus backend setup. | `docs/superpowers/specs/` |
| `.github/` | Continuous-integration workflow (GitHub Actions). | `.github/workflows/ci.yml` |
| `.claude/` | The AI-assisted dev setup — project skills, hooks, and settings used while building. | `.claude/settings.json` |

**Root files worth knowing:**

- [`README.md`](README.md) — the front door: what Sidekit is, and how to download or build it.
- [`Sidekit-v1-spec.md`](Sidekit-v1-spec.md) — the decision-resolved v1 spec (what "done" meant for launch).
- [`BRICKS.md`](BRICKS.md) — the session-by-session build log (see "How we build" below).
  [`BRICKS-ARCHIVE.md`](BRICKS-ARCHIVE.md) holds the older entries.
- [`TESTING.md`](TESTING.md) — the manual test pass run before shipping.
- [`CLAUDE.md`](CLAUDE.md) — the working agreement for development on this repo (our engineering rules).
- `LICENSE` — MIT.

> **Not in the repo:** `lab/` (multi-gigabyte local model-evaluation scratch) and `bip-posts/`
> (build-in-public drafts) are gitignored — they live only on the maintainer's machine.

## Inside each app (the short version)

Both apps follow **ports-and-adapters**: a pure, fully-tested core that knows nothing about the
OS, plus thin "adapter" layers that plug it into real hardware (mic, hotkey, clipboard, camera).
That is why the core is testable without a Mac or PC actually attached.

**`mac/Sources/`**
- `SidekitCore/` — pure, unit-tested logic: the dictation state machine, transcript cleaner,
  Shelf model, Intelligence session.
- `SidekitApp/` — the SwiftUI menu-bar app and the native adapters (mic, the 🌐 / Fn key,
  clipboard, WhisperKit, camera).
- `SidekitIntelligence/` — the on-device LLM (MLX): text engine + model downloader.
- `SidekitNet/` — the sign-up / feedback client (Supabase, insert-only by design).
- `*Selftest/` — headless dev tools that exercise the speech/LLM models end-to-end.

**`windows/`**
- `Sidekit.Core/` — the cross-platform pure logic (mirrors `SidekitCore`).
- `Sidekit.Whisper/` — local transcription (Whisper.net).
- `Sidekit.WinApp/` — the Windows-only UI: tray, global hotkey, audio, clipboard.
- `Sidekit.Tests` / `Sidekit.Whisper.Tests` — the test suites (the core ones run on macOS/Linux too).

Deeper architecture lives in the design specs under `docs/superpowers/specs/`
(e.g. `2026-06-04-speaktype-mac-design.md`).

## How we build (so the repo makes sense)

We work in **bricks** — one small, self-contained change at a time: make it, review it, test it,
verify it, then move on. A feature travels through four stages, and you can follow any feature
across them:

```
vision/             →   docs/superpowers/specs/    →   BRICKS.md        →   shipped
(where we're going)     (decision-resolved design)     (the build log)      (in mac/ or windows/)
```

1. **Vision** — a capability is described in `vision/` (the "what and why").
2. **Spec** — when we commit to building it, it gets a decision-resolved design in
   `docs/superpowers/specs/` and a plan in `docs/superpowers/plans/`.
3. **Bricks** — the work is logged brick-by-brick in `BRICKS.md` as it's built and tested.
4. **Shipped** — the code lands in `mac/` or `windows/`, and the status tables in
   `vision/README.md` move to 🟢.

The full rules of this loop are in [`CLAUDE.md`](CLAUDE.md). `BRICKS.md` is the best place to see
**what's happening right now**; `vision/` is the best place to see **where it's all going**.

---

This map is kept current as the project grows — when the structure changes, this file changes with it.
