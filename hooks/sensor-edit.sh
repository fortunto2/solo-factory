#!/usr/bin/env bash
# sensor-edit.sh — PostToolUse(Edit|Write): syntax only, one file, under 100ms.
#
# Deliberately NOT a full lint or type check. During a multi-file refactor a
# strict semantic sensor on every edit floods the agent with errors from files
# it has not reached yet; the agent then reverts good work or writes local
# stubs to silence them. (@antigravity-scout-99 calls this the Intermittent
# Rupture; Fowler describes the same as a spiral of over-engineered
# refactorings.) Syntax cannot fail for that reason, so it is safe here.
#
# Everything semantic runs at the step boundary — see sensor-stop.sh.

set -uo pipefail

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0

emit() {
  jq -n --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
  exit 0
}

case "$FILE" in
  *.py)
    if ! OUT=$(python3 -c 'import ast,sys; ast.parse(open(sys.argv[1],encoding="utf-8",errors="replace").read())' "$FILE" 2>&1); then
      emit "SYNTAX BROKEN in $FILE — fix before continuing:
$(printf '%s' "$OUT" | tail -3)"
    fi
    ;;
  *.js|*.jsx|*.mjs|*.cjs)
    command -v node >/dev/null || exit 0
    if ! OUT=$(node --check "$FILE" 2>&1); then
      emit "SYNTAX BROKEN in $FILE — fix before continuing:
$(printf '%s' "$OUT" | head -3)"
    fi
    ;;
  *.json)
    if ! OUT=$(jq empty "$FILE" 2>&1); then
      emit "INVALID JSON in $FILE — fix before continuing:
$(printf '%s' "$OUT" | head -2)"
    fi
    ;;
  *.sh|*.bash)
    command -v bash >/dev/null || exit 0
    if ! OUT=$(bash -n "$FILE" 2>&1); then
      emit "SYNTAX BROKEN in $FILE — fix before continuing:
$(printf '%s' "$OUT" | head -3)"
    fi
    ;;
  *.yaml|*.yml)
    python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$FILE" 2>/dev/null || {
      # PyYAML may be absent; silence is correct here, not a false alarm.
      python3 -c 'import yaml' 2>/dev/null && \
        emit "INVALID YAML in $FILE — fix before continuing."
    }
    ;;
esac

exit 0
