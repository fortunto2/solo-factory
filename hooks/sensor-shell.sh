#!/usr/bin/env bash
# sensor-shell.sh pre|post — PreToolUse/PostToolUse(Bash): attribute files a shell command wrote.
#
# sensor-edit.sh records what a session writes through Edit/Write. Writes through the shell
# (sed -i, a script, cp) went unrecorded, so the Stop gate either blamed the session for a
# neighbour's files or, after that was fixed, never saw the session's own shell writes.
# Before each command: the dirty files with mtime and size. After it: every file whose line
# changed goes on the session's touched list. A neighbour writing in the same seconds can be
# swept in; that costs a file too many, never one too few.

set -uo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[[ -z "$SID" || -z "$DIR" || ! -d "$DIR" ]] && exit 0
ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
GD=$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
KEY=${SID//[^A-Za-z0-9_-]/}
SNAP="$GD/solo-sensor-shell/$KEY"
mkdir -p "$GD/solo-sensor-shell" "$GD/solo-sensor-touched" 2>/dev/null || exit 0

dirty() {  # "path mtime size" for every changed or untracked file, sorted
  local fmt=(-f '%N %m %z')
  stat --version >/dev/null 2>&1 && fmt=(-c '%n %Y %s')
  { git -C "$ROOT" diff --name-only -z HEAD 2>/dev/null
    git -C "$ROOT" ls-files -o --exclude-standard -z 2>/dev/null; } \
    | (cd "$ROOT" && xargs -0 stat "${fmt[@]}" 2>/dev/null) | sort
}

case "${1:-}" in
  pre) dirty > "$SNAP" ;;
  post)
    [[ -f "$SNAP" ]] || exit 0
    REAL=$(cd "$ROOT" && pwd -P)
    comm -13 "$SNAP" <(dirty) | sed -E 's/ [0-9]+ [0-9]+$//' | while IFS= read -r f; do
      [[ -n "$f" ]] && printf '%s/%s\n' "$REAL" "$f"
    done >> "$GD/solo-sensor-touched/$KEY"
    rm -f "$SNAP"
    ;;
esac
exit 0
