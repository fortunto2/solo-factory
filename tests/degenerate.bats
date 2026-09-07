#!/usr/bin/env bats
# Every tool that produces a verdict must say UNKNOWN on a degenerate input.
#
# @agent-kek (#24420), on why UNCHECKED has to be its own state: "without it, any
# hole in the instrument instantly dresses up as a negative result, and then people
# argue with a phantom — not 'we could not look' but 'we looked and there is
# nothing'." This file is that property, run rather than assumed.
#
# It exists because the hand audit that produced it was itself the phantom. The
# probe interpolated a whole command line into one argument, so python could not
# open the file and exited 2 — five times, which is exactly the answer the audit
# expected. A CONFIRMING result from a run that never invoked a single tool. Only
# reading the output caught it, and reading the output is not a mechanism.

S="${BATS_TEST_DIRNAME}/../scripts"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  D="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$D"
  ( cd "$D" && git init -q . && git config user.email t@e && git config user.name t )
}

# The assertion that makes this file mean anything: the tool RAN. Without it every
# case below passes for the reason the original probe passed.
assert_unknown() {
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  # Exit 2 alone is satisfied by a python that could not open the script at all,
  # which is how the original probe got five confirming answers from zero runs.
  [[ "$output" != *"can't open file"* ]]
}

@test "solo-verify on an unresolvable file is UNKNOWN, not a pass" {
  run python3 "$S/solo-verify" --root "$D" --files nothing.py
  assert_unknown
  [[ "$output" == *"VERIFY UNKNOWN"* ]]
}

@test "check-vacuous-tests on a non-test path is UNKNOWN, not a pass" {
  run python3 "$S/check-vacuous-tests" "$D/notafile.txt"
  assert_unknown
  [[ "$output" == *"not a pass"* ]]
}

@test "list-env-sensitive-calls finding nothing is UNKNOWN, not a clean sweep" {
  run python3 "$S/list-env-sensitive-calls" "$D"
  assert_unknown
  [[ "$output" == *"walk that failed"* ]]
}

@test "mutate on a missing file is UNKNOWN, not zero survivors" {
  run python3 "$S/mutate" --list "$D/none.py"
  assert_unknown
  [[ "$output" == *"nothing was mutated"* ]]
}

@test "witness on a missing subject is UNKNOWN, not a passing cell" {
  run python3 "$S/witness" --root "$D" --subject none.py --test t.bats --name x
  assert_unknown
}

@test "the probe shape that produced a false clean sweep is itself caught" {
  # The original mistake, reproduced: one argument holding a whole command line.
  # It exits 2 and prints no UNKNOWN, so assert_unknown must reject it — otherwise
  # this whole file could pass without a single tool having run.
  run python3 "$S/solo-verify --root $D --files nothing.py"
  [ "$status" -eq 2 ]                      # the same exit code as a real UNKNOWN
  [[ "$output" != *"UNKNOWN"* ]]           # and nothing to show it ran
  [[ "$output" == *"can't open file"* ]]
}
