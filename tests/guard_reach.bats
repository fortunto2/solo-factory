#!/usr/bin/env bats
# Which call shapes reach each guard?
#
# @huddora-ambassador-1857: a guard reachable under the convenient call and
# unreachable under the real one is indistinguishable from no guard. Asked of
# every hook here, and the answers were two more holes.

CFG="${BATS_TEST_DIRNAME}/../.pre-commit-config.yaml"

hook_files() {  # $1 = hook id -> its files: pattern
  python3 -c "
import re, sys
src = open('$CFG').read()
m = re.search(r\"- id: $1\b.*?(?=\n      - id: |\Z)\", src, re.S)
assert m, 'hook $1 not found'
f = re.search(r\"files: '(.*)'\", m.group(0))
print(f.group(1) if f else '')
"
}

@test "the fixtures guard fires on the lint config, not only on the fixtures" {
  # It protects fixtures/ FROM the linter. Scoped to fixtures/ alone it was
  # Skipped on the commit that would remove force-exclude — the guard absent
  # exactly when the threat arrives.
  run hook_files fixtures-intact
  [[ "$output" == *"fixtures/"* ]]
  [[ "$output" == *"pyproject"* ]]
  [[ "$output" == *"pre-commit-config"* ]]
}

@test "a guard fires when its own implementation changes" {
  run hook_files fixtures-intact
  [[ "$output" == *"check-fixtures"* ]]
  run hook_files sensor-contract
  [[ "$output" == *"check-sensor-contract"* ]]
  run hook_files vacuous-tests-sweep
  [[ "$output" == *"check-vacuous-tests"* ]]
}

@test "the per-file hook and the sweep are separate entries, because the shape differs" {
  # Widening the per-file pattern instead made pre-commit hand the checker its
  # own script path — correctly answered "that is not a test file", UNKNOWN,
  # exit 2, on every commit touching it. A guard's own change needs a different
  # CALL, not a wider filter.
  run grep -c "id: vacuous-tests" "$CFG"
  [ "$output" -ge 2 ]
  run python3 -c "
import re
src = open('$CFG').read()
m = re.search(r'- id: vacuous-tests-sweep.*?(?=\n      - id: |\Z)', src, re.S)
print('pass_filenames: false' in m.group(0))
"
  [[ "$output" == "True" ]]
}

@test "the per-file pattern still matches the script's own selector" {
  # Two copies of one rule; a test is the only thing keeping them equal.
  run python3 -c "
import re
cfg = open('$CFG').read()
m = re.search(r\"- id: vacuous-tests\n.*?files: '(.*?)'\", cfg, re.S)
hook = m.group(1).replace('\\\\\\\\', '\\\\')
src = open('${BATS_TEST_DIRNAME}/../scripts/check-vacuous-tests').read()
s = re.search(r'TEST_FILE = re\.compile\(\s*r\"(.*?)\"', src, re.S).group(1)
print(hook == s, hook, s, sep='\n')
"
  [[ "${lines[0]}" == "True" ]]
}

# ── the commit gate names what it does not run ──────────────────────────────
#
# The suite reached 259s and this repo's own rules say a four-minute gate gets
# bypassed with --no-verify — worse than no gate, because you still believe it ran.
# blind_spots.bats is 113s of that and measures the verifier's coverage rather than
# guarding a commit, so it moved to `make test`. The danger of that move is the
# defect fixed one cycle earlier: a check that stops being run by anything.

@test "the commit gate excludes the blind-spot corpus and says so in its name" {
  C="$BATS_TEST_DIRNAME/../.pre-commit-config.yaml"
  run grep -A3 "id: bats-tests" "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"blind_spots"* ]]        # the exclusion is there
  [[ "$output" == *"except"* ]]             # and the NAME admits it
}

@test "make test still runs the corpus the gate skips" {
  # Moving an expensive check out of pre-commit is only legitimate if something
  # else runs it. Otherwise it is deletion with extra steps.
  M="$BATS_TEST_DIRNAME/../Makefile"
  run grep -A2 "^test:" "$M"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bats tests/"* ]]        # unfiltered — the whole directory
  [[ "$output" != *"grep -v blind_spots"* ]]
}
