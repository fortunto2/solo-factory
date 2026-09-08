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

# ── two caller-shaped mistakes that produced a verdict about somewhere else ──

@test "a --root that is not a directory is UNKNOWN, not PARTIAL with exit 0" {
  # Measured: every subprocess failed with FileNotFoundError on its cwd, which run()
  # maps to 127, which the receipt rendered as "command not found — a nested tool is
  # missing". Ruff was installed. An invented cause, and the verdict was PARTIAL
  # with EXIT 0: a typo in --root reading as a clean-enough run.
  printf 'import os\nx = 1\n' > "$D/f.py"
  run python3 "$S/solo-verify" --root "$D/no-such-dir" --files "$D/f.py"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"is not a directory"* ]]
  [[ "$output" != *"command not found"* ]]     # the cause it used to invent
  [[ "$output" != *"PARTIAL"* ]]
}

@test "a file outside --root is refused rather than misattributed" {
  # It returned VERIFY FAIL with /private/tmp/other/far.py in the findings — a
  # receipt stating one root while reporting on another tree, with an ABSOLUTE path,
  # which breaks the published promise that a receipt never prints one.
  mkdir -p "$D/inside" "$BATS_TEST_TMPDIR/elsewhere"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$D/inside" && git init -q . && git config user.email t@e && git config user.name t )
  printf 'import sys\ny = 1\n' > "$BATS_TEST_TMPDIR/elsewhere/far.py"
  run python3 "$S/solo-verify" --root "$D/inside" --files "$BATS_TEST_TMPDIR/elsewhere/far.py"
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside --root"* ]]
  [[ "$output" != *"F401"* ]]                  # it did not go on to verify it
}

@test "a file inside the root is still verified — the guard is not a wall" {
  # Positive control. Refusing everything passes both tests above while making the
  # tool useless, and --files is the shape the fixture pack tells strangers to use.
  mkdir -p "$D/ok"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$D/ok" && git init -q . && git config user.email t@e && git config user.name t )
  printf 'import os\nx = 1\n' > "$D/ok/g.py"
  run python3 "$S/solo-verify" --root "$D/ok" --files "$D/ok/g.py"
  [ "$status" -eq 1 ]                          # the unused import is found
  [[ "$output" == *"VERIFY FAIL"* ]]
  [[ "$output" == *"g.py"* ]]
  [[ "$output" != *"outside --root"* ]]
}
