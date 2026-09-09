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
  cp "$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests" "$R/scripts/"
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
  [[ "$output" == *"weighs strength"* ]]
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
  # check-vacuous-tests likewise: absent, it is UNCHECKED and the verdict is
  # PARTIAL for that reason rather than for the one under test here.
  mkdir -p "$R/scripts" && cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$R/scripts/"
  cp "$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests" "$R/scripts/"
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
  cp "$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests" "$R/scripts/"
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

# ── the delta counts assertions; it cannot weigh them ────────────────────────
#
# Measured 2026-09-09 on three shapes of one weakening:
#   2 strong -> 3 negative       delta silent, check-vacuous-tests catches it
#   2 strong -> 3 weak positive  both silent — not decidable, and stated as such
#   count goes down              delta catches it
# The first was published on the board as the open hole while a checker in this
# repo already caught it. So witness now RUNS that checker instead of leaving it
# to a hook a stranger running witness standalone would never trigger.

absence_fixture() {  # cells all hold AND the witness is absence-only
  A="$BATS_TEST_TMPDIR/abs"
  mkdir -p "$A/tests" "$A/scripts"
  ( cd "$A" && git init -q . && git config user.email t@e && git config user.name t
    cat > subj.py <<'EOF'
import sys
def main(argv):
    if len(argv) < 2:
        print("warning: no argument given")
        return 0
    return 0
sys.exit(main(sys.argv))
EOF
    # The token is assembled at runtime: bats rewrites a literal @test inside a
    # heredoc into bats_test_function, which still RUNS but is invisible to any
    # checker that parses for @test. Cells passed and the absence check went blind
    # — the trap this repo recorded once already, walked into again here.
    { printf '@%s "no warning is printed" {\n' test
      printf '  run python3 "$SUBJ"\n'
      printf '  [[ "$output" != *"warning"* ]]\n}\n'; } > tests/w.bats
    git add -A && git commit -q -m parent )
  # The guard, when disabled, falls back to the parent's message — so cell 3 holds
  # and every cell is green while the witness passes on empty output.
  cat > "$A/subj.py" <<'EOF'
import sys
def main(argv):
    if len(argv) < 2:
        if True:
            print("refused: an argument is required")
            return 2
        print("warning: no argument given")
        return 0
    return 0
sys.exit(main(sys.argv))
EOF
  cp "$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests" "$A/scripts/"
  cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$A/scripts/"
  export SUBJ="$A/subj.py"
}

@test "an absence-only witness is PARTIAL even when every cell holds" {
  # Known-answer: with this branch disabled the same input prints REPAIR — a full
  # green for a witness that passes on empty output.
  absence_fixture
  run python3 "$W" --root "$A" --subject subj.py --test tests/w.bats \
      --name "no warning is printed" --guard 'if True:'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   new − guard + W must FAIL"* ]]
  [[ "$output" == *"PARTIAL (3 cells)"* ]]
  [[ "$output" == *"absence-only, which is a retreat"* ]]
  [[ "$output" != *"REPAIR"* ]]
}

@test "an absence-only witness is named, with what hides it" {
  absence_fixture
  run python3 "$W" --root "$A" --subject subj.py --test tests/w.bats \
      --name "no warning is printed" --guard 'if True:'
  [[ "$output" == *"asserts only absence"* ]]
  [[ "$output" == *"the delta reads as an addition"* ]]
}

@test "the REPAIR bound says what neither check weighs" {
  # "bounded" without stating the bound is the same defect one level up. The
  # residual is named because it is not decidable, not because nobody tried.
  mkdir -p "$R/scripts"
  cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$R/scripts/"
  cp "$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests" "$R/scripts/"
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [ "$status" -eq 0 ]
  [[ "$output" == *"REPAIR"* ]]
  [[ "$output" == *"weighs strength"* ]]
  [[ "$output" == *"did not run here"* ]]   # --width was not passed here
}

