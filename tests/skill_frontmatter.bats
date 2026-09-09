#!/usr/bin/env bats
# check_skills.py — the validator guarding 46 skills, which had zero tests.
#
# The sensors have 395 tests. The two checks that guard what this repository is
# actually for had none, so nobody had seen either produce a red: the instrument was
# correct today and nothing would notice if it stopped being. That is precisely the
# state check-vacuous-tests exists to prevent, one level up.
#
# It was also unexercisable. Anchored to its own repo — right for a repo-only check —
# a test had to plant a broken skill in the real skills/ directory and remove it, and
# one that failed midway would leave it behind. The seam (SOLO_SKILLS_DIR) is the fix,
# because a test must not be able to damage the thing it tests.

C="${BATS_TEST_DIRNAME}/../scripts/check_skills.py"

good_skill() {  # $1 = dir, $2 = skill name
  mkdir -p "$1/$2"
  { printf -- "---\n"
    printf "name: solo-%s\n" "$2"
    printf "description: A description long enough to trigger reliably on the words a user would actually say when they want this.\n"
    printf -- "metadata:\n  version: 1.0.0\n---\nBody.\n"; } > "$1/$2/SKILL.md"
}

setup() {
  T="$BATS_TEST_TMPDIR/skills"; mkdir -p "$T"
}

@test "a well-formed skill passes" {
  # Positive control first: a validator that rejects everything makes every test
  # below pass while blocking every commit.
  good_skill "$T" research
  run env SOLO_SKILLS_DIR="$T" python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"frontmatter valid"* ]]
}

@test "a name that does not match its directory is caught" {
  # The hook's own title claims this check. It is enforced, and now demonstrated.
  good_skill "$T" research
  mkdir -p "$T/plan"
  printf -- "---\nname: solo-something-else\ndescription: A description long enough to trigger reliably on real user words here.\nmetadata:\n  version: 1.0.0\n---\nB.\n" > "$T/plan/SKILL.md"
  run env SOLO_SKILLS_DIR="$T" python3 "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan"* ]]
  [[ "$output" == *"solo-plan"* ]]
}

@test "a missing description is caught" {
  good_skill "$T" research
  mkdir -p "$T/thin"
  printf -- "---\nname: solo-thin\nmetadata:\n  version: 1.0.0\n---\nB.\n" > "$T/thin/SKILL.md"
  run env SOLO_SKILLS_DIR="$T" python3 "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no \`description\`"* ]]
}

@test "a missing version is caught, because it blocks publishing" {
  good_skill "$T" research
  mkdir -p "$T/unversioned"
  printf -- "---\nname: solo-unversioned\ndescription: A description long enough to trigger reliably on the words a user says.\n---\nB.\n" > "$T/unversioned/SKILL.md"
  run env SOLO_SKILLS_DIR="$T" python3 "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"version"* ]]
}

@test "the count in the summary is the number of skills examined" {
  # A validator that reports on a different set from the one it was given is the
  # defect this repo has recorded four times; here the number is checkable.
  good_skill "$T" one
  good_skill "$T" two
  good_skill "$T" three
  run env SOLO_SKILLS_DIR="$T" python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 skills"* ]]
}

@test "an empty skills directory is not reported as everything being fine" {
  # Zero skills and a wrong path produce the same "no problems". The summary has to
  # carry the count, or a mistyped SOLO_SKILLS_DIR reads as a clean bill.
  run env SOLO_SKILLS_DIR="$T" python3 "$C"
  [[ "$output" == *"0 skills"* ]]
}

# ── every skill carries the block that makes it publishable ──────────────────
#
# Measured 2026-09-09: 2 of 46 skills had no `openclaw:` block, so neither could be
# published to ClawHub. They are the same two a test accidentally rewrote and had
# reverted one cycle earlier — the revert put them back to the state BEFORE the
# metadata was ever added, and nothing has noticed since, because nothing looked.
#
# Found by running add-openclaw-meta.py against a COPY of the real skills to check
# its idempotence claim. Idempotence held; the run also reported "2 modified", which
# is the finding. Verifying one claim measured something nobody had asked about.

@test "every skill in this repository carries an openclaw block" {
  cd "$BATS_TEST_DIRNAME/.."
  total=0
  missing=""
  for f in skills/*/SKILL.md; do
    total=$((total + 1))
    grep -q "openclaw:" "$f" || missing="$missing $(basename "$(dirname "$f")")"
  done
  # A loop over an empty list asserts nothing, and a wrong glob is silent.
  [ "$total" -ge 40 ]
  [ -z "$missing" ] || { echo "no openclaw block:$missing"; false; }
}

@test "add-openclaw-meta is idempotent, checked by running it twice" {
  # It REWRITES every SKILL.md in place; a non-idempotent run corrupts all of them
  # at once. The claim had been in a comment since the seam was added and verified
  # by nobody.
  D="$BATS_TEST_TMPDIR/oc"
  mkdir -p "$D/plain" "$D/already"
  printf -- '---\nname: solo-plain\ndescription: x\n---\n\n# Plain\n' > "$D/plain/SKILL.md"
  printf -- '---\nname: solo-already\ndescription: x\nmetadata:\n  openclaw:\n    emoji: "X"\n---\n\n# A\n' > "$D/already/SKILL.md"
  A=$(cat "$D"/*/SKILL.md | shasum -a256)
  run env SOLO_SKILLS_DIR="$D" python3 "$BATS_TEST_DIRNAME/../scripts/add-openclaw-meta.py"
  [ "$status" -eq 0 ]
  B=$(cat "$D"/*/SKILL.md | shasum -a256)
  # The first run must actually change something, or "idempotent" is being satisfied
  # by a tool that does nothing at all.
  [ "$A" != "$B" ]
  run env SOLO_SKILLS_DIR="$D" python3 "$BATS_TEST_DIRNAME/../scripts/add-openclaw-meta.py"
  [ "$status" -eq 0 ]
  C=$(cat "$D"/*/SKILL.md | shasum -a256)
  [ "$B" = "$C" ]
  [[ "$output" == *"0 modified"* ]]
}
