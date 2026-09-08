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
  # The check measures the LOADED directory when one exists, and that is machine
  # global (~/.claude/rules), not per-repository. Without this, every test below
  # measured the real machine instead of its own fixture — which is how six of them
  # started failing the moment the check learned to look at what actually loads.
  export HOME="$BATS_TEST_TMPDIR/nohome"
  mkdir -p "$HOME"
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

@test "the case log is not in the loaded rules directory" {
  # It was 55,904 bytes — 42% of the always-loaded payload and the only part that
  # grew every cycle, so leaving it there meant every future entry raised the
  # standing cost of every session in every project.
  R2="$BATS_TEST_DIRNAME/.."
  [ -f "$R2/docs/harness-case-log.md" ]
  [ ! -f "$R2/rules/harness-case-log.md" ]
  run grep -c "^\*\*" "$R2/docs/harness-case-log.md"
  [ "$output" -gt 40 ]                       # the entries really moved, not vanished
}

@test "the loaded rules point at the log rather than dropping it" {
  # Moving an archive out of context is only honest if what stays says where it went.
  R2="$BATS_TEST_DIRNAME/.."
  # The whole file, not a -A6 window. The first version picked six lines of context
  # and the sentence it was looking for sat on the eighth — a convenient slice
  # failing a test about content that was actually there.
  run cat "$R2/rules/harness-sensors.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"case log lives"* ]]
  [[ "$output" == *"docs/harness-case-log.md"* ]]
  [[ "$output" == *"append new entries"* ]]
}

@test "the loaded payload is well under budget after the move" {
  # The number that motivated it, asserted so a future cycle that quietly moves the
  # log back has to fail a test rather than just raise a threshold.
  run python3 "$C" "$BATS_TEST_DIRNAME/.."
  [ "$status" -eq 0 ]
  python3 -c "
import re, sys
m = re.search(r'([\d,]+) bytes across', sys.argv[1])
assert m, sys.argv[1][:200]
total = int(m.group(1).replace(',', ''))
assert total < 100_000, total
print('OK', total)
" "$output"
}

# ── the hop this check stopped one short of ─────────────────────────────────
#
# It measured rules/ in the repository. A session loads ~/.claude/rules/, which here
# is five symlinks plus a real file that is not in the repository at all — 908 bytes
# loaded into every session and counted by nothing. Same shape as the shippable
# check one cycle earlier: measuring the source while the reader reads the
# destination.

@test "it measures the loaded directory when one exists" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/rules" "$R/rules"
  printf 'in the repo only\n' > "$R/rules/repo.md"
  printf 'loaded only, not in any repo\n' > "$HOME/.claude/rules/local.md"
  run python3 "$C" "$R"
  [ -n "$output" ]
  [[ "$output" == *"measuring: $HOME/.claude/rules"* ]]
  [[ "$output" == *"local.md"* ]]
}

@test "a file loaded but absent from the repository is named" {
  export HOME="$BATS_TEST_TMPDIR/h2"
  mkdir -p "$HOME/.claude/rules" "$R/rules"
  printf 'x\n' > "$R/rules/shared.md"
  printf 'x\n' > "$HOME/.claude/rules/shared.md"
  printf 'y\n' > "$HOME/.claude/rules/stray.md"
  run python3 "$C" "$R"
  [[ "$output" == *"loaded but NOT in this repository: stray.md"* ]]
  [[ "$output" != *"in this repository but NOT loaded"* ]]
}

@test "a repository file that no session loads is named too" {
  # The reverse, and the worse one: written for a reader that never sees it.
  export HOME="$BATS_TEST_TMPDIR/h3"
  mkdir -p "$HOME/.claude/rules" "$R/rules"
  printf 'x\n' > "$HOME/.claude/rules/shared.md"
  printf 'x\n' > "$R/rules/shared.md"
  printf 'z\n' > "$R/rules/orphan.md"
  run python3 "$C" "$R"
  [[ "$output" == *"in this repository but NOT loaded: orphan.md"* ]]
}

@test "with no loaded directory it says the number is about the source" {
  # A machine with no ~/.claude/rules — CI, a fresh checkout — must not present the
  # repository's bytes as what a session loads.
  export HOME="$BATS_TEST_TMPDIR/h4"
  mkdir -p "$HOME" "$R/rules"
  printf 'x\n' > "$R/rules/a.md"
  run python3 "$C" "$R"
  [[ "$output" == *"does not exist here"* ]]
  [[ "$output" == *"not what any session loads"* ]]
}
