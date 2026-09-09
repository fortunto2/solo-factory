#!/usr/bin/env bats
# scripts/run-tests — the suite runner, and why its argument parser is strict.
#
# The gate was 211s and climbing; this repo's own case log says a four-minute
# pre-commit gate gets bypassed with --no-verify, and a bypassed gate is worse than
# none because you still believe it ran. Measured: 211s serial, 76s file-by-file
# concurrently, three runs agreeing (72/73/73 on the shell prototype).

R="${BATS_TEST_DIRNAME}/../scripts/run-tests"

@test "an unrecognised argument is a refusal, not a silent full run" {
  # This is the defect that built the test. The first parser treated bare words as
  # exclusions and ignored anything dash-prefixed, so the degenerate probe in
  # tests/ — which hands every script a nonsense flag — ran THE ENTIRE SUITE from
  # inside a test. A permissive parser turned a probe into a ten-minute recursion.
  #
  # Run against a scratch tree of two trivial files, never the real suite. A test
  # for a REFUSAL has to make the non-refusing behaviour cheap, or the mutant that
  # removes the guard hangs instead of failing — measured, twice, at ten minutes
  # each, and the second time it left the mutation on disk because the harness was
  # killed before it could restore.
  D="$BATS_TEST_TMPDIR/nonsense"
  mkdir -p "$D/tests" "$D/scripts"
  cp "$R" "$D/scripts/"
  { printf '@%s "a" {\n' test; printf '  [ 1 -eq 1 ]\n}\n'; } > "$D/tests/a.bats"
  { printf '@%s "b" {\n' test; printf '  [ 1 -eq 1 ]\n}\n'; } > "$D/tests/b.bats"
  run python3 "$D/scripts/run-tests" --published-nonsense-arg
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"unrecognised argument"* ]]
  [[ "$output" == *"not a pass"* ]]
  # And it must not have run anything: a count would mean it did.
  [[ "$output" != *"passed"* ]]
}


@test "--exclude removes exactly what it names, and the receipt says so" {
  # A scratch tree, never the real suite. The real suite contains THIS file, and
  # this file runs the runner — so a test that runs the real suite makes the runner
  # invoke itself. Ten minutes, twice, before that was obvious. A test must not be
  # able to invoke the thing that invokes it.
  D="$BATS_TEST_TMPDIR/excl"
  mkdir -p "$D/tests" "$D/scripts"
  cp "$R" "$D/scripts/"
  { printf '@%s "a" {\n' test; printf '  [ 1 -eq 1 ]\n}\n'; } > "$D/tests/keep.bats"
  { printf '@%s "b" {\n' test; printf '  [ 1 -eq 1 ]\n}\n'; } > "$D/tests/drop.bats"
  run python3 "$D/scripts/run-tests" --exclude drop
  [ "$status" -eq 0 ]
  [[ "$output" == *"excluded: drop"* ]]
  [[ "$output" == *"1 passed, 0 failed across 1 file(s)"* ]]
}


@test "excluding everything is UNKNOWN, never a clean run over nothing" {
  # An empty glob and a green run are otherwise the same silence.
  D="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$D/tests" "$D/scripts"
  cp "$R" "$D/scripts/"
  run python3 "$D/scripts/run-tests"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"not a pass"* ]]
}

@test "a file that collects no tests fails, because bats exits 0 on one" {
  # bats prints nothing and exits 0 for a file with no tests, which is exactly the
  # output of a file whose tests all passed.
  D="$BATS_TEST_TMPDIR/notests"
  mkdir -p "$D/tests" "$D/scripts"
  cp "$R" "$D/scripts/"
  printf '#!/usr/bin/env bats\n# no tests in here at all\n' > "$D/tests/hollow.bats"
  run python3 "$D/scripts/run-tests"
  [ "$status" -eq 1 ]
  [[ "$output" == *"collected NO tests"* ]]
  [[ "$output" == *"hollow.bats"* ]]
  [[ "$output" == *"would otherwise read as a clean run"* ]]
}

@test "a failing file is NAMED, with its own output" {
  # A count of failures with no filename is a finding nobody can act on.
  D="$BATS_TEST_TMPDIR/failing"
  mkdir -p "$D/tests" "$D/scripts"
  cp "$R" "$D/scripts/"
  { printf '@%s "this one fails" {\n' test; printf '  [ 1 -eq 2 ]\n}\n'; } > "$D/tests/bad.bats"
  { printf '@%s "this one passes" {\n' test; printf '  [ 1 -eq 1 ]\n}\n'; } > "$D/tests/good.bats"
  run python3 "$D/scripts/run-tests"
  [ "$status" -eq 1 ]
  [[ "$output" == *"=== bad.bats ==="* ]]
  [[ "$output" == *"not ok"* ]]
  [[ "$output" != *"=== good.bats ==="* ]]
}
