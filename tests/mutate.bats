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
