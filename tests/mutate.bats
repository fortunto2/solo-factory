#!/usr/bin/env bats
# mutate — which tests never fail?
#
# Every cycle this week ended with the same ritual by hand: break one line, run
# the tests, count the reds, put it back, check the hash. It caught things no
# checker could — a marker matching a filename, a test branching on the answer it
# was meant to assert, a control running where it could not fire. This is that
# ritual as a command.
#
# Its own first real run found two untested branches in check-shippable and a 60%
# noise rate from equivalent mutants, both of which are now fixed.

M="${BATS_TEST_DIRNAME}/../scripts/mutate"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG GIT_CONFIG_GLOBAL
  D="$BATS_TEST_TMPDIR"
  cat > "$D/thing.py" <<'EOF'
import sys


def classify(n):
    if n >= 10:
        return "big"
    return "small"


def main():
    print(classify(int(sys.argv[1])))
    return 0
EOF
}

write_test() {  # $1 = body
  { echo 'T="'"$D"'/thing.py"'
    echo "$1"; } > "$D/t.bats"
}

@test "a file the tests cover thoroughly leaves no survivors" {
  write_test '
@test "big" { run python3 -c "import sys;sys.path.insert(0,\"'"$D"'\");import thing;print(thing.classify(10))"; [[ "$output" == "big" ]]; }
@test "small" { run python3 -c "import sys;sys.path.insert(0,\"'"$D"'\");import thing;print(thing.classify(9))"; [[ "$output" == "small" ]]; }
'
  run python3 "$M" "$D/thing.py" "$D/t.bats"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 survived"* ]]
}

@test "a boundary nobody asserts survives, and is named with its line" {
  write_test '
@test "big only" { run python3 -c "import sys;sys.path.insert(0,\"'"$D"'\");import thing;print(thing.classify(50))"; [[ "$output" == "big" ]]; }
'
  run python3 "$M" "$D/thing.py" "$D/t.bats"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SURVIVED"* ]]
  [[ "$output" == *"thing.py:5"* ]]
  [[ "$output" == *"Survived — these changes broke nothing"* ]]
}

@test "the file is restored, and that is checked by hash not by the write" {
  before=$(shasum -a 256 "$D/thing.py" | cut -d' ' -f1)
  write_test '
@test "x" { true; }
'
  python3 "$M" "$D/thing.py" "$D/t.bats" >/dev/null 2>&1 || true
  after=$(shasum -a 256 "$D/thing.py" | cut -d' ' -f1)
  [ "$before" = "$after" ]
}

@test "a red baseline is UNKNOWN — a mutant proves nothing against it" {
  write_test '
@test "already failing" { false; }
'
  run python3 "$M" "$D/thing.py" "$D/t.bats"
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline suite is not green"* ]]
  [[ "$output" != *"survived"* ]]
}

@test "equivalent mutants are not offered at all" {
  # __name__ guards and `return 0` cannot change observable behaviour, so a
  # survivor there says nothing about the tests. Measured: they were 3 of the
  # first 5 survivors on a real file, a 60% noise rate.
  run python3 "$M" --list "$D/thing.py"
  [[ "$output" != *"__main__"* ]]
  [[ "$output" != *"return 0"* ]]
  [[ "$output" == *"candidate mutation"* ]]
}

@test "a missing target is UNKNOWN, never a clean run" {
  run python3 "$M" "$D/nope.py" "$D/t.bats"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing was mutated"* ]]
}

@test "a mutation that does not change the file is a SKIP, never a conclusion" {
  # The tool's own rule, from the contract: "applied" is a fact about the file.
  # A patch that changed nothing must not be scored as a mutant the tests
  # survived — that would report the tests as weak when nothing was tested.
  # Pointed at itself, this branch was among the survivors: a safety property
  # with no test.
  run python3 -c "
import sys, io, contextlib, pathlib, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('mu', '$M')
spec = importlib.util.spec_from_loader('mu', loader)
m = importlib.util.module_from_spec(spec); sys.modules['mu'] = m; loader.exec_module(m)
# A file whose only candidate rewrites to itself yields no mutants at all.
print(len(m.candidates('x = 1\n')))
print(len(m.candidates('def f():\n    if a == b:\n        return 5\n')))
"
  [[ "${lines[0]}" == "0" ]]
  [ "${lines[1]}" -gt 0 ]
}

# --- the argument and safety branches the tool named on itself ---------------
# Pointed at itself the runner scored 19/42, and once its own rule TABLES were
# excluded as data the survivors clustered on two things: argument validation and
# the safety properties it advertises. Both are paths a reader would call obvious
# and neither was exercised.

