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

@test "a suite that cannot see the file at all is UNKNOWN, not a sweep of survivors" {
  # *Named* by @just-nik (#27146): CONTROL_CANNOT_FIRE is a different state from
  # CONTROL_FAILED and from NOT_RUN. This fixture's test touches nothing, so every
  # mutant would "survive" — and reporting that as a set of negative results says
  # "your tests do not check this" when the truth is "no test could have".
  printf 'x = 1\n' > "$D/flat.py"
  printf '@%s "t" { true; }\n' test > "$D/flat.bats"
  run python3 "$M" "$D/flat.py" "$D/flat.bats"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot detect a change there at all"* ]]
  [[ "$output" == *"incapable control"* ]]
  [[ "$output" != *"SURVIVED"* ]]
}

@test "zero applicable mutations is UNKNOWN, never 0 killed 0 survived" {
  # A CAPABLE suite with nothing to mutate — the other UNKNOWN, and it needs a
  # fixture the tests actually exercise or the capability probe fires first and this
  # path is never reached.
  printf 'import sys\nsys.exit(7)\n' > "$D/flat.py"
  { printf '@%s "t" {\n' test
    printf '  run python3 "%s/flat.py"\n' "$D"
    printf '  [ "$status" -eq 7 ]\n}\n'; } > "$D/flat.bats"
  run python3 "$M" "$D/flat.py" "$D/flat.bats"
  [ "$status" -eq 2 ]
  [[ "$output" == *"capability"* ]]        # the probe passed, so this is the real path
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
  # Wait for the OBSERVABLE, not a clock. `sleep 5` was calibrated before the
  # capability probe added a test run in front of the mutation loop, and it broke the
  # moment that landed — the same clock-dependency fixed in witness.bats one cycle
  # ago and left here, which is the third time a fix has stopped at one of a pair.
  for _ in $(seq 1 400); do
    [ -f "$M/subj.py.mutate-original" ] && break
    sleep 0.1
  done
  [ -f "$M/subj.py.mutate-original" ]
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
  # Written by the PRODUCTION writer, not by cp. A hand-made crumb tests a format
  # this tool no longer uses, and would have gone on passing after the record grew
  # a header — the same defect as building the state you then recover.
  ( cd "$M" && crumb_py "
m.write_crumb(pathlib.Path('subj.py.mutate-original'), pathlib.Path('subj.py'),
              pathlib.Path('subj.py').read_text())" )
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
  ( cd "$M" && crumb_py "
m.write_crumb(pathlib.Path('subj.py.mutate-original'), pathlib.Path('subj.py'),
              pathlib.Path('subj.py').read_text())" )
  printf 'import sys\nif True:  # mutant\n    pass\n' > "$M/subj.py"
  [ "$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)" != "$before" ]
  ( cd "$M" && crumb_py "
saved, st = m.read_crumb(pathlib.Path('subj.py.mutate-original'), pathlib.Path('subj.py'))
assert st == 'valid', st
pathlib.Path('subj.py').write_text(saved)
pathlib.Path('subj.py.mutate-original').unlink()" )
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
  for _ in $(seq 1 400); do
    [ -f "$M/subj.py.mutate-original" ] && break
    sleep 0.1
  done
  # While the run is still inside the mutation loop.
  [ -f "$M/subj.py.mutate-original" ]
  # The crumb's PAYLOAD is the original — the record also carries a header, so a
  # whole-file hash would be comparing a record against a file.
  ( cd "$M" && crumb_py "
saved, st = m.read_crumb(pathlib.Path('subj.py.mutate-original'), pathlib.Path('subj.py'))
assert st == 'valid', st
import hashlib; print(hashlib.sha256(saved.encode()).hexdigest())" ) | grep -q "$before"
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
  # Whatever the verdict, the original must still be recoverable — and recoverable
  # means the record verifies, not merely that a file is present.
  [ -f "$M/subj.py.mutate-original" ]
  ( cd "$M" && crumb_py "
saved, st = m.read_crumb(pathlib.Path('subj.py.mutate-original'), pathlib.Path('subj.py'))
assert st == 'valid', st
import hashlib; print(hashlib.sha256(saved.encode()).hexdigest())" ) | grep -q "$before"
}

# ── the crumb protects the subject; what protects the crumb ──────────────────
#
# *Named* by @kolpaq (#26742): the crumb-before-mutation shape is atomic-write, and
# nothing was applying that shape to the crumb itself. A SIGKILL mid-write leaves a
# file that EXISTS and is short — and the recovery this tool prints, `mv crumb
# target`, would then install a truncated original over a working file. The recovery
# path doing the damage it exists to prevent.
#
# Spec from @nadir-codex (#26761): temp + fsync + atomic rename; a record carrying a
# version, the target, the payload length and its digest; and three outcomes at
# recovery — absent, valid, corrupt — because a partial record read as "absent"
# turns a crash into a silent skip of recovery.

MU="${BATS_TEST_DIRNAME}/../scripts/mutate"

crumb_py() {  # run python with mutate importable as `m`
  python3 -c "
import sys, importlib.util, importlib.machinery, pathlib, os, time, subprocess
l = importlib.machinery.SourceFileLoader('mu', '$MU')
sp = importlib.util.spec_from_loader('mu', l)
m = importlib.util.module_from_spec(sp); sys.modules['mu'] = m; l.exec_module(m)
$1"
}

@test "a killed crumb write is never CORRUPT, only absent or valid" {
  # The falsifiable test @nadir-codex asked for, with the control that makes it able
  # to fail: the naive writer this replaces is corrupt at most kill points.
  #
  # The writers are FILES, not strings nested three quoting levels deep. The first
  # version embedded them in a python -c inside a bats string, a backslash-n became
  # a real newline, both writers died on a SyntaxError, no crumb was ever written —
  # and "the atomic writer never corrupts" passed on a probe that measured nothing.
  # The control is what caught it.
  cd "$BATS_TEST_TMPDIR"
  printf 'x = 1\n' > subj.py
  cat > w_atomic.py <<PYEOF
import sys, importlib.util, importlib.machinery, pathlib
l = importlib.machinery.SourceFileLoader("mu", "$MU")
sp = importlib.util.spec_from_loader("mu", l)
m = importlib.util.module_from_spec(sp); sys.modules["mu"] = m; l.exec_module(m)
m.write_crumb(pathlib.Path("subj.py.mutate-original"), pathlib.Path("subj.py"),
              "x = 1\n" * 40000)
PYEOF
  cat > w_naive.py <<'PYEOF'
import time
d = ("x = 1" + chr(10)) * 40000
with open("subj.py.mutate-original", "w") as fh:
    for i in range(0, len(d), 4096):
        fh.write(d[i:i + 4096]); fh.flush(); time.sleep(0.002)
PYEOF
  # Both writers must actually run, or every outcome is `absent` and the property
  # under test is never exercised. Checked before the kill loop, not after.
  run python3 w_atomic.py
  [ "$status" -eq 0 ]
  run python3 w_naive.py
  [ "$status" -eq 0 ]
  rm -f subj.py.mutate-original

  run crumb_py "
t = pathlib.Path('subj.py'); c = pathlib.Path('subj.py.mutate-original')
def kill_during(script, delays):
    out = []
    for d in delays:
        c.unlink(missing_ok=True)
        for j in pathlib.Path('.').glob('*.tmp'): j.unlink()
        p = subprocess.Popen([sys.executable, script]); time.sleep(d)
        p.kill(); p.wait()
        st = m.read_crumb(c, t)[1]
        out.append(st if st in ('absent', 'valid') else 'CORRUPT')
    return out
ds = [0.02, 0.04, 0.06, 0.08, 0.10]
print('ATOMIC', kill_during('w_atomic.py', ds))
print('NAIVE', kill_during('w_naive.py', ds))
"
  [ "$status" -eq 0 ]
  atomic_line=$(printf '%s\n' "$output" | grep "^ATOMIC")
  naive_line=$(printf '%s\n' "$output" | grep "^NAIVE")
  [ -n "$atomic_line" ]
  [ -n "$naive_line" ]
  # What this shows, stated narrowly: at these kill points the writer never leaves a
  # corrupt record. It does NOT prove atomicity — measured, the whole write of a 12MB
  # payload takes 73ms on this machine and the import before it dominates, so no
  # sleep reliably lands inside the write. The control corrupts because it is PACED,
  # not because the probe can find the window. Atomicity is pinned by the mechanism
  # test below instead.
  [[ "$atomic_line" != *"CORRUPT"* ]]
  # The control: the writer this replaces DOES corrupt, so the line above is not
  # passing because the probe cannot see corruption.
  [[ "$naive_line" == *"CORRUPT"* ]]
  # And the atomic writer reached `valid` at least once, or "never corrupt" is being
  # satisfied by never writing anything.
  [[ "$atomic_line" == *"valid"* ]]
}


@test "recovery has three outcomes, and names the cause of the third" {
  cd "$BATS_TEST_TMPDIR"
  printf 'x = 1\ny = 2\n' > subj.py
  run crumb_py "
t = pathlib.Path('subj.py'); c = pathlib.Path('subj.py.mutate-original')
m.write_crumb(c, t, t.read_text())
raw = c.read_bytes(); nl = raw.index(b'\n')
print('COMPLETE', m.read_crumb(c, t)[1])
c.write_bytes(raw[:nl + 5]); print('SHORTPAY', m.read_crumb(c, t)[1])
c.write_bytes(raw[:nl - 3]); print('SHORTHDR', m.read_crumb(c, t)[1])
c.write_bytes(raw[:nl + 1] + b'x' * (len(raw) - nl - 1)); print('BADDIGEST', m.read_crumb(c, t)[1])
c.unlink(); print('GONE', m.read_crumb(c, t)[1])
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMPLETE valid"* ]]
  [[ "$output" == *"GONE absent"* ]]
  # Each corrupt shape names its own cause rather than collapsing to one word.
  [[ "$output" == *"SHORTPAY the record claims"* ]]
  [[ "$output" == *"SHORTHDR the record has no header line"* ]]
  [[ "$output" == *"BADDIGEST the payload does not match its digest"* ]]
}

@test "a corrupt crumb is quarantined, never offered as an undo" {
  # The damage path this closes: telling somebody to `mv` a truncated record over a
  # working file. A valid record gets the mv; a partial one must not.
  mut_fixture
  before=$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)
  printf 'solo-mutate-crumb v1 subj.py deadbeef 999\nhalf' > "$M/subj.py.mutate-original"
  run bash -c "cd '$M' && python3 '$MU' --file subj.py --test tests/t.bats 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"CORRUPT"* ]]
  [[ "$output" == *"Do NOT move it"* ]]
  [[ "$output" == *"truncated original"* ]]
  [[ "$output" != *"mv subj.py.mutate-original subj.py"* ]]
  # And it left the subject alone.
  [ "$(shasum -a256 "$M/subj.py" | cut -d' ' -f1)" = "$before" ]
}

@test "the crumb appears only by rename, never by writing the crumb path" {
  # Deterministic where the timing test cannot be. `os.replace` is intercepted in a
  # child, so the mechanism is observed rather than inferred from when a kill landed.
  #
  # This is what actually kills the mutation "write straight to the crumb": that
  # mutant survived a kill-timing probe on this machine, because the write window is
  # narrower than the import that precedes it.
  cd "$BATS_TEST_TMPDIR"
  printf 'x = 1\n' > subj.py
  run crumb_py "
import os
calls = []
real = os.replace
def spy(a, b, *r, **k):
    calls.append((str(a), str(b)))
    return real(a, b, *r, **k)
os.replace = spy
opened = []
real_open = open
import builtins
def spy_open(f, mode='r', *r, **k):
    if 'w' in str(mode) or 'a' in str(mode):
        opened.append(str(f))
    return real_open(f, mode, *r, **k)
builtins.open = spy_open
m.write_crumb(pathlib.Path('subj.py.mutate-original'), pathlib.Path('subj.py'), 'x = 1')
builtins.open = real_open
os.replace = real
print('RENAMED', calls)
print('OPENED', opened)
"
  [ "$status" -eq 0 ]
  # Exactly one rename, from a temp path onto the crumb.
  [[ "$output" == *"RENAMED [('subj.py.mutate-original.tmp', 'subj.py.mutate-original')]"* ]]
  # And the crumb path itself was never opened for writing.
  [[ "$output" == *"OPENED ['subj.py.mutate-original.tmp']"* ]]
}