@test "an unreachable check-vacuous-tests is UNCHECKED, never 'no weakening'" {
  # Same rule as the delta beside it: an absent tool must not turn red into green.
  mkdir -p "$R/scripts" && cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$R/scripts/"
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [ "$status" -eq 0 ]
  [[ "$output" == *"absence-only check UNCHECKED"* ]]
  [[ "$output" == *"PARTIAL"* ]]
  [[ "$output" != *"REPAIR"* ]]
}

# ── discrimination width ─────────────────────────────────────────────────────
#
# *Proposed* by @agent-kek (#26431) after this repo said assertion strength was
# undecidable: fix a minimal mutation set per fixture rather than decide strength
# in general. Measured before building, on two witnesses over one parent:
#   2 strong assertions   width 2 of 2
#   3 weak positive ones  width 1 of 3
# Both discriminate as a whole, both keep every cell green, and the count went UP.

width_witness() {  # $1 = the assertion block
  mkdir -p "$R/scripts"
  cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$R/scripts/"
  cp "$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests" "$R/scripts/"
  { printf '@%s "an empty call is refused" {\n' test
    printf '  run python3 "$SUBJ"\n'
    printf '%s' "$1"
    printf '}\n'; } > "$R/tests/w.bats"
}

@test "width counts assertions that individually fail the parent" {
  width_witness '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [ "$status" -eq 0 ]
  [[ "$output" == *"discrimination width 2 of 2"* ]]
}

@test "a witness that grew while narrowing shows a lower width" {
  # The case the count cannot see: three statements where one carries the whole
  # discrimination. assertions_removed reports an ADDITION here.
  width_witness '  [[ -n "$output" ]]
  [[ "$output" == *"e"* ]]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [ "$status" -eq 0 ]
  [[ "$output" == *"discrimination width 1 of"* ]]
  # And it says what it could not classify, rather than shrinking the denominator
  # in silence: an unrecognised statement is present in every variant, not absent.
  [[ "$output" == *"classifier does not recognise"* ]]
}

@test "width is UNCHECKED when something else fails the parent" {
  # The control. Unclassified statements sit in EVERY variant, so one of them
  # failing the parent makes every variant fail and returns a full mark for a
  # witness whose assertions do nothing.
  # Neither table matches this: NEGATIVE needs `[[`, POSITIVE needs -eq/-ne or a
  # ==/toBe form. It is a real check that fails the parent and is invisible here.
  width_witness '  [ "${output#*refused}" != "$output" ]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [[ "$output" == *"discrimination width UNCHECKED"* ]]
  [[ "$output" == *"something else in the test body"* ]]
  [[ "$output" != *"discrimination width 2"* ]]
}

@test "the stated bound changes with what actually ran" {
  # A fixed sentence goes stale the moment a check is added — it did, twice. First
  # when --width arrived and the bound still called strength unmeasured; then when
  # the parent comparison arrived and the bound claimed narrowing was visible on
  # runs where no comparison had happened.
  narrow_fixture '  [ "$status" -eq 2 ]
' '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [ "$status" -eq 0 ]
  [[ "$output" == *"discrimination width): the"* ]]
  [[ "$output" == *"compared against the parent revision"* ]]
  [[ "$output" != *"NOT compared"* ]]
  # Without --width the bound must claim neither the width nor the comparison.
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2'
  [[ "$output" != *"Width measured"* ]]
  [[ "$output" == *"did not run here"* ]]
}

@test "the witness file is restored after a width run" {
  # It rewrites the test file once per assertion. `restored` is a fact about the
  # bytes, checked the same way `applied` is.
  width_witness '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
'
  before=$(shasum -a256 "$R/tests/w.bats" | cut -d" " -f1)
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  after=$(shasum -a256 "$R/tests/w.bats" | cut -d" " -f1)
  [ "$before" = "$after" ]
}

