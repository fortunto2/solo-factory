#!/usr/bin/env bats
# check-agents — the artifacts that had no validator at all.
#
# Skills have two. The three agents had none, and their contract is just as real: an
# agent is model-invoked by its description and addressed by a name that must match
# its filename. Both fail SILENTLY — the agent simply never triggers.
#
# The audit that produced this found nothing wrong: all three agents are valid today.
# What was missing is not a fix, it is the thing that would notice a future break.

C="${BATS_TEST_DIRNAME}/../scripts/check-agents"

setup() {
  A="$BATS_TEST_TMPDIR/agents"; mkdir -p "$A"
}

agent() {  # $1 = filename stem, $2 = name field
  printf -- "---\nname: %s\ndescription: A description long enough to say when the model should choose this agent over the others.\ntools: Read, Grep\nmodel: sonnet\n---\nBody.\n" "$2" > "$A/$1.md"
}

@test "a well-formed agent passes, and the summary names its scope" {
  # Positive control, and the scope claim: this checks agents/ and says so, after a
  # sibling check printed a count that read as repo-wide.
  agent researcher researcher
  run env SOLO_AGENTS_DIR="$A" python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 agents"* ]]
  [[ "$output" == *"only"* ]]
}

@test "a name that does not match the filename is caught" {
  agent researcher wrong-name
  run env SOLO_AGENTS_DIR="$A" python3 "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match the filename"* ]]
  [[ "$output" == *"invoked as \`researcher\`"* ]]
}

@test "a missing description is caught, with why it matters" {
  printf -- "---\nname: quiet\ntools: Read\nmodel: sonnet\n---\nB.\n" > "$A/quiet.md"
  run env SOLO_AGENTS_DIR="$A" python3 "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"never triggers"* ]]
}

@test "a description too short to describe when to trigger is caught" {
  printf -- "---\nname: terse\ndescription: Does things.\ntools: Read\nmodel: sonnet\n---\nB.\n" > "$A/terse.md"
  run env SOLO_AGENTS_DIR="$A" python3 "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"too short"* ]]
}

@test "a file with no frontmatter at all is caught" {
  printf 'Just prose, no frontmatter.\n' > "$A/prose.md"
  run env SOLO_AGENTS_DIR="$A" python3 "$C"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no YAML frontmatter"* ]]
}

@test "an empty agents directory is UNKNOWN, not a clean bill" {
  # Zero agents and a mistyped path produce the same absence of problems.
  run env SOLO_AGENTS_DIR="$A" python3 "$C"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"indistinguishable"* ]]
}

@test "an absent directory is UNKNOWN too, and says nothing was checked" {
  run env SOLO_AGENTS_DIR="$BATS_TEST_TMPDIR/no-such" python3 "$C"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not the same as nothing being wrong"* ]]
}

@test "this repository's own agents pass" {
  # The measurement that motivated the script, pinned where a reader sees it.
  run python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents — frontmatter valid"* ]]
}
