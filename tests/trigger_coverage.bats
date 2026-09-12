#!/usr/bin/env bats
# validate_triggers.py — the sibling that still had zero tests.
#
# Its summary said "PASS — 48/48 tests passed" over a repository of 46 skills where
# 13 contributed no test case at all and 30 more asserted nothing positive. Three of
# forty-six had a green that meant "this triggers on something a user might say".
#
# The extractor reads exactly one form — `Use when user says "…"` — so a description
# written any other way yields nothing, and yielded it in silence.

V="${BATS_TEST_DIRNAME}/../scripts/validate_triggers.py"

setup() {
  T="$BATS_TEST_TMPDIR/skills"; mkdir -p "$T"
}

with_triggers() {  # $1 = name
  mkdir -p "$T/$1"
  printf -- '---\nname: solo-%s\ndescription: Use when user says "diagnose a flaky test", "debug a failing build".\n---\nB.\n' "$1" > "$T/$1/SKILL.md"
}

no_triggers() {  # $1 = name
  mkdir -p "$T/$1"
  printf -- '---\nname: solo-%s\ndescription: A description written in prose, with no quoted trigger phrases.\n---\nB.\n' "$1" > "$T/$1/SKILL.md"
}

@test "a skill with extractable triggers passes and is listed" {
  # Positive control: green must be reachable, or every assertion below is about a
  # tool that only ever fails.
  with_triggers diagnose
  run env SOLO_SKILLS_DIR="$T" python3 "$V"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    diagnose"* ]]
  [[ "$output" == *"PASS"* ]]
}

@test "a skill with no extractable case is named, not silently dropped" {
  # It was `continue`d with its SKIP line behind --verbose: 46 skills on disk, 33 in
  # the report, 13 invisible while the summary said PASS.
  with_triggers diagnose
  no_triggers quiet
  run env SOLO_SKILLS_DIR="$T" python3 "$V"
  [[ "$output" == *"NO TEST CASE AT ALL"* ]]
  [[ "$output" == *"quiet"* ]]
  # The message must say what is missing, and the extractor reads two spellings
  # now (`Use when user says "…"` and `Use when "…"`), so pinning the sentence to
  # one of them is how this test went red when the second was accepted.
  [[ "$output" == *"quoted phrase after"* ]]
  [[ "$output" == *"Use when"* ]]
}

@test "a repository where every skill is silent still says so loudly" {
  # The degenerate case: nothing to test, and a summary that would otherwise read
  # as a clean bill over an empty set.
  no_triggers one
  no_triggers two
  run env SOLO_SKILLS_DIR="$T" python3 "$V"
  [[ "$output" == *"2 skill(s) contributed NO TEST CASE"* ]]
  [[ "$output" == *"one, two"* ]]
}

@test "a fully covered repository says nothing about gaps" {
  # The other positive control: the two new lines must be absent when there is
  # nothing to report, or they become noise on every run and get ignored.
  with_triggers diagnose
  with_triggers grill
  run env SOLO_SKILLS_DIR="$T" python3 "$V"
  [ "$status" -eq 0 ]
  [[ "$output" != *"NO TEST CASE AT ALL"* ]]
  [[ "$output" != *"NOTHING POSITIVE"* ]]
}

negative_only() {  # $1 = name — a description with "Do NOT use for", no quoted triggers
  mkdir -p "$T/$1"
  printf -- '---\nname: solo-%s\ndescription: Prose with no quoted trigger phrases. Do NOT use for writing poetry.\n---\nB.\n' "$1" > "$T/$1/SKILL.md"
}

@test "a skill asserting only a negative is named as asserting nothing positive" {
  # The state 30 of 46 skills are in: a green that means "does not trigger on an
  # invented phrase" and nothing about triggering on what a user would say. An empty
  # description would pass identically. Written after a mutation showed this branch
  # killed 0 tests — a guard nobody had seen fire.
  with_triggers diagnose
  negative_only halfway
  run env SOLO_SKILLS_DIR="$T" python3 "$V"
  [[ "$output" == *"NOTHING POSITIVE"* ]]
  [[ "$output" == *"halfway"* ]]
  [[ "$output" != *"NO TEST CASE AT ALL"* ]]   # it did contribute one, just not a positive one
}

@test "a real failure is still a failure" {
  # The tool's actual job, pinned: a description whose triggers do not match its own
  # should_trigger example must fail, or the gap-reporting would be decoration on a
  # check that never checks.
  mkdir -p "$T/broken/tests"
  printf -- '---\nname: solo-broken\ndescription: Use when user says "something entirely unrelated".\n---\nB.\n' > "$T/broken/SKILL.md"
  printf 'should_trigger:\n  - "diagnose a flaky test"\n' > "$T/broken/tests/triggers.yaml"
  run env SOLO_SKILLS_DIR="$T" python3 "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"should trigger"* ]]
}
