#!/bin/bash

# Solo Dashboard — tmux session manager for pipeline monitoring
#
# Usage:
#   solo-dashboard.sh create <name>             # create tmux session with log + status panes
#   solo-dashboard.sh add <name> <command>       # add work pane (or reuse idle first pane)
#   solo-dashboard.sh attach <name>              # attach to session
#   solo-dashboard.sh close <name>               # kill session

set -euo pipefail

PIPELINES_DIR="$HOME/.solo/pipelines"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: solo-dashboard.sh <command> <name> [args...]"
  echo ""
  echo "Commands:"
  echo "  create <name>            Create tmux session with log + status panes"
  echo "  add <name> <command>     Add work pane or reuse idle pane"
  echo "  attach <name>            Attach to tmux session"
  echo "  close <name>             Kill tmux session"
  exit 1
}

[[ $# -lt 2 ]] && usage

CMD="$1"
NAME="$2"
shift 2

SESSION="solo-${NAME}"
STATUS_CMD="$SCRIPT_DIR/solo-pipeline-status.sh $NAME"

# Read log_file from state file (absolute path to project .solo/pipelines/pipeline.log)
STATE_FILE="$PIPELINES_DIR/solo-pipeline-${NAME}.local.md"
LOG_FILE=""
if [[ -f "$STATE_FILE" ]]; then
  LOG_FILE=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" | grep '^log_file:' | sed 's/log_file: *//' | sed 's/^"\(.*\)"$/\1/')
fi
# Fallback if state file doesn't exist yet or has no log_file
if [[ -z "$LOG_FILE" ]]; then
  # Try project root from state file
  PROJ_ROOT=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" 2>/dev/null | grep '^project_root:' | sed 's/project_root: *//' | sed 's/^"\(.*\)"$/\1/')
  if [[ -n "$PROJ_ROOT" ]]; then
    LOG_FILE="$PROJ_ROOT/.solo/pipelines/pipeline.log"
  else
    LOG_FILE="$PIPELINES_DIR/solo-pipeline-${NAME}.log"
  fi
fi

# Get pane IDs sorted by index (respects base-index and pane-base-index)
# Returns lines like "%0 %1 %2" — unique pane IDs that always work
get_pane_ids() {
  tmux list-panes -t "$SESSION" -F '#{pane_id}' 2>/dev/null
}

# Get first pane ID
first_pane() {
  get_pane_ids | head -1
}

case "$CMD" in
  create)
    # Check tmux available
    if ! command -v tmux &>/dev/null; then
      echo "Error: tmux not found. Install with: brew install tmux"
      exit 1
    fi

    # Don't recreate if already exists
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Session '$SESSION' already exists. Use: solo-dashboard.sh attach $NAME"
      exit 0
    fi

    mkdir -p "$PIPELINES_DIR"

    # Create session with work pane
    tmux new-session -d -s "$SESSION" -x 200 -y 50
    WORK_PANE=$(first_pane)

    # Split right for log tail
    tmux split-window -h -t "$WORK_PANE" -p 35
    # New pane is now active — grab its ID
    LOG_PANE=$(tmux display-message -t "$SESSION" -p '#{pane_id}')

    if [[ -f "$LOG_FILE" ]]; then
      tmux send-keys -t "$LOG_PANE" "tail -f '$LOG_FILE'" C-m
    else
      tmux send-keys -t "$LOG_PANE" "echo 'Waiting for log...' && while [ ! -f '$LOG_FILE' ]; do sleep 1; done && tail -f '$LOG_FILE'" C-m
    fi

    # Split bottom-right for status
    tmux split-window -v -t "$LOG_PANE" -p 40
    STATUS_PANE=$(tmux display-message -t "$SESSION" -p '#{pane_id}')

    # Use watch if available, fallback to loop
    if command -v watch &>/dev/null; then
      tmux send-keys -t "$STATUS_PANE" "watch -n2 -c '$STATUS_CMD'" C-m
    else
      tmux send-keys -t "$STATUS_PANE" "while true; do clear; $STATUS_CMD; sleep 2; done" C-m
    fi

    # Split bottom of status pane for control menu
    PROJECT_NAME="$NAME"
    tmux split-window -v -t "$STATUS_PANE" -p 25 bash -c '
P="'"$PROJECT_NAME"'"
C="$HOME/startups/active/$P/.solo/pipelines/control"
M="$HOME/startups/active/$P/.solo/pipelines/messages"
mkdir -p "$(dirname "$C")"
while true; do
  clear
  printf "\033[1m═ Control: %s ═\033[0m\n" "$P"
  echo "p=pause  r=resume  s=stop  k=skip  m=message  q=close"
  echo ""
  if [[ -f "$C" ]]; then
    printf "  Status: \033[33m%s\033[0m\n" "$(head -1 "$C")"
  else
    printf "  Status: \033[32mrunning\033[0m\n"
  fi
  read -rsn1 K
  case $K in
    p) echo pause>"$C"; printf "\n\033[33mPaused\033[0m\n";;
    r) rm -f "$C"; printf "\n\033[32mResumed\033[0m\n";;
    s) echo stop>"$C"; printf "\n\033[31mStopping...\033[0m\n";;
    k) echo skip>"$C"; printf "\n\033[36mSkipping stage...\033[0m\n";;
    m) printf "\n→ "; read -r T; echo "$T">>"$M"; printf "\033[32mSent\033[0m\n";;
    q) exit 0;;
  esac
  sleep 1
done'

    # Focus work pane
    tmux select-pane -t "$WORK_PANE"

    echo "Dashboard created: $SESSION"
    echo "  Pane: work area"
    echo "  Pane: log tail"
    echo "  Pane: status monitor"
    echo "  Pane: control (p/r/s/k/m/q)"
    echo ""
    echo "Attach: solo-dashboard.sh attach $NAME"
    ;;

  add)
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Error: session '$SESSION' not found. Create first: solo-dashboard.sh create $NAME"
      exit 1
    fi

    WORK_CMD="$*"
    if [[ -z "$WORK_CMD" ]]; then
      echo "Usage: solo-dashboard.sh add <name> <command>"
      exit 1
    fi

    FIRST=$(first_pane)

    # Check if first pane is idle (running a shell)
    PANE_CMD=$(tmux display-message -p -t "$FIRST" '#{pane_current_command}' 2>/dev/null || echo "")

    # Match any common shell (with or without hyphen prefix for login shells)
    case "$PANE_CMD" in
      bash|zsh|fish|sh|dash|ksh|tcsh|-bash|-zsh|-fish|-sh|login)
        # First pane is idle — send command there
        tmux send-keys -t "$FIRST" "$WORK_CMD" C-m
        ;;
      *)
        # First pane is busy — split a new work pane
        tmux split-window -v -t "$FIRST"
        NEW_PANE=$(tmux display-message -t "$SESSION" -p '#{pane_id}')
        tmux send-keys -t "$NEW_PANE" "$WORK_CMD" C-m
        # Rebalance layout
        tmux select-layout -t "$SESSION" tiled
        ;;
    esac

    echo "Added command to $SESSION"
    ;;

  attach)
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Error: session '$SESSION' not found"
      exit 1
    fi

    if [[ -n "${TMUX:-}" ]]; then
      tmux switch-client -t "$SESSION"
    else
      tmux attach -t "$SESSION"
    fi
    ;;

  close)
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      tmux kill-session -t "$SESSION"
      echo "Session '$SESSION' closed"
    else
      echo "Session '$SESSION' not found"
    fi
    ;;

  *)
    usage
    ;;
esac
