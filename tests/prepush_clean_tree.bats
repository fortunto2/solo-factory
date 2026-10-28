#!/usr/bin/env bats
# prepush-clean-tree.sh — the push is judged on the pushed commit, never on the tree.
#
# Measured: a pre-push suite run in the working tree failed a clean commit because a
# parallel session had broken files lying uncommitted in the same checkout, and agents
# pushed with --no-verify to get past it. A full suite also ran for a push that only
# deleted remote branches.

S="${BATS_TEST_DIRNAME}/../scripts/prepush-clean-tree.sh"
CHECK=(python3 -c "import ast; ast.parse(open('a.py').read())")

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  R="$BATS_TEST_TMPDIR/repo"; mkdir -p "$R"
  ( cd "$R" && git init -q . && git config user.email t@e && git config user.name t
    printf 'x = 1\n' > a.py && git add -A && git commit -q -m base )
}

refs() {  # what git hands a pre-push hook for pushing HEAD
  printf 'refs/heads/main %s refs/heads/main %s\n' "$(git -C "$R" rev-parse HEAD)" \
    0000000000000000000000000000000000000000
}

@test "a clean commit passes although the working tree is broken" {
  printf 'def broken(:\n' > "$R/a.py"           # another session's uncommitted mess
  run bash -c "cd '$R' && $(declare -p CHECK); refs() { $(declare -f refs | tail -n +2); }; refs | bash '$S' -- \"\${CHECK[@]}\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean worktree"* ]]
}

@test "a broken commit fails although the working tree is fixed" {
  ( cd "$R" && printf 'def broken(:\n' > a.py && git commit -qam broken && printf 'x = 1\n' > a.py )
  run bash -c "cd '$R' && $(declare -p CHECK); refs() { $(declare -f refs | tail -n +2); }; refs | bash '$S' -- \"\${CHECK[@]}\""
  [ "$status" -ne 0 ]
  [[ "$output" == *"fails its checks on its own"* ]]
}

@test "a push that only deletes refs runs no check" {
  run bash -c "cd '$R' && printf '(delete) 0000000000000000000000000000000000000000 refs/heads/old abc\n' | bash '$S' -- false"
  [ "$status" -eq 0 ]
  [[ "$output" == *"only deletions"* ]]
}

@test "untracked data dirs named in SOLO_PREPUSH_LINK are visible to the check" {
  mkdir -p "$R/eval" && printf 'fixture\n' > "$R/eval/day.txt"   # data, never in git
  run bash -c "cd '$R' && refs() { $(declare -f refs | tail -n +2); }; refs | SOLO_PREPUSH_LINK=eval bash '$S' -- test -f eval/day.txt"
  [ "$status" -eq 0 ]
  run bash -c "cd '$R' && refs() { $(declare -f refs | tail -n +2); }; refs | bash '$S' -- test -f eval/day.txt"
  [ "$status" -ne 0 ]
}

@test "no leftover worktrees after a run" {
  run bash -c "cd '$R' && refs() { $(declare -f refs | tail -n +2); }; refs | bash '$S' -- true"
  [ "$status" -eq 0 ]
  [ "$(git -C "$R" worktree list | wc -l | tr -d ' ')" -eq 1 ]
}

@test "SOLO_PREPUSH_DIR keeps one worktree at a stable path and moves it to each pushed commit" {
  # A fresh random path per push makes path-keyed build caches (cargo) rebuild the
  # whole workspace every time; a kept worktree only rewrites the files that changed.
  W="$BATS_TEST_TMPDIR/kept"
  run bash -c "cd '$R' && refs() { $(declare -f refs | tail -n +2); }; refs | SOLO_PREPUSH_DIR='$W' bash '$S' -- grep -q 'x = 1' a.py"
  [ "$status" -eq 0 ]
  [ -d "$W" ]
  printf 'stray\n' > "$W/left-over.txt"        # last run's junk must not leak into the next
  ( cd "$R" && printf 'x = 2\n' > a.py && git commit -qam two )
  run bash -c "cd '$R' && refs() { $(declare -f refs | tail -n +2); }; refs | SOLO_PREPUSH_DIR='$W' bash '$S' -- sh -c \"grep -q 'x = 2' a.py && test ! -e left-over.txt\""
  [ "$status" -eq 0 ]
  [ "$(git -C "$R" worktree list | wc -l | tr -d ' ')" -eq 2 ]   # the kept one, not one per push
}
