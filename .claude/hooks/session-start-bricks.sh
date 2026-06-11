#!/bin/bash
# SessionStart hook — injects the current brick build status into Claude's context.
#
# Sidekit uses a single BRICKS.md handoff file (see CLAUDE.md §2b) instead of
# the docs/plans/STATUS.md + brick-NN-*.md split. This hook surfaces BRICKS.md at
# session start so every session begins with "what's done / what's next" visible,
# without relying on the assistant proactively reading it.
#
# Companion files:
#   BRICKS.md             — the handoff log this hook surfaces (Next up / Done)
#   BRICKS-ARCHIVE.md     — older Done entries (rarely read)
#   Sidekit-v1-spec.md    — the complete, decision-resolved spec
#   TESTING.md            — manual M# checklist + automated-test summary
#   CLAUDE.md             — the brick discipline (§2a/§2b)
#
# If BRICKS.md is absent, emits a graceful fallback so the hook never errors.
# Avoids heredocs inside command substitution (macOS ships bash 3.2).

set -uo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
BRICKS_FILE="${PROJ}/BRICKS.md"

PREFIX="=== Sidekit Build Status (live, from BRICKS.md) ===

Project follows a strict brick-by-brick loop (CLAUDE.md §2a). Read this handoff log, then read the relevant Sidekit-v1-spec.md section and the matching TESTING.md M# items before acting. Work only the current brick — the top unchecked item under 'Next up' — never work ahead. Update BRICKS.md the moment a brick is reviewed + tested + verified (§2b).

---
"

SUFFIX="
---
=== End Build Status ==="

FALLBACK="=== Sidekit Build Status ===

No BRICKS.md found yet — the brick-by-brick build hasn't started, or the file was removed.

Recovery: read CLAUDE.md and Sidekit-v1-spec.md for context, then re-establish BRICKS.md from the spec.
=== End Build Status ==="

if [[ -f "$BRICKS_FILE" ]]; then
  BODY=$(cat "$BRICKS_FILE")
  OUTPUT="${PREFIX}${BODY}${SUFFIX}"
else
  OUTPUT="$FALLBACK"
fi

# Emit JSON via jq for proper escaping; fall back to plain text if jq is absent
# (SessionStart also accepts plain stdout as additional context).
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$OUTPUT" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $ctx
    }
  }'
else
  printf '%s\n' "$OUTPUT"
fi
