#!/usr/bin/env bash
# Generate two short license-free audio files as stand-in audiobook content.
# Uses macOS `say` (built-in TTS) so the demo plays real spoken audio, no downloads.
# Resources MUST live inside the AudiobookApp target dir for SwiftPM to bundle them.
set -euo pipefail
DEST="$(dirname "$0")/../Sources/AudiobookApp/Resources"
mkdir -p "$DEST"
if say -v Daniel -o "$DEST/book-a.caf" "Meditations, by Marcus Aurelius. Book one. Book two. Book three." 2>/dev/null; then
    say -v Daniel -o "$DEST/book-b.caf" "The Art of War, by Sun Tzu. Laying plans. Waging war. The sheathed sword."
else
    # Daniel voice not installed — fall back to the default system voice
    say -o "$DEST/book-a.caf" "Meditations, by Marcus Aurelius. Book one. Book two. Book three."
    say -o "$DEST/book-b.caf" "The Art of War, by Sun Tzu. Laying plans. Waging war. The sheathed sword."
fi
echo "Wrote book-a.caf and book-b.caf to $DEST"
