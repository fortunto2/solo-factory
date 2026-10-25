# shellcheck shell=bash
# tree-print.sh — sourced by sensor-baseline.sh and sensor-stop.sh.
# tree_print ROOT: one hash for the dirty state of the working tree (status + mtime/size).
tree_print() {
  local root=$1 fmt=(-f '%N %m %z')                       # BSD/macOS stat
  stat --version >/dev/null 2>&1 && fmt=(-c '%n %Y %s')   # GNU stat
  {
    git -C "$root" status --porcelain=v1 --untracked-files=all 2>/dev/null
    { git -C "$root" diff --name-only -z HEAD 2>/dev/null
      git -C "$root" ls-files -o --exclude-standard -z 2>/dev/null; } \
      | (cd "$root" && xargs -0 stat "${fmt[@]}" 2>/dev/null)
  } | shasum -a 1 | cut -d' ' -f1
}
