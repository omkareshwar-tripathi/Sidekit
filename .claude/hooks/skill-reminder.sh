#!/usr/bin/env bash
# UserPromptSubmit hook: list available skills (project + user) and remind
# Claude to check whether one applies before acting.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
USER_SKILLS_DIR="${HOME:-/nonexistent}/.claude/skills"
PROJECT_SKILLS_DIR="$PROJECT_DIR/.claude/skills"

list_skills_in() {
  local root="$1"
  [ -d "$root" ] || return 0
  while IFS= read -r f; do
    local rel name desc
    rel="${f#"$root"/}"
    name="${rel%/SKILL.md}"
    desc=$(awk '
      /^description:[[:space:]]*\|/ { in_block=1; next }
      in_block && /^[[:space:]]+/ { sub(/^[[:space:]]+/,""); print; exit }
      /^description:[[:space:]]*/ { sub(/^description:[[:space:]]*/, ""); print; exit }
    ' "$f" 2>/dev/null || true)
    # Strip surrounding double or single quotes (YAML quoted scalars)
    desc="${desc#\"}"; desc="${desc%\"}"
    desc="${desc#\'}"; desc="${desc%\'}"
    if [ ${#desc} -gt 140 ]; then
      desc="${desc:0:137}..."
    fi
    if [ -n "$desc" ]; then
      printf -- '- %s — %s\n' "$name" "$desc"
    else
      printf -- '- %s\n' "$name"
    fi
  done < <(find -L "$root" -maxdepth 4 -name 'SKILL.md' 2>/dev/null | sort)
}

project_list=$(list_skills_in "$PROJECT_SKILLS_DIR")
user_list=$(list_skills_in "$USER_SKILLS_DIR")

if [ -z "$project_list" ] && [ -z "$user_list" ]; then
  exit 0
fi

ctx="Before any operation (Write/Edit/Bash/Agent/etc.), scan the skill list below. If any folder-based skill applies to the task, read its SKILL.md before acting. These are in ADDITION to any skills already listed in the system prompt."
[ -n "$project_list" ] && ctx+=$'\n\nProject skills ('"$PROJECT_SKILLS_DIR"$'):\n'"$project_list"
[ -n "$user_list" ] && ctx+=$'\n\nUser skills ('"$USER_SKILLS_DIR"$'):\n'"$user_list"

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
else
  # Fallback: emit additionalContext as plain text (also accepted by the harness for UserPromptSubmit)
  printf '%s\n' "$ctx"
fi