# ── the invariant the measure owes itself ────────────────────────────────────
#
# @agent-kek (#26477) asked for a pairwise subset: each assertion individually
# sufficient while a PAIR together loses discriminability. Measured on bats 1.14.0
# — it aborts on the first failing assertion, so adding assertions is monotone and
# a pair cannot lose what a member has. That mechanism buys nothing.
#
# The same monotonicity gives an invariant the measure can check on ITSELF: with
# cell 1 holding and the control passed, at least one assertion must fail the
# parent, so width cannot be 0. A 0 is the instrument contradicting its premise.

@test "width 0 while the witness fails the parent is UNCHECKED, not a low score" {
  # Reachable on a legitimate input: the discriminating assertions share a line, so
  # they are never isolated, and the one assertion that IS isolable passes on the
  # parent. Not a broken tool — an isolation that could not cover the discrimination.
  mkdir -p "$R/scripts"
  cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$R/scripts/"
  cp "$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests" "$R/scripts/"
  { printf '@%s "an empty call is refused" {\n' test
    printf '  run python3 "$SUBJ"\n'
    printf '  [[ "$output" == *"e"* ]]\n'
    printf '  [ "$status" -eq 2 ]; [[ "$output" == *"refused"* ]]\n}\n'; } > "$R/tests/w.bats"
  run python3 "$W" --root "$R" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [ "$status" -eq 0 ]
  [[ "$output" == *"discrimination width UNCHECKED"* ]]
  # The cause is named from what was observed, not guessed: assertions shared a line.
  [[ "$output" == *"sharing a line were never isolated"* ]]
  [[ "$output" != *"discrimination width 0"* ]]
  [[ "$output" == *"PARTIAL"* ]]
}

@test "bats aborts on the first failing assertion — the premise, pinned" {
  # The invariant above rests on this. If a bats upgrade ever stops aborting, the
  # invariant is wrong and this test says so before the width check misreports.
  { printf '@%s "mid-body failure" {\n' test
    printf '  [ 1 -eq 2 ]\n'
    printf '  [ 1 -eq 1 ]\n}\n'; } > "$R/tests/mono.bats"
  run bats "$R/tests/mono.bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not ok"* ]]
}

# ── narrowing: a width that FELL across the change ───────────────────────────
#
# An absolute width is not a defect — a one-assertion witness is honestly 1 of 1,
# and a threshold on it fires on honest witnesses and gets the check deleted. A
# width that fell IS a defect, because it is a fact about the change rather than
# about the witness. Named as unbuilt for three cycles before this.

narrow_fixture() {  # $1 = parent test body, $2 = current test body
  N="$BATS_TEST_TMPDIR/narrow"
  mkdir -p "$N/tests" "$N/scripts"
  ( cd "$N" && git init -q . && git config user.email t@e && git config user.name t
    cat > subj.py <<'EOF'
import sys
def main(argv):
    if len(argv) < 2:
        print("warning: no argument given")
        return 0
    return 0
sys.exit(main(sys.argv))
EOF
    { printf '@%s "an empty call is refused" {\n' test
      printf '  run python3 "$SUBJ"\n'; printf '%s' "$1"; printf '}\n'; } > tests/w.bats
    git add -A && git commit -q -m parent )
  cat > "$N/subj.py" <<'EOF'
import sys
def main(argv):
    if len(argv) < 2:
        print("refused: an argument is required")
        return 2
    return 0
sys.exit(main(sys.argv))
EOF
  { printf '@%s "an empty call is refused" {\n' test
    printf '  run python3 "$SUBJ"\n'; printf '%s' "$2"; printf '}\n'; } > "$N/tests/w.bats"
  cp "$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests" "$N/scripts/"
  cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$N/scripts/"
  export SUBJ="$N/subj.py"
}

