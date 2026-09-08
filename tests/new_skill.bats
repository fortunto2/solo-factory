#!/usr/bin/env bats
# new-skill.sh — and the agreement between the generator and the validators.
#
# Three of 46 skills carry positive trigger cases, and they are exactly the three
# whose descriptions use `Use when user says "…"`. That form lives in this generator
# and in the validator's regex — and, until this cycle, nowhere an agent
# hand-authoring a skill would read. So the generator and the checks agreed, and the
# agreement was verified by nobody.
#
# It was also unverifiable: SKILL_DIR was $REPO/skills/$NAME with no seam, so a probe
# passing SKILLS_ROOT was ignored and a scratch skill appeared in the repository.
# Third tool this week that could not be exercised without mutating what it produces.

N="${BATS_TEST_DIRNAME}/../scripts/new-skill.sh"
V="${BATS_TEST_DIRNAME}/../scripts/validate_triggers.py"
C="${BATS_TEST_DIRNAME}/../scripts/check_skills.py"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  T="$BATS_TEST_TMPDIR/skills"; mkdir -p "$T"
}

@test "the generator writes where it is told, not into the repository" {
  run env SOLO_SKILLS_DIR="$T" bash "$N" probe-one
  [ -f "$T/probe-one/SKILL.md" ]
  [ ! -e "$BATS_TEST_DIRNAME/../skills/probe-one" ]
}

@test "what the generator produces passes the frontmatter validator" {
  env SOLO_SKILLS_DIR="$T" bash "$N" probe-two >/dev/null 2>&1
  run env SOLO_SKILLS_DIR="$T" python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"frontmatter valid"* ]]
}

@test "what the generator produces yields POSITIVE trigger cases" {
  # The guarantee that matters: 43 of 46 existing skills yield none, and this is why
  # the generated ones do. If the template's wording drifts from the extractor's one
  # accepted form, every new skill silently joins the thirty that assert nothing.
  env SOLO_SKILLS_DIR="$T" bash "$N" probe-three >/dev/null 2>&1
  run env SOLO_SKILLS_DIR="$T" python3 "$V"
  [ "$status" -eq 0 ]
  [[ "$output" == *"probe-three"* ]]
  [[ "$output" != *"0+ /"* ]]                  # it asserts something positive
  [[ "$output" != *"NOTHING POSITIVE"* ]]
  [[ "$output" != *"NO TEST CASE AT ALL"* ]]
}

@test "the template still carries the one form the extractor reads" {
  # Pinned literally, because the coupling is invisible: the generator's prose and
  # the validator's regex have to agree and nothing else connects them.
  run grep -c 'Use when user says' "$N"
  [ "$output" -ge 1 ]
}
