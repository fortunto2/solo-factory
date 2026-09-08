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

# ── the same wrong-caller shape, asked of the siblings ──────────────────────
#
# One cycle earlier a nonexistent --root made solo-verify report an invented cause.
# Fixing it there and stopping is the one-call-site lesson; asked of the other tools,
# two had the same defect with different invented causes.

@test "list-env-sensitive-calls says the root is missing, not that it found nothing" {
  run python3 "$S/list-env-sensitive-calls" "$D/no-such-dir"
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a directory"* ]]
  [[ "$output" == *"not the same as finding nothing"* ]]
  # The cause it used to state: the walk's empty result standing in for a walk that
  # never happened.
  [[ "$output" != *"no literal argv"* ]]
}

@test "a root that is a file is refused too, not walked as empty" {
  printf 'x = 1\n' > "$D/plain.py"
  run python3 "$S/list-env-sensitive-calls" "$D/plain.py"
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a directory"* ]]
}

@test "witness blames the root the caller got wrong, not the subject" {
  run python3 "$S/witness" --root "$D/no-such-dir" --subject s.py --test t.bats --name x
  [ "$status" -eq 2 ]
  [[ "$output" == *"--root"* ]]
  [[ "$output" == *"is not a directory"* ]]
  # It used to say "s.py is not a file here" — the subject is resolved against the
  # root and fails first, so the file the caller got RIGHT took the blame.
  [[ "$output" != *"s.py is not a file here"* ]]
}

@test "a real directory is still walked — the guards are not walls" {
  # Positive control for all three: refusing every root passes them while making
  # both tools useless.
  mkdir -p "$D/real"
  printf 'import subprocess\nsubprocess.run(["git", "log"])\n' > "$D/real/c.py"
  run python3 "$S/list-env-sensitive-calls" "$D/real"
  [ "$status" -eq 1 ]                     # one undefended git call site
  [[ "$output" == *"c.py"* ]]
  [[ "$output" == *"UNDEFENDED"* ]]
}

# ── the third axis: the environment ────────────────────────────────────────
#
# Input was probed many times, invocation twice. The environment a tool runs in is
# the axis nobody varied — and it is the one a hook changes without being asked.

@test "git unreachable is named, not reported as no changed files" {
  # With an empty PATH git cannot run, git_changed_files returns nothing, and the
  # receipt said "empty scope: no changed files were found to check" while a
  # MODIFIED file sat in the tree. The scope query's failure reported as its result.
  R="$BATS_TEST_TMPDIR/nopath"; mkdir -p "$R"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$R" && git init -q . && git config user.email t@e && git config user.name t
    printf 'import os\nx = 1\n' > a.py && git add -A && git commit -q -m base
    printf 'import os\nx = 2\n' > a.py )
  run env PATH= "$(command -v python3)" "$S/solo-verify" --root "$R"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git could not run"* ]]
  [[ "$output" == *"A hook's PATH is not your shell's"* ]]
  [[ "$output" != *"no changed files were found"* ]]
}

@test "a directory that is not a repository says so" {
  R="$BATS_TEST_TMPDIR/plain"; mkdir -p "$R"
  printf 'import os\nx = 1\n' > "$R/a.py"
  run python3 "$S/solo-verify" --root "$R"
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a git repository"* ]]
  [[ "$output" == *"an empty scope is not a finding"* ]]
  [[ "$output" != *"no changed files were found"* ]]
}

@test "a real repository with a real change is still verified" {
  # Positive control: refusing both cases above by refusing everything passes them
  # while making the default invocation — no --files at all — useless.
  R="$BATS_TEST_TMPDIR/live"; mkdir -p "$R"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$R" && git init -q . && git config user.email t@e && git config user.name t
    printf 'x = 1\n' > a.py && git add -A && git commit -q -m base
    printf 'import os\nx = 1\n' > a.py )
  run python3 "$S/solo-verify" --root "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERIFY FAIL"* ]]
  [[ "$output" == *"a.py"* ]]
}

@test "an empty scope in a real repository still says exactly that" {
  # The message the two guards took over must survive where it is TRUE, or the fix
  # replaced one invented cause with another.
  R="$BATS_TEST_TMPDIR/clean"; mkdir -p "$R"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$R" && git init -q . && git config user.email t@e && git config user.name t
    printf 'x = 1\n' > a.py && git add -A && git commit -q -m base )
  run python3 "$S/solo-verify" --root "$R"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no changed files were found"* ]]
  [[ "$output" != *"git could not run"* ]]
}

