# SpeakType for Mac

A native macOS menu-bar dictation app. **Hold the 🌐 (Fn) key, speak, release** — your words are
transcribed on-device and pasted into whatever app you're typing in. No network, no account, no
cloud: transcription runs on the Apple Neural Engine via [WhisperKit](https://github.com/argmaxinc/WhisperKit),
and the speech model is bundled into the app.

This is a deliberate **fork** of the Windows app — Windows stays C#, Mac is native Swift; they
evolve independently.

## Requirements

- **Apple Silicon** Mac (M-series)
- **macOS 14** (Sonoma) or later
- Xcode command-line tools (`xcode-select --install`) for `swift build`

## Build & run

```sh
cd SpeakTypeMac
./Scripts/build-app.sh        # builds, fetches+bundles the model, signs SpeakType.app
open SpeakType.app
```

`build-app.sh` is the one command you need. It:

1. Quits any running instance (so `open` launches the fresh build, not the stale one).
2. Compiles the SwiftPM executable.
3. Fetches the WhisperKit **base.en** model + tokenizer (~147 MB) on first run and bundles it
   into the app, so it works fully offline (`Scripts/fetch-model.sh`, idempotent).
4. Signs the app with a **stable self-signed identity** so your permission grants persist across
   rebuilds (`Scripts/make-signing-cert.sh`, created once).

The model files and the built `.app` are gitignored (large, reproducible from the scripts).

## One-time setup (permissions)

SpeakType is a menu-bar-only app (no Dock icon — look for the mic icon in the menu bar). On first
launch macOS will ask for two permissions:

1. **Microphone** — prompted automatically the first time. Click **Allow**.
2. **Accessibility** — needed to read the global 🌐 key and to send the ⌘V paste keystroke.
   The app opens System Settings and adds itself to the list; flip **SpeakType** on under
   *Privacy & Security → Accessibility*.

Because the app is signed with a stable identity, **you only grant these once** — they survive
future rebuilds.

### Make the 🌐 key free for dictation

By default macOS may steal the 🌐 (Fn) key for its own dictation or emoji picker. Set it to leave
the key alone:

> **System Settings → Keyboard → "Press 🌐 key to" → Do Nothing**

## Using it

- **Hold 🌐**, speak, then **release** — the menu shows *Recording… → Transcribing… → Pasted ✓*
  and the text lands at your cursor.
- A press shorter than ~0.3 s is ignored (so a stray tap doesn't fire).
- Recording auto-stops after 60 s.
- If Accessibility isn't granted, the text is left on the clipboard so you can paste it manually
  (the menu says *Left on clipboard*).

## Troubleshooting

**Stale Accessibility grant after rebuilds** (paste silently fails / menu stuck on *Left on
clipboard*). Clear the old entry and re-grant once:

```sh
tccutil reset Accessibility com.speaktype.mac
```

Then relaunch and toggle SpeakType on under Accessibility again.

**"No speech heard" but you did speak.** Check the mic permission is granted and the right input
device is selected in System Settings → Sound.

**Diagnostic logging.** Logging is off by default. To trace the pipeline:

```sh
defaults write com.speaktype.mac SpeakTypeDebug -bool YES   # then relaunch
tail -f ~/Library/Logs/SpeakType.log
defaults delete com.speaktype.mac SpeakTypeDebug            # turn off again
```

(Running the binary directly from a terminal? `SPEAKTYPE_DEBUG=1` works too.)

## Tests

```sh
swift test
```

The pure dictation logic (state machine, transcript cleaner, clipboard-safe paste, speech gate)
lives in `SpeakTypeCore` and is fully unit-tested with fakes — no hardware needed.

## Layout

```
SpeakTypeMac/
  Sources/
    SpeakTypeCore/      pure, tested logic (ports + DictationCoordinator + cleaner)
    SpeakTypeApp/       SwiftUI MenuBarExtra + native adapters (mic, Fn key, clipboard, WhisperKit)
    ModelSelftest/      headless dev tool: transcribe a wav through the bundled model
  Scripts/              build-app.sh, fetch-model.sh, make-signing-cert.sh
  AppBundle/Info.plist  bundle metadata (LSUIElement, mic usage string)
```

Architecture is ports-and-adapters: a pure `DictationCoordinator` orchestrates protocol "ports",
and the native macOS APIs are thin adapters behind them. See
`docs/superpowers/specs/2026-06-04-speaktype-mac-design.md` for the design.
