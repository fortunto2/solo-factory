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

@test "a long backlog says how many it did not print" {
  # Found by scripts/mutate, not by reading: the "... and N more" branch survived
  # both mutations, so nothing asserted that a truncated list says it truncated.
  # Silent truncation is the same class as a page cap that stays quiet.
  for i in $(seq 1 18); do commit_file "skills/s$i/SKILL.md" "feat: skill $i"; done
  run python3 "$R/scripts/check-shippable"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(18 user-facing)"* ]]
  [[ "$output" == *"and 3 more"* ]]
}

@test "a short backlog prints every commit and claims no remainder" {
  commit_file skills/one/SKILL.md "feat: only one"
  run python3 "$R/scripts/check-shippable"
  [[ "$output" == *"only one"* ]]
  [[ "$output" != *"more"* ]]
}

@test "a manifest with no history is UNKNOWN, not a clean bill" {
  # Also from mutate: the `if not last_bump` branch was never exercised. An
  # untracked manifest has no bump to compare against, and answering "nothing
  # owed" there would be the absent-baseline false green.
  rm -rf "$R/.git"
  git -C "$R" init -q .
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name t
  printf 'x\n' > "$R/README.md"
  git -C "$R" add README.md && git -C "$R" commit -q -m "first"
  run python3 "$R/scripts/check-shippable"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no history"* ]]
  [[ "$output" != *"nothing owed"* ]]
}

# ── the hop this check never looked at ─────────────────────────────────────
#
# It asked "is the manifest ahead of the code?" and called that shippable. It never
# asked "is what a user loads ahead of nothing?" — and that is where the gap lived:
# the manifest said 1.63.0 while the only directory in the plugin cache was 1.23.0,
# forty versions behind, with the check printing "nothing owed" throughout. The same
# gap was recorded once before at TWO versions; the fix then counted unreleased
# commits, which measures the manifest hop again.

iv() {  # installed_versions(name), against a fake HOME
  python3 -c "
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader('cs', '$C')
sp = importlib.util.spec_from_loader('cs', l)
m = importlib.util.module_from_spec(sp); sys.modules['cs'] = m; l.exec_module(m)
print(m.installed_versions('$1'))
"
}

@test "an installed version is found and reported" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/plugins/cache/solo/solo/1.23.0"
  run iv solo
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.23.0"* ]]
  [[ "$output" == *"None"* ]]        # nothing prevented the check
}

@test "no cache at all is UNCHECKED, not 'nothing installed'" {
  # A contributor who never installed the plugin and a machine where the cache was
  # wiped look identical from an empty list. The reason has to be carried.
  export HOME="$BATS_TEST_TMPDIR/bare"
  mkdir -p "$HOME"
  run iv solo
  [[ "$output" == *"no plugin cache on this machine"* ]]
}

@test "a cache without this plugin says which plugin was looked for" {
  export HOME="$BATS_TEST_TMPDIR/other"
  mkdir -p "$HOME/.claude/plugins/cache/elsewhere/somethingelse/2.0.0"
  run iv solo
  [[ "$output" == *"solo is not installed"* ]]
}

@test "the receipt says NOT <version> when the runtime is behind" {
  export HOME="$BATS_TEST_TMPDIR/behind"
  mkdir -p "$HOME/.claude/plugins/cache/solo/solo/1.23.0"
  run python3 "$C"
  [ -n "$output" ]
  [[ "$output" == *"installed"* ]]
  [[ "$output" == *"NOT "* ]]
  [[ "$output" == *"reaches no one"* ]]
}

@test "a matching installed version is reported without the warning" {
  # Positive control: a line that always warns passes the test above while telling
  # every up-to-date machine it is behind.
  export HOME="$BATS_TEST_TMPDIR/match"
  V=$(python3 -c "import json;print(json.load(open('$BATS_TEST_DIRNAME/../.claude-plugin/plugin.json'))['version'])")
  mkdir -p "$HOME/.claude/plugins/cache/solo/solo/$V"
  run python3 "$C"
  [[ "$output" == *"installed        : $V"* ]]
  [[ "$output" != *"NOT $V"* ]]
}