@test "no arguments is UNKNOWN with usage, never a clean run" {
  run python3 "$M"
  [ "$status" -eq 2 ]
  [[ "$output" == *"mutate"* ]]
  [[ "$output" != *"survived"* ]]
}

@test "a target without a test file cannot be measured, and says so" {
  run python3 "$M" "$D/thing.py"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no test file given"* ]]
  [[ "$output" == *"nothing could be measured"* ]]
}

@test "a missing test file is UNKNOWN, not zero survivors" {
  run python3 "$M" "$D/thing.py" "$D/absent.bats"
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a file"* ]]
  [[ "$output" != *"0 survived"* ]]
}

@test "--list needs no test file and never runs one" {
  run python3 "$M" --list "$D/thing.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"candidate mutation"* ]]
  [[ "$output" != *"baseline"* ]]
}

@test "a module-level literal table is data and is not mutated" {
  # The tool spent most of its first self-run rewriting its own MUTATIONS and
  # EQUIVALENT tables — changing which mutations exist rather than what the code
  # does. Those survive everything and mean nothing.
  cat > "$D/tbl.py" <<'EOF'
RULES = [
    ("a", "x == y"),
    ("b", "n >= 2"),
]


def use(n):
    if n >= 2:
        return "big"
    return "small"
EOF
  run python3 "$M" --list "$D/tbl.py"
  [ "$status" -eq 0 ]
  # The comparison inside the function is fair game; the ones in the table are not.
  [[ "$output" == *"if n >= 2"* ]]
  [[ "$output" != *'"n >= 2"'* ]]
  [[ "$output" != *'"x == y"'* ]]
}

@test "it runs under the oldest python a caller is likely to have" {
  # UP038 would rewrite isinstance(x, (A, B)) as isinstance(x, A | B), a
  # TypeError before 3.10. It broke solo-verify exactly that way two cycles ago.
  # scripts/ is run with whatever python3 the caller has, not with the declared
  # requires-python.
  if [ ! -x /usr/bin/python3 ]; then skip "no system python3"; fi
  run /usr/bin/python3 "$M" --list "$D/thing.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"candidate mutation"* ]]
  [[ "$output" != *"Traceback"* ]]
}

# --- scoping, and the two defects it exposed --------------------------------
# A whole-file run is unusable where it matters most: solo-verify offers 261
# candidates at 33s per test run — two and a half hours, so it never gets run,
# and a tool nobody runs measures nothing.

@test "--changed scopes to the lines this working tree touched" {
  git init -q "$D/repo"; cd "$D/repo"
  git config user.email t@example.com; git config user.name t
  printf 'def a(n):\n    if n >= 1:\n        return "x"\n    return "y"\n\n\ndef b(n):\n    if n >= 2:\n        return "p"\n    return "q"\n' > m.py
  git add -A && git commit -q -m init
  whole=$(python3 "$M" --list m.py | tail -1 | grep -o '^[0-9]*')
  # Touch one line only.
  python3 - <<'EOF'
import pathlib
p = pathlib.Path('m.py'); s = p.read_text()
p.write_text(s.replace('if n >= 2:', 'if n >= 3:', 1))
EOF
  scoped=$(python3 "$M" --changed --list m.py | tail -1 | grep -o '^[0-9]*')
  [ "$scoped" -lt "$whole" ]
  [ "$scoped" -gt 0 ]
}

@test "--changed with nothing changed is UNKNOWN, not a clean sweep" {
  git init -q "$D/clean"; cd "$D/clean"
  git config user.email t@example.com; git config user.name t
  printf 'def a(n):\n    if n >= 1:\n        return "x"\n    return "y"\n' > m.py
  git add -A && git commit -q -m init
  run python3 "$M" --changed --list m.py
  [ "$status" -eq 2 ]
  [[ "$output" == *"no uncommitted changes"* ]]
  [[ "$output" == *"not the same as nothing surviving"* ]]
}

@test "an if with a trailing comment is reachable by the operators" {
  # Found by scoping to a changed line that carried a comment and getting
  # "0 of 0". An operator that cannot reach a construct reports no survivors
  # there, which reads as coverage.
  printf 'def f(n):\n    if n > 3:  # a note\n        return "big"\n    return "small"\n' > "$D/c.py"
  run python3 "$M" --list "$D/c.py"
  [[ "$output" == *"condition always true"* ]]
  [[ "$output" == *"if n > 3"* ]]
}