@test "a witness that narrowed across the change is a retreat, not a REPAIR" {
  # Every cell holds. The assertion count went UP, so assertions_removed reports an
  # addition. All three are positive, so check-vacuous-tests is silent. Before this
  # comparison existed, the verdict was REPAIR — verified by disabling the branch.
  narrow_fixture '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
' '  [[ "$output" == *"e"* ]]
  [[ "$output" == *"i"* ]]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   new − guard + W must FAIL"* ]]
  [[ "$output" == *"NARROWED: 2 of 2 at HEAD, 1 of 3 now"* ]]
  [[ "$output" == *"narrowed across this change, which is a retreat"* ]]
  [[ "$output" != *"REPAIR"* ]]
}

@test "a witness that did not narrow says so, rather than staying silent" {
  # Silence would make "not narrowed" and "never compared" the same line.
  narrow_fixture '  [ "$status" -eq 2 ]
' '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [ "$status" -eq 0 ]
  [[ "$output" == *"not narrowed (1 of 1 at HEAD)"* ]]
  [[ "$output" == *"REPAIR"* ]]
}

@test "an unchanged witness file says there is nothing to compare" {
  narrow_fixture '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
' '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [[ "$output" == *"unchanged in this revision"* ]]
  [[ "$output" != *"NARROWED"* ]]
}

@test "the witness file survives a comparison that rewrites it twice" {
  # The parent revision is written to the same path to be measured. `restored` is a
  # fact about the bytes, and this one has two chances to go wrong.
  narrow_fixture '  [ "$status" -eq 2 ]
' '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
'
  before=$(shasum -a256 "$N/tests/w.bats" | cut -d" " -f1)
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  after=$(shasum -a256 "$N/tests/w.bats" | cut -d" " -f1)
  [ "$before" = "$after" ]
}

@test "an equal width is not a narrowing" {
  # `>` versus `>=` — the mutation that survived the first round of these tests,
  # because every case had before < now or before > now and none had them equal.
  # A file that changed without changing the width must not read as a retreat.
  narrow_fixture '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
' '  # a comment added by this change
  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [ "$status" -eq 0 ]
  [[ "$output" == *"not narrowed (2 of 2 at HEAD)"* ]]
  [[ "$output" != *"NARROWED"* ]]
  [[ "$output" == *"REPAIR"* ]]
}

@test "a parent width that could not be measured is not 'not narrowed'" {
  # Silence-as-clean, one level down: an unmeasurable BEFORE and a BEFORE that did
  # not narrow are different facts, and the second is a claim the run cannot make.
  # Here the parent's assertions share a line, so none can be isolated.
  narrow_fixture '  [ "$status" -eq 2 ]; [[ "$output" == *"refused"* ]]
' '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [[ "$output" == *"could NOT be measured"* ]]
  [[ "$output" == *"so no comparison"* ]]
  [[ "$output" != *"not narrowed"* ]]
}

@test "an unmeasurable parent width demotes: a check that could not run leaves no green" {
  # *Named* by @agent-kek (#26545): keep could-not-measure hard and separate, or the
  # demotion turns into a false "did not narrow". Measured on his point — this
  # printed REPAIR while the narrowing comparison had not run. The rule that an
  # absent tool must not turn red into green, broken inside the tool that publishes
  # it. The earlier test asserted the MESSAGE and never the verdict, which is how it
  # stayed green.
  narrow_fixture '  [ "$status" -eq 2 ]; [[ "$output" == *"refused"* ]]
' '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [ "$status" -eq 0 ]
  [[ "$output" == *"[could-not-measure]"* ]]
  [[ "$output" == *"PARTIAL"* ]]
  [[ "$output" != *"REPAIR"* ]]
  [[ "$output" == *"narrowing comparison did not run"* ]]
}

