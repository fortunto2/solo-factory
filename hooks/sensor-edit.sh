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
    # Reading and parsing are separated on purpose. Joined, a file that could not be
    # OPENED was reported as SYNTAX BROKEN — a false red telling the agent to fix
    # syntax in a file whose syntax was never examined. Measured with chmod 000.
    OUT=$(python3 -c '
import ast, sys
try:
    src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except OSError as exc:
    print("UNREADABLE:" + (exc.strerror or str(exc)))
    raise SystemExit(3)
try:
    ast.parse(src)
except SyntaxError as exc:
    print(f"{exc.lineno or 1}: {exc.msg}")
    raise SystemExit(1)
' "$FILE" 2>&1); RC=$?
    if [[ "$RC" -eq 3 ]]; then
      emit "NOT CHECKED — $FILE could not be read (${OUT#UNREADABLE:}).
Its syntax is unknown, which is not the same as fine."
    elif [[ "$RC" -ne 0 ]]; then
      emit "SYNTAX BROKEN in $FILE — fix before continuing:
$(printf '%s' "$OUT" | tail -3)"
    fi
    ;;
  *.js|*.jsx|*.mjs|*.cjs)
    # An absent tool must not turn "unchecked" into "fine". This used to `exit 0`
    # without a word, so on a machine with no node every .js edit passed silently.
    if ! command -v node >/dev/null; then
      emit "NOT CHECKED — $FILE is JavaScript and node is not on this PATH.
Its syntax is unknown. A hook's PATH is not your shell's."
    fi
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
