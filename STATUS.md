# STATUS — SpeakType                                   updated 2026-07-03

## What this is
Sidekit: an always-on-top, fully on-device macOS desktop surface — hold a key,
speak, clean text appears in any app (SpeakType), plus a file Shelf and a Mirror.
Shipped app lives in `mac/`; now growing reusable voice-driven task agents.

## Now
Voice Agent framework on `feat/audiobook-agent`: first agent is an audiobook
player (`agents/audiobook/`) — SwiftUI shell, PlayerStore with 11 actions, and
ActionSchema are built and unit-tested; next is the harness + decide loop.

## Next
- SCHEMA-CONSISTENCY: table test that each ActionSchema entry maps to a real PlayerStore method (drift-catcher)
- AUDIOBOOK-MANUAL-UAT: human Mac pass — build/run the audiobook app, verify all 11 controls with real audio

## Recently done
- 2026-06-23  feat(atlas): promote the light/kanban redesign to the live dashboard
- 2026-06-23  refactor(atlas): cut three unused subsystems (ponytail simplification)
- 2026-06-23  docs(bricks): archive v1 Atlas entries; repair BRICKS-ARCHIVE header

## How we work here
Claude reads this file at session start and keeps it updated at session end.
Project rules live in CLAUDE.md (if present). Bump the date above on every edit.
Recently done keeps only the 3 newest entries — drop older lines when adding;
git history of this file is the archive.
