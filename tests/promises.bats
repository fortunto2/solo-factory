#!/usr/bin/env bats
# check-promises — the promise and the check live in one artifact.
#
# rules/harness-sensors.md states what each sensor guarantees. Twenty-three promises
# in tables, six checker scripts, and nothing verified that a promise had a test at
# all. What that cost, measured this week: the pipeline pause never blocked (deleting
# the whole loop killed 0 tests), the circuit breaker's verdict was acted on by
# nothing, HARNESS GAP could be suppressed in both halves, and the exit-code summary
# named three verdicts of four. Each was a promise written in prose and pinned by
# nothing.
#
# DECLARED, NOT INFERRED. Matching promises to tests by keyword was measured and
# refused: `ty` alone matched 29 test names as a substring of "safety" and "empty".

C="${BATS_TEST_DIRNAME}/../scripts/check-promises"
HDR='| Sensor | Promise | Mechanics | Pinned by |'

fixture() {  # $1 = the pin cell for the single promise row
  F="$BATS_TEST_TMPDIR/f"
  mkdir -p "$F/rules" "$F/tests"
  { printf 'prose above\n\n%s\n' "$HDR"
    printf '|---|---|---|---|\n'
    printf '| `demo` | it promises a thing | how | %s |\n' "$1"
    printf '\nprose below\n'; } > "$F/rules/harness-sensors.md"
  { printf '@%s "a real test" {\n' test; printf '  [ 1 -eq 1 ]\n}\n'; } > "$F/tests/t.bats"
}

run_check() { SOLO_FACTORY_ROOT="$F" run python3 "$C"; }

@test "a promise pinned by a test that exists passes" {
  # The control. Without it, every assertion below could be satisfied by a checker
  # that fails on everything, which is the cheapest way to look strict.
  fixture "a real test"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 pinned by a named test"* ]]
  # No line that IS a finding. The bare substring "FAIL" appears in the bound line
  # — "whether it would FAIL if the promise broke" — so asserting on it matched the
  # commentary about findings rather than a finding. Sixth time in this session that
  # a check has matched prose instead of its subject, this time inside the test
  # written to enforce that promises carry checks.
  run bash -c "SOLO_FACTORY_ROOT='$F' python3 '$C' 2>&1 | grep -c '^FAIL' || true"
  [ "$output" = "0" ]
}

@test "a promise that names no test is a finding" {
  fixture " "
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"promises something and names no test"* ]]
  [[ "$output" == *"1 unpinned"* ]]
}

@test "a pin pointing at a test that does not exist is a finding" {
  # A pin that points at nothing reads exactly like a pin — the failure mode that
  # makes 'declared' weaker than it looks unless the name is resolved on disk.
  fixture "a test nobody ever wrote"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no @test by that name exists"* ]]
}

@test "an unpinnable promise needs a reason, like every other waiver here" {
  fixture "none"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"gives no reason"* ]]
}

@test "an unpinnable promise WITH a reason is printed every run, never silent" {
  # Same shape as EXEMPT in the receipt: the waiver is a standing statement someone
  # can disagree with, not a suppression.
  fixture "none — the tool is not installed on any seat we have"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNPINNED, DECLARED"* ]]
  [[ "$output" == *"the tool is not installed"* ]]
  [[ "$output" == *"1 declared unpinnable"* ]]
}

@test "no promises table at all is UNKNOWN, never zero unpinned" {
  # An absent table and a renamed header are the same silence otherwise, and zero
  # rows checked would read as zero promises unpinned.
  F="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$F/rules" "$F/tests"
  printf 'no table here\n' > "$F/rules/harness-sensors.md"
  { printf '@%s "a real test" {\n' test; printf '  [ 1 -eq 1 ]\n}\n'; } > "$F/tests/t.bats"
  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"not zero unpinned promises"* ]]
}

@test "no tests on disk is UNKNOWN, not every promise unpinned" {
  # Otherwise a wrong root makes all ten promises look broken for a reason that has
  # nothing to do with the promises.
  fixture "a real test"
  rm "$F/tests/t.bats"
  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"nothing to do with the promises"* ]]
}

@test "the checker states what it does NOT verify" {
  # A checker that implies more than it verifies is the defect it exists to catch.
  fixture "a real test"
  run_check
  [[ "$output" == *"checks the named test EXISTS"* ]]
  [[ "$output" == *"scripts/mutate"* ]]
}

@test "this repository's own promises are all pinned or declared" {
  cd "$BATS_TEST_DIRNAME/.."
  run python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"promise(s):"* ]]
  # A loop over an empty table asserts nothing; the real file has ten rows.
  [[ "$output" == *"10 promise(s)"* ]]
}
