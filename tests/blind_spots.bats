#!/usr/bin/env bats
# measure-blind-spots — what the verifier cannot see.
#
# The false-positive rate was measured on foreign repos (#18021). This is the
# other half, and the one a user needs: a green receipt has to mean something
# narrower than "this change is correct", and the only honest way to say how much
# narrower is to plant known defects and count.

M="${BATS_TEST_DIRNAME}/../scripts/measure-blind-spots"

setup() {
  # A hook-like environment, because that is where this script usually runs and
  # where it first failed: pre-commit exports GIT_DIR and GIT_WORK_TREE at the
  # outer repository, and the scratch `git init` then dies with "core.bare and
  # core.worktree do not make sense".
  #
  # Pointed at a DECOY, never at the real .git. The first version aimed it at
  # this repository, and while the fix holds that is harmless — but if the scrub
  # ever regresses, `git init` writes `bare = true` into the real config and the
  # repository stops working. That happened once already, from the unfixed run
  # inside pre-commit, and had to be repaired by hand. A test must not be able to
  # damage the thing it is testing.
  export GIT_DIR="$BATS_TEST_TMPDIR/decoy-git-dir"
  export GIT_WORK_TREE="$BATS_TEST_TMPDIR/decoy-worktree"
}

@test "it reports both numbers and they add up" {
  run python3 "$M"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ([0-9]+)/15\ caught,\ ([0-9]+)/15\ missed ]]
  c="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[2]}"
  [ $((c + m)) -eq 15 ]
  # A run that catches nothing would mean the verifier is broken, not modest.
  [ "$c" -gt 0 ]
}

@test "every miss is named, so the blind spots are published not summarised" {
  run python3 "$M"
  [[ "$output" == *"Blind to:"* ]]
  [[ "$output" == *"off-by-one in a loop bound"* ]]
  [[ "$output" == *"wrong comparison operator"* ]]
}

@test "it refuses to credit a coincidental finding as a detection" {
  # The first draft scored 6/15 because "a test that asserts nothing" was matched
  # on the filename, and ruff had flagged an unused local in the same file. That
  # is the lenient-assertion defect this repo has a checker for, reproduced
  # inside the measurement of that very tool. It now needs the rule code.
  run python3 "$M"
  [[ "$output" == *"MISSED   a test that asserts nothing"* ]]
  [[ "$output" == *"file flagged for something else"* ]]
}

@test "a caught case names the rule that caught it" {
  run python3 "$M"
  [[ "$output" == *"caught   unused import  (F401)"* ]]
  [[ "$output" == *"caught   syntax error  (syntax)"* ]]
}

@test "the receipt's meaning is stated, not left to the reader" {
  run python3 "$M"
  [[ "$output" == *"never that the change is correct"* ]]
}
