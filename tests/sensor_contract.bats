#!/usr/bin/env bats
# check-sensor-contract — every call site, not one.
#
# rules/harness-sensors.md says a skip always carries a reason and is labelled
# not-applicable or unavailable, and the label decides the verdict. Both were
# true of ruff and neither was enforced: eslint and tsc shipped with no
# skip_kind at all, so a TypeScript file with a real type error came back VERIFY
# PASS in a repo without node_modules. The rule had a test from the day it was
# written; the test exercised one sensor.

C="${BATS_TEST_DIRNAME}/../scripts/check-sensor-contract"

run_on() {  # $1 = python source
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/fake.py"
  run python3 -c "
import sys, pathlib, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('c', '$C')
spec = importlib.util.spec_from_loader('c', loader)
m = importlib.util.module_from_spec(spec); sys.modules['c'] = m; loader.exec_module(m)
for v in m.violations(pathlib.Path('$BATS_TEST_TMPDIR/fake.py').read_text()):
    print(v)
print('DONE')
"
}

@test "the real file passes, and says how many call sites it checked" {
  run python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ([0-9]+)\ skip\ call\ site ]]
  [ "${BASH_REMATCH[1]}" -gt 10 ]
  [[ "$output" == *"0 violation(s)"* ]]
}

@test "a skip with no kind is caught" {
  run_on 'Result("x", "skip", reason="nothing here")'
  [[ "$output" == *"no skip_kind"* ]]
}

@test "a skip with no reason is caught" {
  run_on 'Result("x", "skip", skip_kind=UNAVAILABLE)'
  [[ "$output" == *"no reason"* ]]
}

@test "an empty reason is caught" {
  run_on 'Result("x", "skip", reason="   ", skip_kind=UNAVAILABLE)'
  [[ "$output" == *"empty reason"* ]]
}

@test "an unknown kind is caught" {
  run_on 'Result("x", "skip", reason="r", skip_kind=SOMETHING_ELSE)'
  [[ "$output" == *"unknown skip_kind"* ]]
}

@test "a correct skip is left alone" {
  run_on 'Result("x", "skip", reason="no shell files in scope", skip_kind=NOT_APPLICABLE)'
  [[ "$output" == "DONE" ]]
}

@test "a pass or fail Result is not governed by this check" {
  run_on 'Result("x", "pass", promise="p")'
  [[ "$output" == "DONE" ]]
}

@test "the word skip inside prose is not a call site" {
  # Three times this repo has been bitten by a scanner that could not tell
  # content from instruction: bats rewriting @test in a heredoc, a vitest fixture
  # read as tests, a docstring read as a directive. This one reads the AST.
  run_on 'DOC = """Result("x", "skip") looks like a call but is prose."""'
  [[ "$output" == "DONE" ]]
}

@test "zero call sites is UNKNOWN, never a clean pass" {
  printf 'x = 1\n' > "$BATS_TEST_TMPDIR/empty.py"
  run python3 -c "
import sys, pathlib, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('c', '$C')
spec = importlib.util.spec_from_loader('c', loader)
m = importlib.util.module_from_spec(spec); sys.modules['c'] = m; loader.exec_module(m)
m.TARGET = pathlib.Path('$BATS_TEST_TMPDIR/empty.py')
sys.exit(m.main())
"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing was checked"* ]]
}

@test "the summary names the file it walked, and what it does not cover" {
  # It printed "25 skip call site(s) checked, 0 violation(s)" — a sentence that
  # reads as a statement about the repository and is a statement about one file.
  # Twelve scripts here have UNKNOWN paths; this contract governs the Result
  # dataclass only solo-verify uses. The remit was right, the sentence was not.
  run python3 "$C"
  [ -n "$output" ]
  [[ "$output" == *"in solo-verify"* ]]
  [[ "$output" == *"scope: solo-verify only"* ]]
  [[ "$output" == *"not covered here"* ]]
  # The count is still there — naming the scope must not have replaced the number.
  [[ "$output" =~ [0-9]+" skip call site" ]]
}
