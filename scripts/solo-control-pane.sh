#!/bin/bash
# Solo Dashboard — control pane (spawned inside tmux)
# Usage: solo-control-pane.sh <project-name>

P="$1"
S="solo-$P"
C="$HOME/startups/active/$P/.solo/pipelines/control"
M="$HOME/startups/active/$P/.solo/pipelines/messages"
mkdir -p "$(dirname "$C")"

kill_dashboard() {
  printf "\n\033[31mKilling dashboard...\033[0m\n"
  sleep 0.3
  tmux kill-session -t "$S" 2>/dev/null
  exit 0
}
trap kill_dashboard INT

while true; do
  clear
  printf "\033[1m═ Control: %s ═\033[0m\n" "$P"
  echo "p=pause  r=resume  s=stop  k=skip  m=message  ^C=KILL"
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
  esac
  sleep 1
done