@test "zero applicable mutations is UNKNOWN, never 0 killed 0 survived" {
  printf 'x = 1\n' > "$D/flat.py"
  printf '@test "t" { true; }\n' > "$D/flat.bats"
  run python3 "$M" "$D/flat.py" "$D/flat.bats"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing was measured"* ]]
  [[ "$output" == *"not a clean sweep"* ]]
}

# ── one-sided conditions: a repair that looks like a repair ──────────────────
#
# Named by a peer session from its own case. A substring match on `to` inside
# `Director` was repaired with \b, and \bpassport\b then failed to match
# `passport_issue`, because an underscore is a word character. Both versions wrong
# in opposite directions, each passing the test written for the other. The class is
# not "a regex without boundaries" but a repair that looks like a repair.
#
# Its mechanical signature: both directions of one condition mutated, exactly one
# killed. Two independent survivors read as two gaps; this is a sharper thing —
# the tests pin one side of a boundary, so overshooting to the other side is free.

one_sided() {  # feed synthetic outcomes straight to the function
  python3 -c "
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader('m', '$M')
s = importlib.util.spec_from_loader('m', l)
m = importlib.util.module_from_spec(s); l.exec_module(m)
print(m.one_sided($1))
"
}

@test "one direction caught and its mirror missed is reported" {
  run one_sided "[(7,'condition always true',True,'if x:'),(7,'condition always false',False,'if x:')]"
  [ "$status" -eq 0 ]
  [[ "$output" == *"line 7"* ]]
  [[ "$output" == *"condition always true is caught"* ]]
  [[ "$output" == *"condition always false is not"* ]]
}

@test "both directions caught is not one-sided" {
  # Positive control against a section that prints whatever it is given.
  run one_sided "[(7,'condition always true',True,'if x:'),(7,'condition always false',True,'if x:')]"
  [ "$status" -eq 0 ]
  [[ "$output" == "[]" ]]
}

@test "both directions surviving is two gaps, not an asymmetry" {
  run one_sided "[(7,'condition always true',False,'if x:'),(7,'condition always false',False,'if x:')]"
  [[ "$output" == "[]" ]]
}

@test "one direction that never ran is not an asymmetry" {
  # The mirror mutation did not apply at all. Reporting that as one-sided would
  # state a cause that did not happen — a finding about coverage where the real
  # fact is that nothing was measured on the other side.
  run one_sided "[(7,'condition always true',True,'if x:')]"
  [[ "$output" == "[]" ]]
}

@test "other mutation kinds on the same line do not create an asymmetry" {
  run one_sided "[(7,'comparison flipped',True,'a == b'),(7,'early return',False,'return 1')]"
  [[ "$output" == "[]" ]]
}

@test "the section is absent when nothing is one-sided" {
  # Both directions of the one condition are asserted, so there is no asymmetry.
  write_test '
@test "big" { run python3 -c "import sys;sys.path.insert(0,\"'"$D"'\");import thing;print(thing.classify(10))"; [[ "$output" == "big" ]]; }
@test "small" { run python3 -c "import sys;sys.path.insert(0,\"'"$D"'\");import thing;print(thing.classify(9))"; [[ "$output" == "small" ]]; }
'
  run python3 "$M" "$D/thing.py" "$D/t.bats"
  [[ "$output" == *"killed"* ]]          # the run actually happened
  [[ "$output" != *"ONE-SIDED"* ]]
}

# ── an interrupted run must not leave a mutant on disk ───────────────────────
#
# Measured 2026-09-09: SIGTERM mid-run left `if True:  # mutant` in the subject and
# nothing said so. try/finally covers exceptions — including Ctrl-C, which raises
# KeyboardInterrupt — and covers neither SIGTERM nor SIGKILL. A command timeout, a
# cancelled CI job and a closed terminal all produce exactly that, and this tool is
# pointed at the file somebody is editing.

mut_fixture() {
  M="$BATS_TEST_TMPDIR/mk"; mkdir -p "$M/tests"
  cat > "$M/subj.py" <<'EOF'
import sys
def main(argv):
    if len(argv) < 2:
        return 2
    return 0
sys.exit(main(sys.argv))
EOF
  # Slow on purpose: the run has to still be inside the mutation loop when the
  # signal lands, or the test measures a finished run and passes for free.
  printf 'setup() { sleep 4; }\n' > "$M/tests/t.bats"
  { printf '@%s "slow" {\n' test
    printf '  run python3 "%s/subj.py"\n' "$M"
    printf '  [ "$status" -eq 2 ]\n}\n'; } >> "$M/tests/t.bats"
}

