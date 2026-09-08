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

# --- which call shapes reach this guard? ------------------------------------
# @huddora-ambassador-1857: a guard reachable under the convenient call and
# unreachable under the real one is indistinguishable from no guard. Asked of
# this checker, the answer was two holes.

@test "the script owns its selector, so no caller can narrow it" {
  # The Makefile passed a hand-written glob. It agreed with TEST_FILE on the
  # fifteen files that happen to exist here and diverged on the first .spec.ts:
  # in a scratch repo the script's selector saw three files and the glob saw one.
  run python3 -c "
import sys, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('c', '$CHECK')
spec = importlib.util.spec_from_loader('c', loader)
m = importlib.util.module_from_spec(spec); sys.modules['c'] = m; loader.exec_module(m)
for name in ['a.bats', 'widget.spec.ts', 'helper_test.ts', 'test_x.py', 'src/main.ts']:
    print(name, bool(m.TEST_FILE.search(name)))
"
  [[ "$output" == *"widget.spec.ts True"* ]]
  [[ "$output" == *"helper_test.ts True"* ]]
  [[ "$output" == *"src/main.ts False"* ]]
}

@test "a one-line test body is scanned, not skipped" {
  # The loop `continue`d after matching a test's opening line, so everything on
  # that same line was skipped — the checker was reachable for multi-line tests
  # and unreachable for single-line ones, which is the shape it exists to catch.
  printf "it('one line', () => { expect(b).not.toContain('x') })\n" > "$D/one.spec.ts"
  run python3 "$CHECK" "$D/one.spec.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"one line"* ]]
}

@test "a one-liner carrying both an assertion and a negation is left alone" {
  # Counting per LINE marked it negative-only. Counted per statement now.
  printf "it('both', () => { expect(r.status).toBe(200); expect(b).not.toContain('x') })\n" > "$D/ok.spec.ts"
  run python3 "$CHECK" "$D/ok.spec.ts"
  [ "$status" -eq 0 ]
  [[ "$output" != *"asserts only absence"* ]]
}

@test "the same holds for a bats one-liner" {
  printf '%s "both" { run a; [ "$status" -eq 0 ]; [[ "$output" != *"b"* ]]; }\n' "$AT" > "$D/b.bats"
  run python3 "$CHECK" "$D/b.bats"
  [ "$status" -eq 0 ]
}

@test "with no arguments it finds the repository's test files itself" {
  run python3 "$CHECK"
  [ "$status" -eq 0 ]
  [[ "$output" =~ checked\ ([0-9]+)\ test\ file ]]
  [ "${BASH_REMATCH[1]}" -ge 10 ]
}

@test "a brand-new, untracked test file is examined" {
  # `git ls-files` alone misses a file that is not staged yet — the one most likely
  # to carry a fresh mistake — and the script printed "checked N test file(s)" with
  # nothing saying an N+1th existed. Measured on the test file added the same hour:
  # 19 picked, 20 on disk.
  R="$BATS_TEST_TMPDIR/newfile"; mkdir -p "$R/tests"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$R" && git init -q . && git config user.email t@e && git config user.name t
    printf '@test "old" { run true; [ "$status" -eq 0 ]; }\n' > tests/old.bats
    git add -A && git commit -q -m base
    # Untracked, and deliberately vacuous: absence-only assertions.
    printf '@test "new" { run true; [[ "$output" != *"x"* ]]; }\n' > tests/new.bats )
  run bash -c "cd '$R' && python3 '$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests'"
  [ -n "$output" ]
  [[ "$output" == *"checked 2 test file(s)"* ]]
  [[ "$output" == *"new.bats"* ]]        # and it was actually judged
}

@test "an ignored file is still not examined" {
  # Positive control the other way: --exclude-standard has to keep meaning
  # something, or the fix traded a blind spot for noise from build output.
  R="$BATS_TEST_TMPDIR/ignored"; mkdir -p "$R/tests"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$R" && git init -q . && git config user.email t@e && git config user.name t
    printf '@test "old" { run true; [ "$status" -eq 0 ]; }\n' > tests/old.bats
    printf 'tests/gen.bats\n' > .gitignore
    git add -A && git commit -q -m base
    printf '@test "gen" { run true; [[ "$output" != *"x"* ]]; }\n' > tests/gen.bats )
  run bash -c "cd '$R' && python3 '$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests'"
  [[ "$output" == *"checked 1 test file(s)"* ]]
  [[ "$output" != *"gen.bats"* ]]
}
