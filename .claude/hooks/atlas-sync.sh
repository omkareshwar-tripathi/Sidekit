#!/bin/bash
# Stop hook — refresh Project Atlas at the end of each turn.
#
# Re-derives the dashboard's view from the repo (git state, BRICKS.md, vision,
# specs, .claude) by running .atlas/sync.js, so the board never drifts from
# reality. This is a pure refresh: it NEVER blocks the stop (always exits 0) and
# stays silent. Mirrors the house style of check-bricks-updated.sh
# (set -uo pipefail, .git guard, single-purpose, macOS bash-3.2-safe).
#
# Safe everywhere: no-ops if node or .atlas/sync.js is missing (fresh clone / CI).

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

# Loop guard — if already responding to a prior stop-hook block, do nothing.
case "$INPUT" in
  *'"stop_hook_active"'*'true'*) exit 0 ;;
esac

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$PROJ/.git" ] || exit 0
[ -f "$PROJ/.atlas/sync.js" ] || exit 0
command -v node >/dev/null 2>&1 || exit 0

cd "$PROJ" || exit 0

# Refresh the board; swallow output so the turn ends cleanly either way.
node .atlas/sync.js >/dev/null 2>&1 || exit 0

exit 0
