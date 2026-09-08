#!/usr/bin/env bats
# add-openclaw-meta.py — the only one of these tools that WRITES.
#
# Four scripts this week could not be exercised without mutating what they produce.
# The other three report; this one rewrites every SKILL.md in place, so its
# idempotence claim — "skips skills that already have openclaw metadata" — was the
# one nobody could afford to test and nobody had. A non-idempotent run would have
# corrupted 46 files at once.

A="${BATS_TEST_DIRNAME}/../scripts/add-openclaw-meta.py"

setup() {
  T="$BATS_TEST_TMPDIR/skills"; mkdir -p "$T"
}

skill() {  # $1 = dir name, $2... = file body via stdin
  mkdir -p "$T/$1"
  cat > "$T/$1/SKILL.md"
}

@test "it adds the metadata block once" {
  skill research <<'EOF'
---
name: solo-research
description: Deep research. Use when user says "research this market".
---
Body.
EOF
  # SOLO_SKILLS_DIR on EVERY invocation. The first draft of this test opened with a
  # bare `run python3 "$A"` — and that run rewrote two real skills, knowledge and
  # sgr, in the repository. The test written to show that a writing tool needs a seam
  # used the tool without it.
  run env SOLO_SKILLS_DIR="$T" python3 "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 modified"* ]]
  run grep -c "openclaw" "$T/research/SKILL.md"
  [ "$output" -ge 1 ]
}

@test "running it twice changes nothing — the claim, checked" {
  skill research <<'EOF'
---
name: solo-research
description: Deep research. Use when user says "research this market".
---
Body.
EOF
  env SOLO_SKILLS_DIR="$T" python3 "$A" >/dev/null 2>&1
  first=$(shasum -a 256 "$T/research/SKILL.md" | cut -d' ' -f1)
  run env SOLO_SKILLS_DIR="$T" python3 "$A"
  [[ "$output" == *"0 modified"* ]]
  [[ "$output" == *"1 skipped"* ]]
  second=$(shasum -a 256 "$T/research/SKILL.md" | cut -d' ' -f1)
  [ -n "$first" ]
  [ "$first" = "$second" ]
}

@test "a file with no frontmatter is left exactly as it was" {
  skill prose <<'EOF'
No frontmatter at all, just prose.
EOF
  before=$(shasum -a 256 "$T/prose/SKILL.md" | cut -d' ' -f1)
  run env SOLO_SKILLS_DIR="$T" python3 "$A"
  after=$(shasum -a 256 "$T/prose/SKILL.md" | cut -d' ' -f1)
  [ "$before" = "$after" ]
}

@test "an empty file is left exactly as it was" {
  mkdir -p "$T/blank"; : > "$T/blank/SKILL.md"
  before=$(shasum -a 256 "$T/blank/SKILL.md" | cut -d' ' -f1)
  run env SOLO_SKILLS_DIR="$T" python3 "$A"
  after=$(shasum -a 256 "$T/blank/SKILL.md" | cut -d' ' -f1)
  [ "$before" = "$after" ]
}

@test "a horizontal rule in the body survives the rewrite" {
  # split("---", 2) is what parses the frontmatter, and a body containing its own
  # `---` is the input that would break a naive split. The body must come through
  # whole, not truncated at the first rule.
  skill dashes <<'EOF'
---
name: solo-dashes
description: A skill. Use when user says "do it".
---
Body with a rule:

---

And more after it.
EOF
  run env SOLO_SKILLS_DIR="$T" python3 "$A"
  [[ "$output" == *"1 modified"* ]]
  run grep -c "And more after it" "$T/dashes/SKILL.md"
  [ "$output" -eq 1 ]
  run grep -c "openclaw" "$T/dashes/SKILL.md"
  [ "$output" -ge 1 ]
}

@test "no test in this file invokes the writer without the seam" {
  # Mechanical, because noticing it was luck: the first draft's bare invocation was
  # caught by `git status` after the fact, not by anything that would catch it next
  # time. Every call must carry SOLO_SKILLS_DIR, or it writes into the repository.
  run grep -cE '^\s*run .*python3 "\$A"' "$BATS_TEST_FILENAME"
  total="$output"
  [ "$total" -ge 5 ]                     # a count of zero would pass vacuously
  run grep -cE '^\s*run env SOLO_SKILLS_DIR="\$T" python3 "\$A"' "$BATS_TEST_FILENAME"
  seamed="$output"
  [ "$seamed" -eq "$total" ]
}
