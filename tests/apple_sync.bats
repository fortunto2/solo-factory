#!/usr/bin/env bats
# sync-apple-skills.sh — delete-then-copy left a hole for the length of a copy.
#
# Found 2026-09-09 by ENUMERATING every destructive call under scripts/ rather than
# by recalling which tools edit in place. The enumeration is the point: the belief
# being checked was "mutate and witness are the only in-place editors here", and it
# was wrong in a file nobody had connected to the question.
#
#     rm -rf "${DEST:?}/$name"      <- destination gone
#     mkdir -p "$DEST"
#     cp -R "$dir" "$DEST/$name"    <- ...for the whole duration of this
#
# A kill or a failed cp in that window destroys the skill with nothing to restore
# from. The ${DEST:?} guard covers an empty variable, not the window.

setup() {
  D="$BATS_TEST_TMPDIR/dest"; SRC="$BATS_TEST_TMPDIR/src"
  mkdir -p "$D/thing" "$SRC/thing"
  printf 'old content\n' > "$D/thing/SKILL.md"
  # Big enough that a recursive copy takes measurable time.
  for i in $(seq 1 400); do printf 'new content %d\n' "$i" > "$SRC/thing/f$i.md"; done
}

# The two orders, extracted so the difference is the only variable.
old_order() {
  rm -rf "${D:?}/thing"
  mkdir -p "$D"
  cp -R "$SRC/thing" "$D/thing"
}

new_order() {
  mkdir -p "$D"
  inc="$D/.incoming-thing.$$"; out="$D/.outgoing-thing.$$"
  rm -rf "$inc" "$out"
  cp -R "$SRC/thing" "$inc"
  [ -e "$D/thing" ] && mv "$D/thing" "$out"
  mv "$inc" "$D/thing"
  rm -rf "$out"
}

@test "the old order leaves the destination absent while copying" {
  # The control that makes the test below able to fail: without it, "the
  # destination always exists" could pass on a probe that never samples the window.
  old_order &
  bg=$!
  gone=0
  for _ in $(seq 1 200); do
    [ -e "$D/thing/SKILL.md" ] || [ -e "$D/thing" ] || gone=1
    kill -0 $bg 2>/dev/null || break
  done
  wait $bg 2>/dev/null || true
  [ "$gone" -eq 1 ]
}

@test "under the staged order, an absent destination always has its content beside it" {
  # The first version of this test asserted "never absent" and was FLAKY — 2 runs in
  # 4. The flake was the mechanism correcting the test: the staged order removes the
  # long window (a whole recursive copy) but not the short one between the two
  # `mv`s, and the file's own comment says POSIX has no atomic directory swap. I
  # wrote the caveat and then asserted its opposite.
  #
  # The real guarantee, and the one worth pinning: at any moment the destination is
  # either present, or its previous content is sitting under `.outgoing-`. Never a
  # hole with nothing to recover from.
  new_order &
  bg=$!
  violations=0
  samples=0
  for _ in $(seq 1 400); do
    samples=$((samples + 1))
    if [ ! -e "$D/thing" ]; then
      compgen -G "$D/.outgoing-thing.*" >/dev/null || violations=$((violations + 1))
    fi
    kill -0 $bg 2>/dev/null || break
  done
  wait $bg 2>/dev/null || true
  [ "$samples" -gt 1 ]          # a loop that ran once asserts almost nothing
  [ "$violations" -eq 0 ]
  # And it really did replace the content, or the invariant is satisfied by never
  # doing anything.
  [ -e "$D/thing/f1.md" ]
  [ ! -e "$D/thing/SKILL.md" ]
}

@test "a kill mid-copy leaves the old skill intact under the staged order" {
  new_order &
  bg=$!
  sleep 0.05
  kill -9 $bg 2>/dev/null || true
  wait $bg 2>/dev/null || true
  # Either the swap completed or it never started; either way something real is at
  # the destination, and nothing is a hole.
  [ -e "$D/thing" ]
  [ -n "$(ls -A "$D/thing")" ]
}

@test "the script itself uses the staged order, not delete-then-copy" {
  # The tests above exercise the shape. This pins it to the file, so the shape
  # cannot drift back while the tests keep passing on their local copies.
  run grep -n 'rm -rf "${DEST:?}/\$name"' "$BATS_TEST_DIRNAME/../scripts/sync-apple-skills.sh"
  [ "$status" -ne 0 ]
  run grep -c 'incoming-' "$BATS_TEST_DIRNAME/../scripts/sync-apple-skills.sh"
  [ "$output" -ge 1 ]
}
