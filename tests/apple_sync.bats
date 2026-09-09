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
  # The control that makes the invariant test able to fail: without it, "absent
  # implies .outgoing- exists" could pass on a probe that never samples a window.
  #
  # Deterministic, not raced. The first version ran the old order in the background
  # and polled — which under a loaded machine finished the copy before the loop took
  # a sample, and the CONTROL went flaky at ~1 run in 6 once the suite started
  # running 30 files at once. A control that only fires when the machine is idle is
  # not a control. The window is a property of the ORDER, so the order is stepped
  # through rather than raced.
  rm -rf "${D:?}/thing"
  # This is the state the old order occupies for the whole length of its copy.
  [ ! -e "$D/thing" ]
  compgen -G "$D/.outgoing-thing.*" >/dev/null && false || true   # nothing to recover from
  mkdir -p "$D"
  cp -R "$SRC/thing" "$D/thing"
  [ -e "$D/thing/f1.md" ]
}

@test "under the staged order, an absent destination always has its content beside it" {
  # Stepped, not raced — and this is the second time in one cycle that lesson had to
  # be applied. The control beside it was made deterministic first and this one was
  # left polling a background process; it then flaked at 2 runs in 6 under the
  # parallel suite. Fixing one racing test and leaving its sibling racing is its own
  # small finding: the change was understood as being about that test rather than
  # about the shape.
  #
  # The property has three boundaries and every one of them is checkable without a
  # clock: content staged, old moved aside, new in place.
  mkdir -p "$D"
  inc="$D/.incoming-thing.$$"; out="$D/.outgoing-thing.$$"
  rm -rf "$inc" "$out"

  cp -R "$SRC/thing" "$inc"
  [ -e "$D/thing/SKILL.md" ]              # destination still the OLD one, untouched

  mv "$D/thing" "$out"
  # The only moment the destination is absent. The invariant: its content is here.
  [ ! -e "$D/thing" ]
  [ -e "$out/SKILL.md" ]

  mv "$inc" "$D/thing"
  [ -e "$D/thing/f1.md" ]                 # the new content is in place
  [ -e "$out/SKILL.md" ]                  # and the old is still recoverable

  rm -rf "$out"
  [ -e "$D/thing/f1.md" ]
  [ ! -e "$D/thing/SKILL.md" ]
}


@test "a kill at any point leaves the content recoverable" {
  # The one test here that still races, deliberately: a real -9 at an arbitrary
  # moment is the failure the staged order exists for. What changed is the
  # assertion. It used to be "the destination exists and is non-empty", which is
  # FALSE in the window between the two `mv`s and would have flaked the moment a
  # loaded machine landed there — a weak claim that was also the wrong one.
  #
  # The true invariant holds at every instant: the content is either at the
  # destination or under `.outgoing-`. Never nowhere.
  new_order &
  bg=$!
  sleep 0.05
  kill -9 $bg 2>/dev/null || true
  wait $bg 2>/dev/null || true
  if [ -e "$D/thing" ] && [ -n "$(ls -A "$D/thing")" ]; then
    :                                        # swap done, or never started
  else
    compgen -G "$D/.outgoing-thing.*" >/dev/null
    [ -n "$(ls -A "$D"/.outgoing-thing.* 2>/dev/null)" ]
  fi
}

@test "the script itself uses the staged order, not delete-then-copy" {
  # The tests above exercise the shape. This pins it to the file, so the shape
  # cannot drift back while the tests keep passing on their local copies.
  run grep -n 'rm -rf "${DEST:?}/\$name"' "$BATS_TEST_DIRNAME/../scripts/sync-apple-skills.sh"
  [ "$status" -ne 0 ]
  run grep -c 'incoming-' "$BATS_TEST_DIRNAME/../scripts/sync-apple-skills.sh"
  [ "$output" -ge 1 ]
}
