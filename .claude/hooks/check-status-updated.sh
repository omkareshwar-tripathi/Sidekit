#!/bin/bash
# Stop hook — STATUS.md freshness gate.
# Blocks the stop (once) when the repo changed this turn but STATUS.md's
# "updated" date is stale. Self-limiting: bumping the date keeps it quiet
# for the rest of the day; the stop_hook_active guard prevents loops.
# Installed by the agent-OS adopt script (my-agent-os/atlas/adopt.js).
set -uo pipefail

INPUT=$(cat)
echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
# -e not -d: in a git worktree .git is a file, not a directory.
[ -e "$PROJ/.git" ] || exit 0
[ -f "$PROJ/STATUS.md" ] || exit 0
cd "$PROJ" || exit 0

# The root STATUS.md itself was touched this turn → fine.
[ -n "$(git status --porcelain -- STATUS.md 2>/dev/null)" ] && exit 0

# Anything else uncommitted?
CHANGED=$(git status --porcelain 2>/dev/null || true)
[ -z "$CHANGED" ] && exit 0

# Date already bumped today → quiet. Anchored to the 'updated' label so a
# date elsewhere on the title line can't false-quiet.
TODAY=$(date +%Y-%m-%d)
head -1 STATUS.md | grep -q "updated $TODAY" && exit 0

{
  echo "The repo changed this turn but STATUS.md is stale (updated date is not today)."
  echo "If this work changed What-this-is / Now / Next / Recently done, update those sections."
  echo "If nothing status-worthy changed, just bump the 'updated' date on line 1."
} >&2
exit 2
