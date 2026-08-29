#!/bin/sh
# shellcheck disable=SC2154  # dir/model/chat/... are assigned by the eval below
# Claude Code statusline: chat name · dir (branch) · model · context · limits
#
# Colored by importance instead of the usual \033[2m dim, which is invisible on a
# light background. 256-palette, not truecolor: Apple Terminal has no 24-bit color.
# The palette follows the theme via the state file the `theme` script writes.
#
# Install: chmod +x, then in ~/.claude/settings.json
#   "statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" }
input=$(cat)

# one jq call, not six — this runs on every render
eval "$(printf '%s' "$input" | jq -r '
  @sh "dir=\(.workspace.current_dir // .cwd // "?")
       model=\(.model.display_name // "Claude")
       chat=\(.session_name // "")
       rem=\(.context_window.remaining_percentage // "")
       five=\(.rate_limits.five_hour.used_percentage // "")
       week=\(.rate_limits.seven_day.used_percentage // "")
       effort=\(.effort.level // "")"')"

case "$(cat ~/.config/terminal-profiles/.state 2>/dev/null)" in
  dark) C_CHAT=175; C_DIR=246; C_BRANCH=108; C_MODEL=179; C_DIM=137
        C_OK=107; C_WARN=179; C_LOW=167 ;;
  *)    C_CHAT=89;  C_DIR=240; C_BRANCH=24;  C_MODEL=130; C_DIM=101
        C_OK=64;  C_WARN=94;  C_LOW=124 ;;
esac
c()  { printf '\033[38;5;%sm%s\033[0m' "$1" "$2"; }        # colored
cb() { printf '\033[1;38;5;%sm%s\033[0m' "$1" "$2"; }      # colored + bold
sep() { c "$C_DIR" ' · '; }

branch=""
if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  b=$(git -C "$dir" -c gc.auto=0 symbolic-ref --short HEAD 2>/dev/null)
  [ -n "$b" ] && branch="$b"
fi

# Optional: name the account when juggling several via CLAUDE_CONFIG_DIR
case "${CLAUDE_CONFIG_DIR}" in
  *work*) account="work" ;;
  *)      account="" ;;
esac

# chat name first — it is what the eye hunts for most often
[ -n "$chat" ] && { cb "$C_CHAT" "$chat"; sep; }

c "$C_DIR" "$(basename "$dir")"
[ -n "$branch" ] && { printf ' '; cb "$C_BRANCH" "($branch)"; }
sep
cb "$C_MODEL" "$model"
[ "$effort" = "xhigh" ] || [ "$effort" = "max" ] && c "$C_DIM" " $effort"

if [ -n "$rem" ]; then
  r=$(printf '%.0f' "$rem")
  if   [ "$r" -ge 50 ]; then col=$C_OK
  elif [ "$r" -ge 20 ]; then col=$C_WARN
  else col=$C_LOW; fi
  sep; c "$col" "${r}% ctx"
fi

if [ -n "$five" ] || [ -n "$week" ]; then
  sep
  [ -n "$five" ] && c "$C_DIM" "5h $(printf '%.0f' "$five")%"
  [ -n "$five" ] && [ -n "$week" ] && c "$C_DIR" " / "
  if [ -n "$week" ]; then
    w=$(printf '%.0f' "$week")
    if   [ "$w" -ge 80 ]; then col=$C_LOW
    elif [ "$w" -ge 50 ]; then col=$C_WARN
    else col=$C_DIM; fi
    c "$col" "7d ${w}%"
  fi
fi

[ -n "$account" ] && { sep; c "$C_DIM" "$account"; }
