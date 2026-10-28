#!/usr/bin/env bash
# prepush-clean-tree.sh — run a pre-push check against the commits being pushed, not
# against the working tree.
#
# Why: a pre-push hook that runs the suite in the working tree judges whatever is lying
# there. With parallel sessions in one checkout, another session's uncommitted files
# failed the push of a clean commit, and agents learned to push with --no-verify; the
# same tree can also pass a commit that is broken on its own. A detached worktree of the
# pushed sha sees exactly what the remote will get.
#
# Install as .git/hooks/pre-push (git passes the refs on stdin):
#
#   #!/bin/sh
#   exec /path/to/solo-factory/scripts/prepush-clean-tree.sh -- make test
#
# SOLO_PREPUSH_LINK="eval models"  untracked data dirs the checks read; each is
#                                  symlinked from the main tree into the worktree.
# A push that only deletes remote refs runs nothing: there is no new code to check.

set -uo pipefail

[[ "${1:-}" == "--" ]] && shift
if [[ $# -eq 0 ]]; then
  echo "usage: prepush-clean-tree.sh -- <check command...>" >&2
  exit 2
fi

TOP=$(git rev-parse --show-toplevel) || exit 2
ZERO=0000000000000000000000000000000000000000
SHAS=()
while read -r _local_ref local_sha _remote_ref _remote_sha; do
  [[ -z "${local_sha:-}" || "$local_sha" == "$ZERO" ]] && continue   # a deletion
  [[ " ${SHAS[*]-} " == *" $local_sha "* ]] || SHAS+=("$local_sha")
done

if [[ ${#SHAS[@]} -eq 0 ]]; then
  echo "pre-push: only deletions, nothing to check"
  exit 0
fi

RC=0
for sha in "${SHAS[@]}"; do
  WT=$(mktemp -d "${TMPDIR:-/tmp}/prepush.XXXXXX")
  if ! git -C "$TOP" worktree add --detach --quiet "$WT" "$sha" 2>/dev/null; then
    echo "pre-push: could not check out $sha into a clean worktree" >&2
    rm -rf "$WT"; exit 2
  fi
  for d in ${SOLO_PREPUSH_LINK:-}; do
    [[ -e "$TOP/$d" && ! -e "$WT/$d" ]] && ln -s "$TOP/$d" "$WT/$d"
  done
  echo "pre-push: checking ${sha:0:10} in a clean worktree"
  ( cd "$WT" && "$@" ); rc=$?
  git -C "$TOP" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
  if [[ $rc -ne 0 ]]; then
    echo "pre-push: ${sha:0:10} fails its checks on its own (exit $rc); the working tree was not consulted" >&2
    RC=$rc
  fi
done
exit "$RC"
