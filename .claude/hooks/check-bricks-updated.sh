#!/bin/bash
# Stop hook — BRICKS.md / docs guardrail for SpeakType (C#).
#
# Fires when Claude finishes a turn. If C# files have uncommitted changes but
# the brick handoff log (BRICKS.md) wasn't touched in the same turn, blocks the
# stop and tells Claude exactly which doc(s) to update — based on which paths
# changed. This is the SpeakType port of my-agent-os's check-docs-updated.sh +
# check-status-updated.sh, collapsed to the single-BRICKS.md convention (CLAUDE.md §2b).
#
# Gate (primary):  BRICKS.md must be updated when *.cs changes.
# Extra nudges:    test files -> TESTING.md ; project/build files -> spec.
# Escape hatch:    commit your changes (Conventional Commits) — committed work
#                  is the changelog and silences this check.
#
# Safe before `git init`: exits 0 when the project isn't a git repo yet.

INPUT=$(cat)

# Loop guard — if already responding to a prior stop-hook block, allow stop.
if echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    exit 0
fi

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$PROJ/.git" ] || exit 0
cd "$PROJ" || exit 0

# Uncommitted C# changes this turn?
CS_CHANGED=$(git diff --name-only HEAD -- '*.cs' 2>/dev/null)
[ -z "$CS_CHANGED" ] && exit 0

# Primary gate satisfied if BRICKS.md was updated this turn.
BRICKS_CHANGED=$(git diff --name-only HEAD -- 'BRICKS.md' 2>/dev/null)
[ -n "$BRICKS_CHANGED" ] && exit 0

# ---- Map changed paths to additional target docs ----
TARGETS=()
add_target() {
    local entry="$1"
    local t
    for t in ${TARGETS[@]+"${TARGETS[@]}"}; do
        [ "$t" = "$entry" ] && return
    done
    TARGETS+=("$entry")
}

# BRICKS.md is always the primary target (the handoff log, §2b).
add_target "BRICKS.md — add/extend the Done entry for the brick (what / files / Verified M# items / notes), and trim Next up"

NEED_TESTING=0
NEED_SPEC=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
        *Tests/*|*.Tests/*|*Tests.cs|*Test.cs)
            NEED_TESTING=1 ;;
    esac
done <<< "$CS_CHANGED"

# Build/project changes also touch the spec's stack/structure.
PROJ_CHANGED=$(git diff --name-only HEAD -- '*.csproj' '*.sln' 'Directory.Build.props' 'global.json' '*.props' 2>/dev/null)
[ -n "$PROJ_CHANGED" ] && NEED_SPEC=1

[ "$NEED_TESTING" -eq 1 ] && add_target "TESTING.md — record new/changed automated tests or manual M# steps"
[ "$NEED_SPEC" -eq 1 ] && add_target "Sidekit-v1-spec.md — update the Technology Stack / project-structure section for the build/dependency change"

# ---- Block stop with a directive message ----
{
    echo "Stop blocked — BRICKS.md hasn't caught up with your code changes."
    echo ""
    echo "C# files with uncommitted changes:"
    echo "$CS_CHANGED" | head -20 | sed 's/^/  /'
    echo ""
    echo "Update the following before finishing this turn:"
    for t in ${TARGETS[@]+"${TARGETS[@]}"}; do
        echo "  → $t"
    done
    echo ""
    echo "Per CLAUDE.md §2b, the BRICKS.md Done entry records: what it does, files"
    echo "touched, how it was verified (cite TESTING.md M# items), and any notes a"
    echo "future session needs (decisions, gotchas, follow-ups)."
    echo ""
    echo "Escape hatch: commit your changes with a Conventional Commits message"
    echo "(e.g. 'feat(hotkey): add push-to-talk hook', 'test(cleanup): ...')."
    echo "Committed changes are the changelog — git log is the source of truth."
} >&2

exit 2
