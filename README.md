# Sidekit

An always-on-top, **fully on-device** desktop surface you summon mid-task and let go of. Open it and you get your dictation (**SpeakType** — hold a key, speak, clean text appears in any app), a temporary **Shelf** for files, and a **Mirror** for a pre-call glance. Nothing leaves your machine.

Sidekit is the product; SpeakType, Shelf, and Mirror are features inside it.

**Website & download:** <https://sidekit.app> · **License:** [MIT](LICENSE)

> **New here?** [`STRUCTURE.md`](STRUCTURE.md) is a guided tour of the whole repo — read that one
> file to understand how everything fits together. Want to help? See [CONTRIBUTING.md](CONTRIBUTING.md).

## Repository layout

The shipped app lives in `mac/` (Swift, macOS), plus shared planning docs in `vision/` and `docs/`.
Windows is a **planned** future platform (see [`vision/`](vision/README.md)) — not yet in the repo.
The full annotated map and a "where do I start?" guide is in **[STRUCTURE.md](STRUCTURE.md)**.

`Sidekit-v1-spec.md` is the decision-resolved spec; `BRICKS.md` is the session-by-session build log.

---

## macOS (`mac/`)

Native menu-bar app. **Hold the 🌐 (Fn) key, speak, release** — transcribed on-device and pasted into whatever app you're typing in.

**Requirements:** Apple Silicon Mac, macOS 14+, Xcode command-line tools (`xcode-select --install`).

```sh
cd mac
./Scripts/build-app.sh        # builds, fetches+bundles the model, signs Sidekit.app
open Sidekit.app
```

`build-app.sh` is the one command you need — see `mac/README.md` for permissions setup and troubleshooting.

---

## Windows — planned

Windows is on the roadmap: Sidekit comes to Windows **after** Mac (see [`vision/ROADMAP.md`](vision/ROADMAP.md)).
An earlier .NET prototype was removed to be rebuilt — **there is no Windows build in the repo yet.**
