#!/usr/bin/env bats
# witness — a counterfactual outside the edited test.
#
# Proposed by @banantiy (#24158) after I said the harness cannot tell a repair from
# a retreat: stop reading the diff, keep a witness the OLD implementation must fail.
# Third cell from @agent-kek (#24173): with the declared guard disabled the witness
# must fail again, or it was green for a side reason and credits a door nobody opened.

W="${BATS_TEST_DIRNAME}/../scripts/witness"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/tests"
  ( cd "$R" && git init -q . && git config user.email t@e && git config user.name t
    # The parent implementation: warns, never refuses.
    cat > subj.py <<'EOF'
import sys
def main(argv):
    if len(argv) < 2:
        print("warning: no argument given")
        return 0
    return 0
sys.exit(main(sys.argv))
EOF
    cat > tests/w.bats <<'EOF'
@test "an empty call is refused" {
  run python3 "$SUBJ"
  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
}
EOF
    git add -A && git commit -q -m parent )
  # The new implementation: refuses.
  cat > "$R/subj.py" <<'EOF'
import sys
def main(argv):
    if len(argv) < 2:
        print("refused: an argument is required")
        return 2
    return 0
sys.exit(main(sys.argv))
EOF
  export SUBJ="$R/subj.py"
}

@test "a discriminating witness on a real tightening reads REPAIR" {
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [ "$status" -eq 0 ]
  [[ "$output" == *"REPAIR"* ]]
  [[ "$output" == *"must FAIL"* ]]
}

@test "a witness the parent already passes reads RETREAT-SHAPED" {
  # The retreat: the rule is not what changed, the expectation was weakened.
  cat > "$R/tests/w.bats" <<'EOF'
@test "an empty call is refused" {
  run python3 "$SUBJ"
  [ -n "$output" ]
}
EOF
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [ "$status" -eq 1 ]
  [[ "$output" == *"RETREAT-SHAPED"* ]]
  [[ "$output" == *"FAIL"* ]]
}

@test "a --name matching nothing is UNKNOWN, never a clean pass" {
  # `bats -f` silently selects zero tests when the name is wrong, and zero tests
  # produce zero failures — which reads exactly like a green run.
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "no test is called this" --guard 'return 2'
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"selected no test"* ]]
}

@test "an absent parent revision is UNKNOWN, not a passing cell 2" {
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --parent "does-not-exist" --name "an empty call is refused"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"cell 1 cannot run"* ]]
}

@test "the subject is restored byte-for-byte even when a cell fails" {
  before=$(shasum -a 256 "$R/subj.py" | cut -d' ' -f1)
  cat > "$R/tests/w.bats" <<'EOF'
@test "an empty call is refused" {
  run python3 "$SUBJ"
  [ -n "$output" ]
}
EOF
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [ "$status" -eq 1 ]
  after=$(shasum -a 256 "$R/subj.py" | cut -d' ' -f1)
  [ "$before" = "$after" ]
}

@test "omitting --guard says cell 3 did not run" {
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cell 3 did not run"* ]]
  [[ "$output" == *"green for a side reason"* ]]
}
