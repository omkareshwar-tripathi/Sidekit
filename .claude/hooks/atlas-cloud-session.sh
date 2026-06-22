#!/bin/bash
# SessionStart hook (cloud only) — keep the atlas's environment view honest in
# the remote container. Guarded so it does nothing on your local machine.
#
# In the cloud, ~/.claude is invisible, so this triggers sync.js's
# preserve-don't-delete merge (--env-only): the committed machine-local snapshot
# is carried forward and relabelled "last seen", never dropped. Additive — runs
# alongside session-start-bricks.sh, never replacing it. Silent and never blocks.

set -uo pipefail

# No-op unless we're in the Claude Code cloud/web container.
[ -n "${CLAUDE_CODE_REMOTE:-}" ] || exit 0

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$PROJ/.atlas/sync.js" ] || exit 0
command -v node >/dev/null 2>&1 || exit 0

cd "$PROJ" || exit 0
node .atlas/sync.js --env-only >/dev/null 2>&1 || exit 0
exit 0