# ── fourth axis: a file that is there and cannot be read ────────────────────
#
# `except OSError: pass` in the syntax sensor and `except OSError: continue` in
# limits — each silently narrowing its own scope. The only trace was a difference
# between `scope: 2 covered` and `parsed: 1`, which a reader has to notice unaided.

setup_unreadable() {
  U="$BATS_TEST_TMPDIR/perm"; mkdir -p "$U"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$U" && git init -q . && git config user.email t@e && git config user.name t
    printf 'x = 1\n' > a.py && printf 'y = 2\n' > b.py && git add -A && git commit -q -m base
    printf 'import os\nx = 1\n' > a.py && printf 'import sys\ny = 2\n' > b.py )
}

@test "a file in scope that cannot be read is named, not silently dropped" {
  setup_unreadable
  chmod 000 "$U/b.py"
  run python3 "$S/solo-verify" --root "$U"
  chmod 644 "$U/b.py"
  [ -n "$output" ]
  [[ "$output" == *"IN SCOPE, UNREADABLE"* ]]
  [[ "$output" == *"Permission denied"* ]]
  # Attributed per sensor. Deduped, removing the syntax sensor's branch killed 0
  # tests — limits reported the same file and the receipt read identically, so a
  # guard could have regressed with nothing to notice.
  [[ "$output" == *"syntax: b.py"* ]]
  [[ "$output" == *"limits: b.py"* ]]
}

@test "a readable tree says nothing about unreadability" {
  # Positive control: a line printed unconditionally passes the test above while
  # labelling every ordinary run as incomplete.
  setup_unreadable
  run python3 "$S/solo-verify" --root "$U"
  [[ "$output" == *"scope:"* ]]           # the run really happened
  [[ "$output" != *"UNREADABLE"* ]]
}

@test "the unreadable file is still not counted as parsed" {
  # The counter has to stay honest as well as the new line: naming the file while
  # also claiming it parsed would trade one false green for a louder one.
  setup_unreadable
  chmod 000 "$U/b.py"
  run python3 "$S/solo-verify" --root "$U" --json
  chmod 644 "$U/b.py"
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['unreadable'], 'nothing reported as unreadable'
syntax = [r for r in d['ran'] if r['name'] == 'syntax'][0]
assert syntax['counters']['parsed'] == 1, syntax['counters']
assert len(d['scope']) == 2, d['scope']
print('OK')
" "$output"
}

# ── the list, enumerated rather than remembered ────────────────────────────
#
# Five scripts were probed for the UNKNOWN contract and five were not, because the
# set lived in whichever ones I happened to think of. That is the same failure as
# "all three hooks are probed" (there were four) and "six scripts call git" (there
# were eight): a set recalled instead of enumerated.

# Every script claiming the contract, and the degenerate call that exercises it.
# A script here with no entry fails the completeness test below — which is the point.
declare_probes() {
  PROBES="
check-fixtures|--published-nonsense-arg
check-rules-budget|/no/such/dir
check-sensor-contract|
check-shippable|
check-vacuous-tests|/no/such/file.txt
list-env-sensitive-calls|/no/such/dir
mutate|--list /no/such/file.py
solo-verify|--root /no/such/dir
witness|--root /no/such/dir --subject x.py --test t.bats --name n
"
}

@test "every script that claims the UNKNOWN contract has a degenerate probe here" {
  # Enumerated from disk. A new check that prints UNKNOWN and is never probed would
  # otherwise join the harness with nobody having seen its unknown path fire.
  declare_probes
  cd "$BATS_TEST_DIRNAME/.."
  claiming=$(grep -l '"UNKNOWN' scripts/* 2>/dev/null | grep -v __pycache__ | sed 's|scripts/||' | sort)
  [ -n "$claiming" ]
  missing=""
  for s in $claiming; do
    printf '%s\n' "$PROBES" | grep -q "^$s|" || missing="$missing $s"
  done
  [ -z "$missing" ] || { echo "no degenerate probe for:$missing"; false; }
}

@test "each probed script answers UNKNOWN and proves it ran" {
  declare_probes
  cd "$BATS_TEST_DIRNAME/.."
  checked=0
  while IFS='|' read -r name args; do
    [ -n "$name" ] || continue
    # shellcheck disable=SC2086
    out=$(python3 "scripts/$name" $args 2>&1 || true)
    # Exit 2 alone is satisfied by an interpreter that never reached the script.
    [[ "$out" != *"can't open file"* ]] || { echo "$name: never ran"; false; }
    checked=$((checked + 1))
  done <<< "$(printf '%s\n' "$PROBES" | grep '|')"
  [ "$checked" -ge 9 ]        # a loop over an empty list asserts nothing
}