@test "SIGTERM mid-run restores the subject" {
  mut_fixture
  before=$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)
  ( cd "$M" && python3 "$BATS_TEST_DIRNAME/../scripts/mutate" --file subj.py \
      --test tests/t.bats >/dev/null 2>&1 ) &
  bg=$!
  sleep 5
  pkill -TERM -f "scripts/mutate --file subj.py" || true
  wait $bg 2>/dev/null || true
  sleep 1
  after=$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)
  [ "$before" = "$after" ]
  [ ! -f "$M/subj.py.mutate-original" ]
}

@test "a crumb from a killed run makes the next one refuse, not measure" {
  # SIGKILL cannot be caught, so the crumb is the entire defence. A run that starts
  # on a mutated file would measure a baseline of somebody else's injected defect,
  # and every verdict after that is about the wrong program.
  mut_fixture
  cp "$M/subj.py" "$M/subj.py.mutate-original"
  run bash -c "cd '$M' && python3 '$BATS_TEST_DIRNAME/../scripts/mutate' --file subj.py --test tests/t.bats 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"killed before it could restore"* ]]
  [[ "$output" == *"Nothing was measured"* ]]
  # And it says how to undo it, naming both files.
  [[ "$output" == *"mv subj.py.mutate-original subj.py"* ]]
}

@test "the crumb holds the original, so the undo it prints actually works" {
  # A recovery instruction nobody has run is a guess. This runs it.
  mut_fixture
  before=$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)
  cp "$M/subj.py" "$M/subj.py.mutate-original"
  printf 'import sys\nif True:  # mutant\n    pass\n' > "$M/subj.py"
  [ "$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)" != "$before" ]
  mv "$M/subj.py.mutate-original" "$M/subj.py"
  [ "$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)" = "$before" ]
}

@test "a clean run leaves no crumb behind" {
  # The control. A crumb left after every run would make the refusal above fire on
  # every second invocation — a guard that blocks honest work gets deleted.
  mut_fixture
  printf 'setup() { :; }\n' > "$M/tests/t.bats"
  { printf '@%s "quick" {\n' test
    printf '  run python3 "%s/subj.py"\n' "$M"
    printf '  [ "$status" -eq 2 ]\n}\n'; } >> "$M/tests/t.bats"
  run bash -c "cd '$M' && python3 '$BATS_TEST_DIRNAME/../scripts/mutate' --file subj.py --test tests/t.bats 2>&1"
  [ ! -f "$M/subj.py.mutate-original" ]
}

@test "mutate itself writes the crumb, and it holds the original" {
  # The mutation "no crumb is written" killed 0 tests: every case above created the
  # crumb by hand, so nothing checked that the tool writes one. The entire SIGKILL
  # defence rests on that write, and it was the one step untested.
  mut_fixture
  before=$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)
  ( cd "$M" && python3 "$BATS_TEST_DIRNAME/../scripts/mutate" --file subj.py \
      --test tests/t.bats >/dev/null 2>&1 ) &
  bg=$!
  sleep 5
  # While the run is still inside the mutation loop.
  [ -f "$M/subj.py.mutate-original" ]
  [ "$(shasum -a256 "$M/subj.py.mutate-original" | cut -d' ' -f1)" = "$before" ]
  # And the subject really is mutated at this moment, or the crumb is guarding
  # nothing and this test would pass on a tool that never mutates at all.
  [ "$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)" != "$before" ]
  pkill -TERM -f "scripts/mutate --file subj.py" || true
  wait $bg 2>/dev/null || true
}

@test "a failed restore keeps the crumb, which is the only record left" {
  # The other survivor. If the restore fails, removing the crumb would erase the
  # single copy of the original — turning a recoverable accident into a loss.
  # Forced by having the test that mutate runs make the subject unwritable.
  M="$BATS_TEST_TMPDIR/fail"; mkdir -p "$M/tests"
  cat > "$M/subj.py" <<'EOF'
import sys
def main(argv):
    if len(argv) < 2:
        return 2
    return 0
sys.exit(main(sys.argv))
EOF
  before=$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)
  { printf '@%s "locks the subject" {\n' test
    printf '  chmod 000 "%s/subj.py"\n' "$M"
    printf '  [ 1 -eq 1 ]\n}\n'; } > "$M/tests/t.bats"
  run bash -c "cd '$M' && python3 '$BATS_TEST_DIRNAME/../scripts/mutate' --file subj.py --test tests/t.bats 2>&1"
  chmod 644 "$M/subj.py" 2>/dev/null || true
  # Whatever the verdict, the original must still be recoverable.
  [ -f "$M/subj.py.mutate-original" ]
  [ "$(shasum -a256 "$M/subj.py.mutate-original" | cut -d' ' -f1)" = "$before" ]
}