@test "the verdict reads a state, not a word inside a sentence" {
  # The gate used to search the human-readable note for "NARROWED". A verdict keyed
  # on a substring of prose is one rewording away from silently never firing, and
  # nothing would have failed when it stopped.
  narrow_fixture '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
' '  [[ "$output" == *"e"* ]]
  [[ "$output" == *"i"* ]]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [[ "$output" == *"[narrowed]"* ]]
  [[ "$output" == *"narrowed across this change"* ]]
}

@test "the bound distinguishes 'no change to compare' from 'could not compare'" {
  # The mutation that survived: making the bound claim a comparison whenever width
  # ran. Every fixture had the comparison actually running, so nothing noticed.
  # And the two no-comparison cases are different claims — an unchanged witness
  # cannot have narrowed, an uncompared one might have.
  narrow_fixture '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
' '  [ "$status" -eq 2 ]
  [[ "$output" == *"refused"* ]]
'
  run python3 "$W" --root "$N" --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width
  [ "$status" -eq 0 ]
  [[ "$output" == *"[unchanged]"* ]]
  [[ "$output" == *"REPAIR"* ]]
  [[ "$output" == *"did not change in this revision"* ]]
  [[ "$output" != *"AND compared against"* ]]
  [[ "$output" != *"NOT compared against"* ]]
}

# ── witness edits TWO files, and both were left damaged when killed ──────────
#
# Measured 2026-09-09, after the same class was fixed in scripts/mutate: SIGTERM
# during --width left the subject holding the parent implementation AND the test
# file holding a single-assertion variant. The second is the worse of the two — a
# witness cut down to one assertion looks like a plausible test rather than obvious
# damage, so it survives a glance and gets committed.

sig_fixture() {
  P="$BATS_TEST_TMPDIR/sig"
  mkdir -p "$P/tests" "$P/scripts"
  ( cd "$P" && git init -q . && git config user.email t@e && git config user.name t
    cat > subj.py <<'EOF'
import sys
def main(argv):
    if len(argv) < 2:
        print("warning: no argument given")
        return 0
    return 0
sys.exit(main(sys.argv))
EOF
    { printf '@%s "an empty call is refused" {\n' test
      printf '  sleep 3\n'
      printf '  run python3 "$SUBJ"\n'
      printf '  [ "$status" -eq 2 ]\n'
      printf '  [[ "$output" == *"refused"* ]]\n}\n'; } > tests/w.bats
    git add -A && git commit -q -m parent )
  cat > "$P/subj.py" <<'EOF'
import sys
def main(argv):
    if len(argv) < 2:
        print("refused: an argument is required")
        return 2
    return 0
sys.exit(main(sys.argv))
EOF
  cp "$BATS_TEST_DIRNAME/../scripts/check-vacuous-tests" "$P/scripts/"
  cp "$BATS_TEST_DIRNAME/../scripts/solo-verify" "$P/scripts/"
  export SUBJ="$P/subj.py"
}

@test "SIGTERM mid-run restores BOTH the subject and the test file" {
  sig_fixture
  sb=$(shasum -a256 "$P/subj.py" | cut -d' ' -f1)
  tb=$(shasum -a256 "$P/tests/w.bats" | cut -d' ' -f1)
  ( cd "$P" && python3 "$W" --root . --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width >/dev/null 2>&1 ) &
  bg=$!
  # Wait for the OBSERVABLE state, not for a number of seconds. `sleep 4` was a
  # guess about how long the run takes to reach its editing phase, and it went flaky
  # at ~1 run in 6 once the suite began running 30 files at once — the guess was
  # calibrated on an idle machine. The crumb appearing IS the editing phase starting.
  for _ in $(seq 1 300); do
    [ -f "$P/subj.py.mutate-original" ] && break
    sleep 0.1
  done
  [ -f "$P/subj.py.mutate-original" ]   # or the kill below lands before anything ran
  pkill -TERM -f "scripts/witness --root . --subject subj.py" || true
  wait $bg 2>/dev/null || true
  # Same as in mutate.bats: no fixed sleep. The crumbs disappearing IS the restore
  # completing, so that is what the test waits for.
  for _ in $(seq 1 100); do
    [ -f "$P/subj.py.mutate-original" ] || break
    sleep 0.1
  done
  [ "$(shasum -a256 "$P/subj.py" | cut -d' ' -f1)" = "$sb" ]
  [ "$(shasum -a256 "$P/tests/w.bats" | cut -d' ' -f1)" = "$tb" ]
  # A clean interruption leaves no records behind either.
  [ ! -f "$P/subj.py.mutate-original" ]
  [ ! -f "$P/tests/w.bats.mutate-original" ]
}

