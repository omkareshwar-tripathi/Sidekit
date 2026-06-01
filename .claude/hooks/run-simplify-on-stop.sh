#!/bin/bash
# Stop hook — advisory /simplify reminder (NON-BLOCKING) for SpeakType (C#).
#
# Fires when Claude finishes a turn. If C# files have uncommitted changes,
# displays a non-blocking notification asking whether to run the simplify skill.
# The user decides next turn — reply "run simplify" or "/simplify" to invoke it,
# anything else to skip. (SpeakType port of my-agent-os's advisory variant.)
#
# Discipline note: /simplify (quality-only cleanup) is still valuable per
# CLAUDE.md §6. This is a reminder, not a gate. To enforce, change `exit 0`
# to `exit 2` and emit the message on stderr instead.
#
# Safe before `git init`: exits 0 when the project isn't a git repo yet.

INPUT=$(cat)

# Loop guard preserved (harmless even though we don't block).
if echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    exit 0
fi

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$PROJ/.git" ] || exit 0
cd "$PROJ" || exit 0

CS_CHANGED=$(git diff --name-only HEAD -- '*.cs' 2>/dev/null)
[ -z "$CS_CHANGED" ] && exit 0

COUNT=$(printf '%s\n' "$CS_CHANGED" | wc -l | tr -d ' ')
FILES_LIST=$(printf '%s\n' "$CS_CHANGED" | head -10 | sed 's/^/  /')

MESSAGE_BODY="C# code changed this turn (${COUNT} file(s) with uncommitted changes):

${FILES_LIST}

Run simplify before continuing? Reply 'run simplify' (or '/simplify') to invoke the skill. Reply anything else to skip — this is advisory only."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg msg "$MESSAGE_BODY" '{ systemMessage: $msg }'
else
  printf '%s\n' "$MESSAGE_BODY" >&2
fi

exit 0
