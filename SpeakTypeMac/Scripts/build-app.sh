#!/usr/bin/env bash
# Assemble Sidekit.app from the SwiftPM executable.
#
# macOS grants microphone/Accessibility permissions to a *bundle* with a stable
# signed identity, not a loose binary — so even for local dev we wrap the executable
# in a .app and ad-hoc code-sign it. Usage: ./Scripts/build-app.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")/.."   # → SpeakTypeMac/
CONFIG="${1:-debug}"

# Quit any running instance first — otherwise `open` just re-activates the old (now stale)
# process instead of launching the freshly built one.
pkill -f "Sidekit.app/Contents/MacOS/SpeakType" 2>/dev/null && echo "Quit running instance." || true

echo "Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="Sidekit.app"
CONTENTS="$APP/Contents"

# Ensure the speech model is present, then bundle it so the app runs fully offline.
"$(dirname "$0")/fetch-model.sh"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/SpeakTypeApp" "$CONTENTS/MacOS/SpeakType"
cp "AppBundle/Info.plist" "$CONTENTS/Info.plist"
cp "AppBundle/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp "AppBundle/MenuBarIcon.pdf" "$CONTENTS/Resources/MenuBarIcon.pdf"
cp -R "Models" "$CONTENTS/Resources/Models"

# Sign with a STABLE self-signed identity so macOS TCC permissions (Accessibility,
# Microphone) persist across rebuilds. Ad-hoc fallback if the identity isn't available.
"$(dirname "$0")/make-signing-cert.sh"
SIGN_ID="SpeakType Local Signing"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
  codesign --force --deep --sign "$SIGN_ID" "$APP"
  echo "Signed with stable identity: $SIGN_ID"
else
  codesign --force --sign - "$APP"
  echo "Signed ad-hoc (stable identity unavailable)."
fi

# Stamp the build identity into a sidecar JS that the manual-test sheet (test-run.html) loads,
# so its "Build" field fills itself with exactly the build you're testing. Regenerated each build.
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then DIRTY=""; else DIRTY="-dirty"; fi
BUILD_ID="$CONFIG · $SHA$DIRTY · $(date -u +'%Y-%m-%d %H:%M UTC')"
printf 'window.SPEAKTYPE_BUILD = "%s";\n' "$BUILD_ID" > build-info.js
echo "Stamped build-info.js: $BUILD_ID"

echo "Built $PWD/$APP"
echo "Run it with:  open $APP   (or: open -a \"$PWD/$APP\")"