@test "a record for EITHER file makes the next run refuse" {
  # The test file is guarded too, not just the subject. Guarding only the obvious
  # one would leave the more dangerous damage undetected.
  sig_fixture
  ( cd "$P" && python3 -c "
import sys, pathlib
sys.path.insert(0, '$BATS_TEST_DIRNAME/../scripts')
from _safe_edit import write_crumb, crumb_for
t = pathlib.Path('tests/w.bats')
write_crumb(crumb_for(t), t, t.read_text())" )
  run bash -c "cd '$P' && python3 '$W' --root . --subject subj.py --test tests/w.bats --name 'an empty call is refused' --guard 'return 2' 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"w.bats.mutate-original"* ]]
  [[ "$output" == *"killed before it could restore"* ]]
}

@test "one implementation of the crumb, not two" {
  # mutate and witness both edit files in place and both restore them. A second copy
  # of the crumb format would be the two-places-disagreeing defect this repo keeps
  # paying for — and it would drift silently, because each tool's tests would pass
  # against its own copy.
  cd "$BATS_TEST_DIRNAME/.."
  run grep -c "solo-mutate-crumb" scripts/_safe_edit.py
  [ "$output" -ge 1 ]
  # Neither tool may define the format itself.
  run bash -c "grep -l 'CRUMB_V = ' scripts/* 2>/dev/null | grep -v __pycache__"
  [ "$output" = "scripts/_safe_edit.py" ]
}

@test "SIGKILL leaves a record for the test file, which is what the crumb is for" {
  # The discriminating input. Under SIGTERM the handler raises SystemExit, the stack
  # unwinds, and every `finally` runs — so the test file is restored even with no
  # crumb, and "protect only the subject" survives a SIGTERM probe. SIGKILL does not
  # unwind. There the crumb is the only thing standing between a rewritten witness
  # and a reader who has no idea it was rewritten.
  sig_fixture
  ( cd "$P" && python3 "$W" --root . --subject subj.py --test tests/w.bats \
      --name "an empty call is refused" --guard 'return 2' --width >/dev/null 2>&1 ) &
  bg=$!
  # Same reason as the SIGTERM test: wait for the crumbs, which are the editing
  # phase becoming observable, rather than for a clock.
  for _ in $(seq 1 300); do
    [ -f "$P/tests/w.bats.mutate-original" ] && break
    sleep 0.1
  done
  [ -f "$P/tests/w.bats.mutate-original" ]
  pkill -KILL -f "scripts/witness --root . --subject subj.py" || true
  wait $bg 2>/dev/null || true
  # Both records must exist: the run was killed with no chance to remove them.
  [ -f "$P/subj.py.mutate-original" ]
  [ -f "$P/tests/w.bats.mutate-original" ]
  # And each holds the file it names, verified rather than assumed.
  run bash -c "cd '$P' && python3 -c \"
import sys, pathlib
sys.path.insert(0, '$BATS_TEST_DIRNAME/../scripts')
from _safe_edit import read_crumb, crumb_for
for f in ('subj.py', 'tests/w.bats'):
    t = pathlib.Path(f)
    print(f, read_crumb(crumb_for(t), t)[1])
\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"subj.py valid"* ]]
  [[ "$output" == *"tests/w.bats valid"* ]]
}
