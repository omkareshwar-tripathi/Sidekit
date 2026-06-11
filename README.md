# Sidekit

An always-on-top, **fully on-device** desktop surface you summon mid-task and let go of. Open it and you get your dictation (**SpeakType** — hold a key, speak, clean text appears in any app), a temporary **Shelf** for files, and a **Mirror** for a pre-call glance. Nothing leaves your machine.

Sidekit is the product; SpeakType, Shelf, and Mirror are features inside it.

## Repository layout

This repo holds the two native apps (one per OS) plus shared planning docs:

| Path | What |
|---|---|
| `mac/` | The macOS app — native Swift / SwiftUI, on-device Whisper via WhisperKit (Apple Neural Engine). **The lead platform** (shipped). |
| `windows/` | The Windows app — C# / .NET 8, on-device Whisper via Whisper.net. Mirrors the Mac app. |
| `vision/` | Product vision, roadmap, and website brief. |
| `docs/` | Design specs and plans. |
| `lab/`, `scripts/` | Offline model experiments and export tooling (not shipped). |

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

## Windows (`windows/`)

Push-to-talk voice typing. Hold the hotkey (default **Right Ctrl**), speak, release — a local Whisper model transcribes and types into whatever has focus.

**Requirements:** Windows 10/11 x64; an internet connection on **first run only**, to download the speech model.

### Install (download, no build)

Every green CI run attaches a finished, self-contained `Sidekit.exe` as a downloadable artifact — no .NET SDK or build needed:

1. Open the repo's **Actions** tab → click the latest green **CI** run on `main`.
2. Under **Artifacts**, download **`Sidekit-win-x64`** (a `.zip`).
3. Unzip it, then double-click **`Sidekit.exe`** (see the SmartScreen note below on first launch).

Artifacts are kept for 90 days.

### Run / test / build from source

```sh
dotnet run    --project windows/Sidekit.App
dotnet test   windows/Sidekit.sln
dotnet publish windows/Sidekit.App/Sidekit.App.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

The cross-platform `Sidekit.Core` / `Sidekit.Tests` suites also run on macOS/Linux; the `Sidekit.App` UI layer (hotkey hook, audio, tray, clipboard) is **Windows-only**. The published single-file exe lands at `windows/Sidekit.App/bin/Release/net8.0-windows/win-x64/publish/Sidekit.exe`.

### SmartScreen warning (expected)

The v1 executable is **unsigned**, so on first launch Windows SmartScreen shows *"Windows protected your PC."* This is expected — click **More info → Run anyway**. (Code signing is out of scope for v1.)

### First run

On first launch Sidekit opens a Welcome window and downloads the default speech model (`base.en`), then turns on **Start with Windows**. After that it lives in the system tray — right-click for Settings (hotkey, model, overlay, filler removal), Pause, and Quit.
