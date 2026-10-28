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

@test "an UNKNOWN on byte-identical files blocks once, not every turn" {
  # Measured 2026-10-13 in a client repo: two browser console logs, untracked and never
  # touched again, blocked four consecutive turns with the same UNKNOWN. The first block
  # told the agent; the next three told it nothing and cost a reply each. A gate that
  # repeats itself on unchanged input gets switched off, which is the worse outcome.
  ( cd "$R" && git checkout -q a.py && printf 'console noise\n' > noise.log )
  out=$(bash "$H" 2>/dev/null | ctx)
  [[ "$out" == *"NOTHING was verified"* ]]
  out=$(bash "$H" 2>/dev/null | ctx)
  [ -z "$out" ]
  # A new byte in scope is new input: it blocks again.
  printf 'more\n' >> "$R/noise.log"
  out=$(bash "$H" 2>/dev/null | ctx)
  [[ "$out" == *"NOTHING was verified"* ]]
}

@test "a red verification keeps blocking even on identical files" {
  # The dedup is for UNKNOWN only. A failure left in place is still a failure.
  out=$(bash "$H" 2>/dev/null | ctx)
  [[ "$out" == *"verification is red"* ]]
  out=$(bash "$H" 2>/dev/null | ctx)
  [[ "$out" == *"verification is red"* ]]
}

@test "a session that changed nothing is not blocked on a tree that was already red" {
  # Measured: read-only sessions were told to fix another session's half-done work.
  in='{"session_id":"s-read","cwd":"'"$R"'"}'
  printf '%s' "$in" | bash "${BATS_TEST_DIRNAME}/../hooks/sensor-baseline.sh"
  out=$(printf '%s' "$in" | bash "$H" 2>/dev/null | ctx)
  [ -z "$out" ]
}

@test "once the session writes, the whole dirty tree is judged again" {
  in='{"session_id":"s-write","cwd":"'"$R"'"}'
  printf '%s' "$in" | bash "${BATS_TEST_DIRNAME}/../hooks/sensor-baseline.sh"
  sleep 1; printf 'y = 2\n' > "$R/b.py"
  out=$(printf '%s' "$in" | bash "$H" 2>/dev/null | ctx)
  [[ "$out" == *"verification is red"* ]]
}

edit_as() {  # record a write by session $1 of file $2 the way the PostToolUse hook does
  printf '{"session_id":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" \
    | bash "${BATS_TEST_DIRNAME}/../hooks/sensor-edit.sh" >/dev/null
}

@test "a session is judged on its own edits, not on a parallel session's red file" {
  # Measured: the gate blocked three turns in a row on another session's uncommitted
  # files in the same tree, whose hashes kept changing as that session worked.
  # a.py (red: unused import) belongs to someone else; this session writes b.py.
  in='{"session_id":"s-mine","cwd":"'"$R"'"}'
  printf '%s' "$in" | bash "${BATS_TEST_DIRNAME}/../hooks/sensor-baseline.sh"
  sleep 1; printf 'y = 2\n' > "$R/b.py"; edit_as s-mine "$R/b.py"
  out=$(printf '%s' "$in" | bash "$H" 2>/dev/null | ctx)
  [ -z "$out" ]
}

@test "the session's own red edit still blocks, and names the files it left alone" {
  in='{"session_id":"s-red","cwd":"'"$R"'"}'
  printf '%s' "$in" | bash "${BATS_TEST_DIRNAME}/../hooks/sensor-baseline.sh"
  sleep 1; printf 'import sys\ny = 2\n' > "$R/c.py"; edit_as s-red "$R/c.py"
  out=$(printf '%s' "$in" | bash "$H" 2>/dev/null | ctx)
  [[ "$out" == *"verification is red"* ]]
  [[ "$out" == *"c.py"* ]]
  [[ "$out" != *"a.py"* ]]
  [[ "$out" == *"1 other changed file(s)"* ]]
}

@test "an edit the session already committed leaves nothing for it to answer for" {
  in='{"session_id":"s-done","cwd":"'"$R"'"}'
  printf '%s' "$in" | bash "${BATS_TEST_DIRNAME}/../hooks/sensor-baseline.sh"
  sleep 1; printf 'y = 2\n' > "$R/d.py"; edit_as s-done "$R/d.py"
  ( cd "$R" && git add d.py && git commit -q -m mine )
  out=$(printf '%s' "$in" | bash "$H" 2>/dev/null | ctx)
  [ -z "$out" ]
}
