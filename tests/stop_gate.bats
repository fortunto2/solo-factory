#!/usr/bin/env bats
# sensor-stop.sh — the gate itself, probed the way the sensors have been.
#
# Four axes found a defect each in the tools. The gate had never been probed at all,
# and it failed open in the plainest way: a verifier that produced nothing exited 0
# in silence, so a turn with an unrunnable verifier read as a turn that passed.

H="${BATS_TEST_DIRNAME}/../hooks/sensor-stop.sh"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  R="$BATS_TEST_TMPDIR/repo"; mkdir -p "$R"
  ( cd "$R" && git init -q . && git config user.email t@e && git config user.name t
    printf 'x = 1\n' > a.py && git add -A && git commit -q -m base
    printf 'import os\nx = 1\n' > a.py )
  export CLAUDE_PROJECT_DIR="$R"
}

ctx() {  # the additionalContext the hook hands back, or empty
  python3 -c "
import json, sys
raw = sys.stdin.read().strip()
if not raw: print(''); raise SystemExit
print(json.loads(raw)['hookSpecificOutput']['additionalContext'])
" 2>/dev/null
}

@test "a red verification blocks the turn" {
  out=$(bash "$H" 2>/dev/null | ctx)
  [ -n "$out" ]
  [[ "$out" == *"cannot end yet"* ]]
  [[ "$out" == *"verification is red"* ]]
}

@test "a verifier that produces nothing does not read as a pass" {
  # It used to `exit 0` in silence — the false green this harness exists to prevent,
  # in the gate itself. Its stderr was discarded too, so every named cause
  # solo-verify learned to print went to /dev/null.
  fake="$BATS_TEST_TMPDIR/plugin"
  mkdir -p "$fake/scripts" "$fake/hooks"
  cp "$H" "$fake/hooks/"
  printf '#!/bin/sh\necho "UNKNOWN: I could not run" >&2\nexit 2\n' > "$fake/scripts/solo-verify"
  chmod +x "$fake/scripts/solo-verify"
  out=$(CLAUDE_PLUGIN_ROOT="$fake" bash "$fake/hooks/sensor-stop.sh" 2>/dev/null | ctx)
  [ -n "$out" ]
  [[ "$out" == *"no receipt"* ]]
  [[ "$out" == *"UNKNOWN: I could not run"* ]]   # the stderr it used to discard
  [[ "$out" == *"Nothing was verified"* ]]
}

@test "a budget that was not enforced is stated, not implied" {
  # The first version set UNBOUNDED=1 and never read it: a comment saying "say so
  # rather than pretend the run was bounded" above code that pretended. Found by
  # asking for a 3s budget on a 4000-file tree and watching it take 114s in silence.
  if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    skip "timeout(1) exists here, so the unbounded branch is not the one taken"
  fi
  out=$(SOLO_SENSOR_BUDGET=3 bash "$H" 2>/dev/null | ctx)
  [ -n "$out" ]
  [[ "$out" == *"ran UNBOUNDED"* ]]
  [[ "$out" == *"was not enforced"* ]]
}

@test "a clean tree lets the turn end" {
  # Positive control: a gate that blocks everything passes the tests above while
  # making every turn unfinishable.
  ( cd "$R" && git add -A && git commit -q -m clean )
  out=$(bash "$H" 2>/dev/null | ctx)
  [ -z "$out" ]
}
