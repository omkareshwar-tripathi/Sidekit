#!/bin/bash
# SessionStart hook — inject STATUS.md so every Claude session starts oriented.
# Installed by the agent-OS adopt script (my-agent-os/atlas/adopt.js).
set -uo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
F="$PROJ/STATUS.md"

if [ -f "$F" ]; then
  echo "=== Project status (live, from STATUS.md — keep it honest, update before ending a session) ==="
  cat "$F"
  echo "=== End status ==="
else
  echo "No STATUS.md at the repo root. Create one (What this is / Now / Next / Recently done / How we work here) so sessions start oriented."
fi
