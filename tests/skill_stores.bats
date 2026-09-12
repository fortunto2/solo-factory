#!/usr/bin/env bats
# Where a skill is allowed to live, and where a copy of it is a defect.
#
# Measured 2026-09-12: 28 solo skills were reachable twice — once through the
# plugin as solo:<name>, once through ~/.claude/skills as solo-<name>, the second
# route a six-month-old snapshot installed by `npx skills add`. All 28 files had
# drifted, and sessions had taken the stale route 7 times. `make doctor` printed
# "OK no duplicate skills" the whole time: it compared the repo's directory name
# (`plan`) against ~/.claude/skills/plan, while the duplicate is spelled
# `solo-plan` and lives in a store the check never looked at.

REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export SOLO_AGENT_SKILLS="$HOME/.agents/skills"
  export SOLO_PROJECT_SKILLS="$HOME/project/.claude/skills"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$SOLO_AGENT_SKILLS" "$SOLO_PROJECT_SKILLS"
  # Any real skill will do — hardcoding one would rot when it is renamed.
  SKILL="$(basename "$(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d | sort | head -1)")"
}

doctor() { bash "$REPO/scripts/doctor.sh" 2>&1; }

@test "a clean machine says what it checked, not just ok" {
  run doctor
  [[ "$output" == *"no duplicate skills"* ]]
  [[ "$output" == *"both spellings"* ]]
  [[ "$output" == *"point into the repo"* ]]
  [[ "$output" == *"adds no copy of a plugin skill"* ]]
  # The count is the part that makes the green readable: a check that scanned
  # nothing must not look like a check that found nothing.
  [[ "$output" =~ \([0-9]+\ skills,\ both\ spellings\) ]]
}

@test "a copy under the PUBLISHED name is caught — the shape that was invisible" {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/solo-$SKILL"
  echo "stale" > "$CLAUDE_CONFIG_DIR/skills/solo-$SKILL/SKILL.md"
  run doctor
  [[ "$output" == *"FAIL  reachable from BOTH"* ]]
  [[ "$output" == *"solo-$SKILL"* ]]
}

@test "a copy under the repo's own directory name is still caught" {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/$SKILL"
  run doctor
  [[ "$output" == *"FAIL  reachable from BOTH"* ]]
  [[ "$output" == *"$SKILL"* ]]
}

@test "a symlink into the repo is a duplicate too: one skill, two descriptions" {
  ln -s "$REPO/skills/$SKILL" "$CLAUDE_CONFIG_DIR/skills/solo-$SKILL"
  run doctor
  [[ "$output" == *"FAIL  reachable from BOTH"* ]]
  [[ "$output" == *"solo-$SKILL"* ]]
}

@test "the shared store accepts a symlink into the repo and refuses a copy" {
  ln -s "$REPO/skills/$SKILL" "$SOLO_AGENT_SKILLS/solo-$SKILL"
  run doctor
  [[ "$output" == *"point into the repo"* ]]

  rm "$SOLO_AGENT_SKILLS/solo-$SKILL"
  mkdir -p "$SOLO_AGENT_SKILLS/solo-$SKILL"
  echo "snapshot" > "$SOLO_AGENT_SKILLS/solo-$SKILL/SKILL.md"
  run doctor
  [[ "$output" == *"FAIL  stale solo skills"* ]]
  [[ "$output" == *"solo-$SKILL=copy"* ]]
}

@test "a symlink in the shared store pointing somewhere else is named as such" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/$SKILL"
  ln -s "$BATS_TEST_TMPDIR/elsewhere/$SKILL" "$SOLO_AGENT_SKILLS/solo-$SKILL"
  run doctor
  [[ "$output" == *"FAIL  stale solo skills"* ]]
  [[ "$output" == *"solo-$SKILL=points-outside-repo"* ]]
}

@test "an absent shared store is a stated skip, not silence" {
  export SOLO_AGENT_SKILLS="$BATS_TEST_TMPDIR/nowhere"
  run doctor
  [[ "$output" == *"no $BATS_TEST_TMPDIR/nowhere on this machine"* ]]
  [[ "$output" == *"no shared store to check"* ]]
}

@test "a project registering a plugin skill a second time is caught" {
  # <project>/.claude/skills is the third route. 27 links there served `build`
  # beside the plugin's `solo:build`: one skill, two descriptions, every session
  # opened in that tree paying for both.
  ln -s "$REPO/skills/$SKILL" "$SOLO_PROJECT_SKILLS/$SKILL"
  run doctor
  [[ "$output" == *"FAIL  plugin skills registered a second time"* ]]
  [[ "$output" == *"$SKILL"* ]]
}

@test "a project's own skill is left alone" {
  # Only names the plugin also serves are duplicates. A skill that exists solely
  # in the project is the normal case and must not be reported.
  mkdir -p "$SOLO_PROJECT_SKILLS/wiki-note"
  echo "local" > "$SOLO_PROJECT_SKILLS/wiki-note/SKILL.md"
  run doctor
  [[ "$output" == *"adds no copy of a plugin skill"* ]]
  [[ "$output" != *"FAIL  plugin skills registered a second time"* ]]
}
