#!/bin/bash
# SessionStart + Stop hook — auto-heal the parked windows/ baseline.
#
# The pre-split .NET baseline (windows/SpeakType.App) kept getting deleted from
# the WORKTREE during manual Shelf drag-testing on the Mac — a Finder-side move
# during a drag gesture, never a commit (investigated 2026-06-10, see the
# BRICKS.md "windows/ phantom deletions" note). On this branch the baseline is
# read-only, so an UNSTAGED deletion of it is never intentional: restore it and
# say so. An intentional removal (a staged `git rm`) is untouched — this only
# heals worktree-vs-index deletions.
#
# Registered for SessionStart (heal before a fresh session reads the tree) and
# Stop, ahead of check-bricks-updated.sh (so the guardrail isn't tripped by
# phantom noise). Non-blocking: always exits 0.

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$PROJ/.git" ] || exit 0
cd "$PROJ" || exit 0

WIN_BASE="windows/SpeakType.App"

# Tracked at all? (If the baseline is ever properly removed/moved, do nothing.)
git ls-files --error-unmatch "$WIN_BASE" >/dev/null 2>&1 || exit 0

# Worktree-only (unstaged) deletions under the baseline — the phantom signature.
DELETED=$(git ls-files --deleted -- "$WIN_BASE" 2>/dev/null)
[ -z "$DELETED" ] && exit 0

git restore -- "$WIN_BASE" 2>/dev/null
COUNT=$(printf '%s\n' "$DELETED" | wc -l | tr -d ' ')

MESSAGE="Auto-restored ${COUNT} phantom-deleted file(s) under ${WIN_BASE} (the parked Windows baseline; deleted from the worktree but never committed — known Finder drag-test hazard, see BRICKS.md). No action needed; avoid dragging repo files during Shelf tests (use ~/SpeakType-TestFiles)."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg msg "$MESSAGE" '{ systemMessage: $msg }'
else
  printf '%s\n' "$MESSAGE" >&2
fi

exit 0
