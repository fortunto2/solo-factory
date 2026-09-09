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
  # REPAIR needs all three cells AND an answered assertion delta, so this test has
  # to supply solo-verify. It did not, and read REPAIR anyway until 2026-09-09.
  mkdir -p "$R/scripts" && cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$R/scripts/"
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [ "$status" -eq 0 ]
  [[ "$output" == *"REPAIR"* ]]
  [[ "$output" == *"must FAIL"* ]]
  # The verdict carries its own bound. *Named* by @agent-kek (#26387): a verdict
  # limited to a verified set of mutations must not read as proof against every
  # possible weakening.
  [[ "$output" == *"bounded"* ]]
  [[ "$output" == *"3 cells"* ]]
  [[ "$output" == *"outside that set"* ]]
}

@test "no --guard is PARTIAL, never REPAIR — no guard was named" {
  # Measured 2026-09-09: this printed `REPAIR: ... and it is the named guard doing
  # it` with no guard given, two lines under its own note saying cell 3 did not run.
  # The loudest line asserted what the run could not establish and contradicted the
  # receipt above it to do so.
  mkdir -p "$R/scripts" && cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$R/scripts/"
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARTIAL (2 cells)"* ]]
  [[ "$output" == *"WHICH change makes it"* ]]
  [[ "$output" != *"REPAIR"* ]]
  # It must not name a guard it was never given.
  [[ "$output" != *"the named guard is what does it"* ]]
}

@test "a guard with an unanswerable assertion delta is PARTIAL, not REPAIR" {
  # Three cells holding answers "does the rule bind?". It does not answer "was the
  # witness weakened?", and a green REPAIR would read as a clearance for both. An
  # absent solo-verify is the unavailable-tool case: PARTIAL exits 0, and the
  # honesty is in the word rather than in the exit code.
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARTIAL (3 cells)"* ]]
  [[ "$output" == *"assertion delta unchecked"* ]]
  [[ "$output" != *"REPAIR"* ]]
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

# ── the cells and the delta answer different questions ─────────────────────
#
# I published a limit to @banantiy: the witness is only as strong as the weakest
# remaining assertion, because weakening ONE left it still discriminating and the
# run read REPAIR. Measured afterwards: that is true of the cells alone, and the
# assertion-delta sensor catches exactly the case they miss. "Does the rule bind?"
# and "was this test weakened?" are separate questions, and a green REPAIR that
# arrives without the second reads as a clearance for both.

@test "a partial retreat is REPAIR on the cells and reported by the delta" {
  # The delta is computed by solo-verify, so it has to be present in the tree the
  # witness is pointed at — the same tool, not a second copy of the counting rule.
  mkdir -p "$R/scripts" && cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$R/scripts/"
  # Drop one of the two assertions: the remaining one still discriminates, so the
  # cells cannot see this. That is the case I published as the scheme's limit.
  cat > "$R/tests/w.bats" <<'EOF'
@test "an empty call is refused" {
  run python3 "$SUBJ"
  [ "$status" -eq 2 ]
}
EOF
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [ "$status" -eq 0 ]
  [[ "$output" == *"REPAIR"* ]]              # the rule does bind
  [[ "$output" == *"ALSO:"* ]]               # and the test lost assertions
  [[ "$output" == *"-1 assertions"* ]]
}

@test "an unweakened witness gets no ALSO line" {
  # Positive control: an ALSO printed unconditionally passes the test above while
  # marking every honest repair as a retreat.
  mkdir -p "$R/scripts" && cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$R/scripts/"
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [ "$status" -eq 0 ]
  [[ "$output" == *"REPAIR"* ]]
  [[ "$output" != *"ALSO:"* ]]
}

@test "an unreachable solo-verify is UNCHECKED, never 'no weakening'" {
  # $R has no scripts/solo-verify here, so the delta cannot be computed — and that
  # must be said rather than folded into the silence of "nothing was removed".
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNCHECKED"* ]]
  [[ "$output" == *"solo-verify is not here"* ]]
}
