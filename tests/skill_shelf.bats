#!/usr/bin/env bats
# `shelf` — the skill archive: usage from transcripts, shelve, list, restore.
#
# Every skill in ~/.claude/skills costs its description in every session, so the
# archive exists to make "not loaded" cheap to undo. The tests pin the two ways it
# could lie: a usage count of zero that came from reading nothing, and a restore
# that puts a skill somewhere other than where it was taken from.

setup() {
  SHELF="$BATS_TEST_DIRNAME/../skills/skill-shelf/scripts/shelf.py"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  export SKILL_SHELF_DIR="$BATS_TEST_TMPDIR/archive"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$CLAUDE_CONFIG_DIR/projects/p1"
  for s in used-one never-used; do
    mkdir -p "$CLAUDE_CONFIG_DIR/skills/$s"
    printf -- '---\nname: %s\ndescription: Does %s things.\n---\nbody\n' "$s" "$s" \
      > "$CLAUDE_CONFIG_DIR/skills/$s/SKILL.md"
  done
  T="$CLAUDE_CONFIG_DIR/projects/p1/s.jsonl"
  printf '%s\n' \
    '{"timestamp":"2026-10-20T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"used-one"}}]}}' \
    '{"timestamp":"2026-10-21T10:00:00Z","message":{"content":"<command-name>/used-one</command-name>"}}' \
    '{"timestamp":"2026-10-21T11:00:00Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"solo:solo-plan"}}]}}' \
    > "$T"
}

@test "stats counts Skill calls and slash commands, and names the unused" {
  run python3 "$SHELF" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"2  used-one"* ]]
  [[ "$output" == *"solo:plan"* ]]
  [[ "$output" == *"unused in ~/.claude/skills"*"never-used"* ]]
}

@test "stats over zero transcripts is UNKNOWN, never 'everything unused'" {
  rm -rf "$CLAUDE_CONFIG_DIR/projects/p1"
  run python3 "$SHELF" stats
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" != *"never-used"* ]]
}

@test "shelve moves the skill out and restore puts it back where it was" {
  run python3 "$SHELF" shelve never-used --reason "0 uses"
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_CONFIG_DIR/skills/never-used" ]
  [ -f "$SKILL_SHELF_DIR/never-used/SKILL.md" ]
  run python3 "$SHELF" restore never-used
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_CONFIG_DIR/skills/never-used/SKILL.md" ]
  [ ! -e "$SKILL_SHELF_DIR/never-used" ]
}

@test "shelve from a project dir restores into that project" {
  P="$BATS_TEST_TMPDIR/proj/.claude/skills"
  mkdir -p "$P/local-one"
  printf -- '---\nname: local-one\ndescription: x\n---\n' > "$P/local-one/SKILL.md"
  python3 "$SHELF" shelve local-one --from "$P"
  [ ! -e "$P/local-one" ]
  python3 "$SHELF" restore local-one
  [ -f "$P/local-one/SKILL.md" ]
}

@test "restore --to puts the skill in another project" {
  python3 "$SHELF" shelve never-used
  P="$BATS_TEST_TMPDIR/other/.claude/skills"
  run python3 "$SHELF" restore never-used --to "$P"
  [ "$status" -eq 0 ]
  [ -f "$P/never-used/SKILL.md" ]
}

@test "a symlinked skill is shelved as the link, its target untouched" {
  SRC="$BATS_TEST_TMPDIR/src/linked"
  mkdir -p "$SRC"
  printf -- '---\nname: linked\ndescription: x\n---\n' > "$SRC/SKILL.md"
  ln -s "$SRC" "$CLAUDE_CONFIG_DIR/skills/linked"
  python3 "$SHELF" shelve linked
  [ -L "$SKILL_SHELF_DIR/linked" ]
  [ -f "$SRC/SKILL.md" ]
}

@test "shelve refuses a missing skill and an occupied archive slot" {
  run python3 "$SHELF" shelve no-such-skill
  [ "$status" -eq 1 ]
  mkdir -p "$SKILL_SHELF_DIR/never-used"
  run python3 "$SHELF" shelve never-used
  [ "$status" -eq 1 ]
  [ -f "$CLAUDE_CONFIG_DIR/skills/never-used/SKILL.md" ]
}

@test "list shows archived skills with description, filtered by a query" {
  python3 "$SHELF" shelve never-used --reason "0 uses in 8 weeks"
  run python3 "$SHELF" list
  [[ "$output" == *"never-used"*"Does never-used things."* ]]
  run python3 "$SHELF" list zzz
  [[ "$output" != *"never-used"* ]]
}
