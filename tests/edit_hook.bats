#!/usr/bin/env bats
# sensor-edit.sh — the other hook, probed the way the Stop gate was.
#
# The Stop gate was examined last cycle and three defects fell out. Stopping there
# is the one-call-site pattern this repo has recorded eight times, so the same four
# questions were asked here: does it fail open, does it discard its evidence, is it
# bounded, and what does it do with a file it cannot read.

H="${BATS_TEST_DIRNAME}/../hooks/sensor-edit.sh"

setup() {
  D="$BATS_TEST_TMPDIR"
  printf 'x = 1\n' > "$D/ok.py"
  printf 'def f(\n' > "$D/bad.py"
  printf 'y = 1\n' > "$D/locked.py"
  printf 'const a = 1\n' > "$D/ok.js"
}

ctx() {  # first line of additionalContext, or the literal (silent)
  python3 -c "
import json, sys
raw = sys.stdin.read().strip()
if not raw: print('(silent)'); raise SystemExit
print(json.loads(raw)['hookSpecificOutput']['additionalContext'].splitlines()[0])
" 2>/dev/null
}

fire() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$H" 2>/dev/null | ctx; }

@test "a valid file is silent" {
  # Positive control for all of it: a hook that speaks on every edit is a hook that
  # gets turned off, and this one fires after every Edit and Write.
  run fire "$D/ok.py"
  [ "$output" = "(silent)" ]
}

@test "a broken file is reported as broken" {
  run fire "$D/bad.py"
  [[ "$output" == *"SYNTAX BROKEN"* ]]
  [[ "$output" == *"bad.py"* ]]
}

@test "an unreadable file is NOT CHECKED, not SYNTAX BROKEN" {
  # Measured with chmod 000: reading and parsing shared one try/except, so a file
  # that could not be OPENED was reported as a syntax error — a false red telling
  # the agent to fix syntax in a file whose syntax was never examined.
  chmod 000 "$D/locked.py"
  run fire "$D/locked.py"
  chmod 644 "$D/locked.py"
  [[ "$output" == *"NOT CHECKED"* ]]
  [[ "$output" == *"Permission denied"* ]]
  [[ "$output" != *"SYNTAX BROKEN"* ]]
}

@test "javascript with no node says so instead of passing in silence" {
  # It used to `exit 0` without a word, so on a machine with no node every .js edit
  # passed silently — an absent tool turning "unchecked" into "fine", which this
  # repo's contract forbids everywhere else.
  run bash -c "printf '{\"tool_input\":{\"file_path\":\"$D/ok.js\"}}' | env PATH=/usr/bin:/bin bash '$H' 2>/dev/null"
  [ -n "$output" ]
  [[ "$output" == *"NOT CHECKED"* ]]
  [[ "$output" == *"node is not on this PATH"* ]]
}

@test "a valid javascript file with node available is still silent" {
  if ! command -v node >/dev/null; then skip "no node here to check with"; fi
  run fire "$D/ok.js"
  [ "$output" = "(silent)" ]
}
