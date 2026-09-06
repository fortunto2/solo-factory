#!/usr/bin/env bats
# check-vacuous-tests — a test that asserts only absence passes on empty output.
#
# Three times in one week this author shipped one, twice inside the test file
# about vacuous passes. Vigilance failed twice, so it is a check. Measured on the
# nine test files in this repo before shipping: 2 findings, both true positives,
# 0 false. A checker with a high false-positive rate gets deleted within a week
# and leaves you believing a check exists when it does not.

CHECK="${BATS_TEST_DIRNAME}/../scripts/check-vacuous-tests"

setup() {
  D="$BATS_TEST_TMPDIR"
  # bats rewrites `@test "..." {` into a function definition wherever it appears in
  # this file — INCLUDING inside a heredoc. A fixture written with a literal @test
  # therefore lands on disk already transformed, and the checker then measures
  # bats's rewrite instead of the test I wrote. Two of these tests passed on that
  # for exactly one run. So the token is assembled at runtime and never appears
  # literally in this source.
  AT='@test'
}

@test "a bats test asserting only absence is flagged" {
  printf '%s "only absence" {\n  run thing\n  [[ "$output" != *"boom"* ]]\n}\n' "$AT" > "$D/x.bats"
  run python3 "$CHECK" "$D/x.bats"
  [ "$status" -eq 1 ]
  [[ "$output" == *"asserts only absence"* ]]
  [[ "$output" == *"only absence"* ]]
}

@test "one positive assertion is enough to clear it" {
  printf '%s "has both" {\n  run thing\n  [ "$status" -eq 0 ]\n  [[ "$output" != *"boom"* ]]\n}\n' "$AT" > "$D/x.bats"
  run python3 "$CHECK" "$D/x.bats"
  [ "$status" -eq 0 ]
  [[ "$output" != *"asserts only absence"* ]]
}

@test "a substring that must be present counts as positive" {
  printf '%s "positive substring" {\n  run thing\n  [[ "$output" == *"expected"* ]]\n  [[ "$output" != *"boom"* ]]\n}\n' "$AT" > "$D/x.bats"
  run python3 "$CHECK" "$D/x.bats"
  [ "$status" -eq 0 ]
}

@test "a test with no assertions at all is deliberately NOT flagged" {
  # A different defect, and a noisier check: a setup helper looks identical.
  printf '%s "asserts nothing" {\n  run thing\n}\n' "$AT" > "$D/x.bats"
  run python3 "$CHECK" "$D/x.bats"
  [ "$status" -eq 0 ]
}

@test "each test is judged alone, not by its neighbours" {
  printf '%s "good one" {\n  run thing\n  [ "$status" -eq 0 ]\n}\n%s "bad one" {\n  run thing\n  [[ "$output" != *"boom"* ]]\n}\n' "$AT" "$AT" > "$D/x.bats"
  run python3 "$CHECK" "$D/x.bats"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad one"* ]]
  [[ "$output" != *"good one"* ]]
}

@test "pytest: assert not, with nothing positive, is flagged" {
  cat > "$D/test_x.py" <<'EOF'
def test_only_absence():
    out = run()
    assert not out.startswith("boom")
EOF
  run python3 "$CHECK" "$D/test_x.py"
  [ "$status" -eq 1 ]
  [[ "$output" == *"test_only_absence"* ]]
}

@test "vitest: a lone not.toContain is flagged, and a toBe clears it" {
  cat > "$D/a.test.ts" <<'EOF'
it('only absence', async () => {
  expect(body).not.toContain('boom')
})
it('has a positive', async () => {
  expect(r.status).toBe(200)
  expect(body).not.toContain('boom')
})
EOF
  run python3 "$CHECK" "$D/a.test.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"only absence"* ]]
  [[ "$output" != *"has a positive"* ]]
}

@test "a path that is not a test file is UNKNOWN and exit 2, never a pass" {
  printf 'x = 1\n' > "$D/notatest.py"
  run python3 "$CHECK" "$D/notatest.py"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing was examined"* ]]
  [[ "$output" == *"not a pass"* ]]
}

@test "it says how many files it examined, so a silent zero is impossible" {
  printf '%s "fine" {\n  [ "$status" -eq 0 ]\n}\n' "$AT" > "$D/x.bats"
  run python3 "$CHECK" "$D/x.bats"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checked 1 test file(s), 0 finding(s)"* ]]
}

@test "a fixture that looks like a test of another dialect is data, not a test" {
  # The checker's first false positive, found on its own test file: a vitest
  # fixture inside a .bats heredoc was parsed as if it were a real test. A .bats
  # file has no vitest tests in it. Dialect follows the file extension now.
  printf '%s "wrapper" {\n  [ "$status" -eq 0 ]\n  cat > /tmp/x <<XEOF\nit("only absence", () => {\n  expect(b).not.toContain("boom")\n})\nXEOF\n}\n' "$AT" > "$D/w.bats"
  run python3 "$CHECK" "$D/w.bats"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checked 1 test file(s), 0 finding(s)"* ]]
  [[ "$output" != *"only absence"* ]]
}
