#!/usr/bin/env bats
# check-rules-budget — what the always-loaded rules cost.
#
# rules/*.md is read into context at the start of every session in every project,
# and nothing here had ever measured it — in a repository whose subject is measuring
# things. The file arguing that a green light must state its cost had become the
# largest cost in the harness, growing a few thousand bytes per cycle because every
# cycle appends its finding to it.

C="${BATS_TEST_DIRNAME}/../scripts/check-rules-budget"

setup() {
  R="$BATS_TEST_TMPDIR/repo"; mkdir -p "$R/rules"
}

@test "it reports the total, the share per file, and the token estimate" {
  printf 'x%.0s' $(seq 1 4000) > "$R/rules/big.md"
  printf 'y%.0s' $(seq 1 100)  > "$R/rules/small.md"
  run python3 "$C" "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"big.md"* ]]
  [[ "$output" == *"4,100 bytes across 2 file(s)"* ]]
  [[ "$output" == *"tokens at 4 bytes/token"* ]]   # the conversion is stated
  [[ "$output" == *"headroom"* ]]
}

@test "over budget is exit 1 and names it as a decision, not a failure" {
  python3 -c "
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text('x' * 200_000)
" "$R/rules/huge.md"
  run python3 "$C" "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"OVER BUDGET"* ]]
  [[ "$output" == *"a decision that has not been made"* ]]
}

@test "an absent rules directory is UNKNOWN, not a payload of zero" {
  run python3 "$C" "$BATS_TEST_TMPDIR/no-such-repo"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"not the same as a payload of zero"* ]]
}

@test "an empty rules directory is UNKNOWN too" {
  # Zero files and a bad path produce the same total. This cannot tell them apart
  # and says so rather than reporting 0 bytes as a clean result.
  run python3 "$C" "$R"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"cannot tell them apart"* ]]
}

@test "this repository's own payload is measured and named" {
  # The number that motivated the script, asserted where a reader will see it.
  run python3 "$C" "$BATS_TEST_DIRNAME/.."
  [ -n "$output" ]
  [[ "$output" == *"harness-sensors.md"* ]]
  [[ "$output" == *"EVERY session in EVERY project"* ]]
}
