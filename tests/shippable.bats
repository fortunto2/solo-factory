#!/usr/bin/env bats
# check-shippable — committed and shipped are different things.
#
# This plugin is distributed by version string: Claude Code offers no update when
# the declared version matches the installed one. So a repo can accumulate weeks
# of pushed commits no user will ever receive, and every one looks delivered.
# Measured the first time it ran here: 39 unreleased user-facing commits, and the
# previous declared version had never been installed either.
#
# These tests build their own repository. The first draft ran against THIS one
# and branched on the answer — "if it says nothing owed then expect 0, else
# expect 1" — which accepts both outcomes and can never fail. The mutation that
# made every path non-user-facing killed 0 of 4. A test that adapts to the answer
# is the defect this repo ships a checker for, in a shape that checker cannot see
# because the assertions are positive.

C="${BATS_TEST_DIRNAME}/../scripts/check-shippable"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
        GIT_COMMON_DIR GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX \
        GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/.claude-plugin" "$R/skills" "$R/scripts"
  cp "$C" "$R/scripts/check-shippable"
  git -C "$R" init -q .
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name t
  printf '{\n  "name": "t",\n  "version": "1.0.0"\n}\n' > "$R/.claude-plugin/plugin.json"
  git -C "$R" add -A && git -C "$R" commit -q -m "release 1.0.0"
}

commit_file() {  # path, message
  mkdir -p "$(dirname "$R/$1")"
  printf 'x\n' >> "$R/$1"
  git -C "$R" add -A && git -C "$R" commit -q -m "$2"
}

@test "a fresh release owes nothing" {
  run python3 "$R/scripts/check-shippable"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing owed"* ]]
  [[ "$output" == *"1.0.0"* ]]
}

@test "a user-facing commit after the release is exit 1 and is named" {
  commit_file skills/thing/SKILL.md "feat: a skill users receive"
  run python3 "$R/scripts/check-shippable"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(1 user-facing)"* ]]
  [[ "$output" == *"a skill users receive"* ]]
  [[ "$output" == *"plugin-publish"* ]]
  [[ "$output" != *"nothing owed"* ]]
}

@test "a repo-only commit owes nothing, and is still counted as a commit" {
  commit_file README.md "docs: notes to ourselves"
  commit_file .github/workflows/ci.yml "ci: tweak"
  run python3 "$R/scripts/check-shippable"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(0 user-facing)"* ]]
  [[ "$output" == *"nothing owed"* ]]
  # The commits happened; only the obligation is absent.
  [[ "$output" == *"commits since it : 2"* ]]
}

@test "bumping the version clears the debt" {
  commit_file skills/thing/SKILL.md "feat: a skill"
  run python3 "$R/scripts/check-shippable"
  [ "$status" -eq 1 ]
  printf '{\n  "name": "t",\n  "version": "1.1.0"\n}\n' > "$R/.claude-plugin/plugin.json"
  git -C "$R" add -A && git -C "$R" commit -q -m "release 1.1.0"
  run python3 "$R/scripts/check-shippable"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.1.0"* ]]
  [[ "$output" == *"nothing owed"* ]]
}

@test "a mixed commit counts as user-facing" {
  # One file anyone receives is enough; a release is owed for the whole commit.
  mkdir -p "$R/skills/m"
  printf 'x\n' > "$R/README.md"
  printf 'y\n' > "$R/skills/m/SKILL.md"
  git -C "$R" add -A && git -C "$R" commit -q -m "chore: notes and a skill"
  run python3 "$R/scripts/check-shippable"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(1 user-facing)"* ]]
}

@test "an unreadable manifest is UNKNOWN and exit 2, never a pass" {
  rm "$R/.claude-plugin/plugin.json"
  run python3 "$R/scripts/check-shippable"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a pass"* ]]
  [[ "$output" != *"nothing owed"* ]]
}
