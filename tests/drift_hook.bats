#!/usr/bin/env bats
# context-drift.sh — the third hook, and the last unexamined one.
#
# Both sensors were probed and both had defects. This one advises rather than
# blocks, which is exactly why nobody had read it: a hook that only warns looks
# harmless until its warning is about the wrong tree.

H="${BATS_TEST_DIRNAME}/../hooks/context-drift.sh"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  R="$BATS_TEST_TMPDIR/repo"; mkdir -p "$R/sub"
  ( cd "$R" && git init -q . && git config user.email t@e && git config user.name t
    printf 'x = 1  # AI-TODO: one\n' > a.py
    git add -A && git commit -q -m base )
}

warnings() {  # $1 = directory to run from
  ( cd "$1" && bash "$H" 2>/dev/null ) | python3 -c "
import json, sys
raw = sys.stdin.read().strip()
print(json.loads(raw)['context_drift']['warnings'] if raw else [])
"
}

@test "the same repository gives the same answer from a subdirectory" {
  # It searched `.`, and a SessionStart hook runs wherever the session started. From
  # the root it found the AI-TODO file; from a subdirectory of the SAME repository
  # it found none and reported no drift at all. The scope depended silently on
  # something the caller chose.
  run warnings "$R"
  [ -n "$output" ]
  [[ "$output" == *"AI-TODO"* ]]
  from_root="$output"
  run warnings "$R/sub"
  [ "$output" = "$from_root" ]
}

@test "a count that stopped at the cap says it is a floor" {
  # Measured: 60 files reported as a flat "50 files have unresolved AI-TODO items".
  # The same defect cap_note exists for in gpb, in a hook nobody had read since.
  ( cd "$R" && for i in $(seq 1 60); do printf 'x = 1  # AI-TODO: n\n' > "f$i.py"; done )
  run warnings "$R"
  [[ "$output" == *"at least 50"* ]]
  [[ "$output" == *"floor, not a total"* ]]
}

@test "a count below the cap is stated plainly, with no floor language" {
  # Positive control: hedging every number would pass the test above while making
  # an exact count unreadable as exact.
  run warnings "$R"
  [[ "$output" == *"1 files have unresolved"* ]]
  [[ "$output" != *"at least"* ]]
  [[ "$output" != *"floor"* ]]
}

@test "a repository with no AI-TODO and no drift is silent" {
  # This hook fires at the start of every session. One false warning and it is off.
  ( cd "$R" && rm -f a.py && printf 'x = 1\n' > a.py && git add -A && git commit -q -m clean )
  run warnings "$R"
  [ "$output" = "[]" ]
}
