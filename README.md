# SpeakType

Push-to-talk voice typing for Windows, **fully on-device**. Hold the hotkey (default **Right Ctrl**), speak, release — a local Whisper model transcribes your speech and types it straight into whatever has focus. No audio ever leaves your machine.

## Requirements

- Windows 10/11, **x64**.
- An internet connection on **first run only**, to download the speech model.

## Install (download, no build)

Every green CI run attaches the finished, self-contained `SpeakType.exe` as a downloadable artifact — no .NET SDK or build needed:

1. Open the repo's **Actions** tab → click the latest green **CI** run on `main`.
2. Under **Artifacts**, download **`SpeakType-win-x64`** (a `.zip`).
3. Unzip it, then double-click **`SpeakType.exe`** (see the SmartScreen note below on first launch).

Artifacts are kept for 90 days. To build it yourself instead, see *Build a release* below.

## Run from source

```
dotnet run --project SpeakType.App
```

## Test

```
dotnet test SpeakType.sln
```

The cross-platform `SpeakType.Core` / `SpeakType.Tests` suites also run on macOS/Linux; the `SpeakType.App` UI layer (hotkey hook, audio, tray, clipboard) is **Windows-only**.

## Build a release (single-file `.exe`)

SpeakType ships as one **self-contained, single-file `win-x64` executable**: the .NET 8 runtime and the native Whisper libraries are bundled in, so it runs on a clean machine with nothing pre-installed. There is no installer in v1.

```
dotnet publish SpeakType.App/SpeakType.App.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

The exe is written to:

```
SpeakType.App/bin/Release/net8.0-windows/win-x64/publish/SpeakType.exe
```

Copy that single file anywhere and run it.

### SmartScreen warning (expected)

The v1 executable is **unsigned**, so on first launch Windows SmartScreen shows *"Windows protected your PC."* This is expected. Click **More info → Run anyway** to start it. (Code signing is out of scope for v1.)

## First run

On first launch SpeakType opens a Welcome window and downloads the default speech model (`base.en`), then turns on **Start with Windows**. After that it lives in the system tray — right-click for Settings (hotkey, model, overlay, filler removal), Pause, and Quit.
