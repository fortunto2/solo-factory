#!/usr/bin/env bash
# sensor-baseline.sh — SessionStart: remember what the working tree looked like before
# this session touched anything, so the Stop gate judges the session's own changes.
#
# Without it, a session that only read files was blocked on a tree that was already
# dirty when it started (another session's half-finished work, a pre-existing red
# test): the gate asked it to fix what it never touched. sensor-stop.sh compares the
# same fingerprint and stays silent while it is unchanged.
#
# The fingerprint is the dirty paths with their mtime and size, not their bytes:
# one `stat` call however large the tree, and any write moves an mtime.

set -uo pipefail

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
ROOT="${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}"
[[ -n "$SID" ]] || exit 0
GITDIR=$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null) || exit 0

. "$(dirname "${BASH_SOURCE[0]}")/tree-print.sh"
mkdir -p "$GITDIR/solo-sensor-baseline" 2>/dev/null || exit 0
# Sessions are few per repo, but they never end cleanly: drop prints older than 7 days.
find "$GITDIR/solo-sensor-baseline" -type f -mtime +7 -delete 2>/dev/null
find "$GITDIR/solo-sensor-touched" -type f -mtime +7 -delete 2>/dev/null
tree_print "$ROOT" > "$GITDIR/solo-sensor-baseline/${SID//[^A-Za-z0-9_-]/}" 2>/dev/null
exit 0
