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

@test "the largest sections are named, with their line counts" {
  # 911 lines had accumulated under a heading about one paragraph, and 516 under
  # another, because every cycle appended before the same anchor. A section whose
  # heading stopped describing it is a table of contents that lies, and headings are
  # the only navigation a 2,000-line file has.
  { printf '# Doc\n\n## Small\n\nx\n\n## Huge\n\n'; printf 'line\n%.0s' $(seq 1 400); } > "$R/rules/a.md"
  run python3 "$C" "$R"
  [ -n "$output" ]
  [[ "$output" == *"largest sections"* ]]
  [[ "$output" == *"Huge"* ]]
  [[ "$output" == *"a.md"* ]]
}

@test "a file with no headings contributes no sections and does not crash" {
  printf 'just prose, no headings at all\n' > "$R/rules/flat.md"
  printf '# Doc\n\n## One\n\nx\n' > "$R/rules/b.md"
  run python3 "$C" "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"One"* ]]
  [[ "$output" != *"flat.md —"* ]]
}

@test "the section list is ordered largest first" {
  { printf '# D\n\n## Tiny\n\nx\n\n## Middle\n\n'; printf 'm\n%.0s' $(seq 1 50)
    printf '\n## Biggest\n\n'; printf 'b\n%.0s' $(seq 1 300); } > "$R/rules/c.md"
  run python3 "$C" "$R"
  python3 -c "
import re, sys
lines = [l for l in sys.argv[1].splitlines() if 'lines  ' in l]
assert lines, 'no section lines printed'
counts = [int(re.search(r'(\d+) lines', l).group(1)) for l in lines]
assert counts == sorted(counts, reverse=True), counts
assert 'Biggest' in lines[0], lines[0]
print('OK', counts)
" "$output"
}
