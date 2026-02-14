#!/bin/bash

# Solo Pipeline Status
# ASCII-art hacker dashboard for active pipelines
#
# Usage:
#   solo-pipeline-status.sh              # show all active pipelines
#   solo-pipeline-status.sh <project>    # show specific pipeline
#   watch -n2 -c solo-pipeline-status.sh # auto-refresh

set -euo pipefail

PIPELINES_DIR="$HOME/.solo/pipelines"
FILTER_PROJECT="${1:-}"

# --- Colors (ANSI) ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# --- ASCII icons ---
DONE="${GREEN}[x]${RESET}"
RUN="${YELLOW}[>]${RESET}"
WAIT="${GRAY}[ ]${RESET}"
ARROW="${DIM}--->${RESET}"
QUEUE_ICON="${CYAN}|||${RESET}"

# --- Helper: time ago ---
time_ago() {
  local started="$1"
  local now
  now=$(date +%s)
  local started_epoch
  if [[ "$OSTYPE" == "darwin"* ]]; then
    started_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" +%s 2>/dev/null || echo "0")
  else
    started_epoch=$(date -u -d "$started" +%s 2>/dev/null || echo "0")
  fi
  if [[ "$started_epoch" == "0" ]]; then
    echo "??:??"
    return
  fi
  local diff=$(( now - started_epoch ))
  if [[ $diff -lt 60 ]]; then
    echo "${diff}s"
  elif [[ $diff -lt 3600 ]]; then
    echo "$(( diff / 60 ))m"
  else
    echo "$(( diff / 3600 ))h$(( (diff % 3600) / 60 ))m"
  fi
}

# --- Progress bar ---
progress_bar() {
  local done="$1"
  local total="$2"
  local width=20
  local filled=$(( done * width / total ))
  local empty=$(( width - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="="; done
  if [[ $filled -lt $width ]]; then
    bar+=">"
    for ((i=0; i<empty-1; i++)); do bar+="."; done
  fi
  echo "$bar"
}

# --- Find pipeline state files ---
if [[ ! -d "$PIPELINES_DIR" ]]; then
  echo -e "${DIM}"
  echo "  no pipelines"
  echo -e "${RESET}"
  exit 0
fi

found=0
for f in "$PIPELINES_DIR"/solo-pipeline-*.local.md; do
  [[ -f "$f" ]] || continue

  FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$f")

  ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//')
  [[ "$ACTIVE" != "true" ]] && continue

  PROJECT=$(echo "$FRONTMATTER" | grep '^project:' | sed 's/project: *//' | sed 's/^"\(.*\)"$/\1/')
  [[ -n "$FILTER_PROJECT" ]] && [[ "$PROJECT" != "$FILTER_PROJECT" ]] && continue

  IDEA=$(echo "$FRONTMATTER" | grep '^idea:' | sed 's/idea: *//' | sed 's/^"\(.*\)"$/\1/')
  PIPELINE_TYPE=$(echo "$FRONTMATTER" | grep '^pipeline:' | sed 's/pipeline: *//')
  ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
  MAX_ITER=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
  STARTED_AT=$(echo "$FRONTMATTER" | grep '^started_at:' | sed 's/started_at: *//' | sed 's/^"\(.*\)"$/\1/')
  LOG_FILE=$(echo "$FRONTMATTER" | grep '^log_file:' | sed 's/log_file: *//' | sed 's/^"\(.*\)"$/\1/')
  PROJECT_ROOT=$(echo "$FRONTMATTER" | grep '^project_root:' | sed 's/project_root: *//' | sed 's/^"\(.*\)"$/\1/')
  STACK=$(echo "$FRONTMATTER" | grep '^stack:' | sed 's/stack: *//' | sed 's/^"\(.*\)"$/\1/')
  [[ -z "$LOG_FILE" ]] && LOG_FILE="$PIPELINES_DIR/solo-pipeline-${PROJECT}.log"

  # Parse stages with Python
  STAGES_JSON=$(python3 -c "
import yaml, json, os, glob
with open('$f') as fh:
    content = fh.read()
parts = content.split('---', 2)
if len(parts) >= 3:
    fm = yaml.safe_load(parts[1])
    stages = fm.get('stages', [])
    for s in stages:
        check = s.get('check', '')
        if check:
            if '*' in check:
                s['done'] = len(glob.glob(os.path.expanduser(check))) > 0
            else:
                s['done'] = os.path.exists(os.path.expanduser(check))
    print(json.dumps(stages))
else:
    print('[]')
" 2>/dev/null || echo "[]")

  found=1
  ELAPSED=$(time_ago "$STARTED_AT")

  # Count done stages
  DONE_COUNT=$(echo "$STAGES_JSON" | python3 -c "import json,sys; s=json.load(sys.stdin); print(sum(1 for x in s if x.get('done')))" 2>/dev/null || echo "0")
  TOTAL_STAGES=$(echo "$STAGES_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

  # --- Header box ---
  echo ""
  echo -e "  ${BOLD}+--[ ${CYAN}${PROJECT}${RESET}${BOLD} ]-------------------------------+${RESET}"
  echo -e "  ${BOLD}|${RESET}"
  [[ -n "$STACK" ]] && echo -e "  ${BOLD}|${RESET}  stack    ${DIM}${STACK}${RESET}"
  [[ -n "$IDEA" ]] && echo -e "  ${BOLD}|${RESET}  idea     ${DIM}${IDEA}${RESET}"
  echo -e "  ${BOLD}|${RESET}  iter     ${YELLOW}${ITERATION}${RESET}/${DIM}${MAX_ITER}${RESET}  ${DIM}(${ELAPSED})${RESET}"

  BAR=$(progress_bar "$DONE_COUNT" "$TOTAL_STAGES")
  echo -e "  ${BOLD}|${RESET}  progress ${GREEN}[${BAR}]${RESET} ${DONE_COUNT}/${TOTAL_STAGES}"
  echo -e "  ${BOLD}|${RESET}"

  # --- Stage pipeline (horizontal) ---
  echo "$STAGES_JSON" | python3 -c "
import json, sys

stages = json.load(sys.stdin)
G = '\033[0;32m'
Y = '\033[1;33m'
D = '\033[0;90m'
R = '\033[0m'
B = '\033[1m'

found_running = False
line1 = '  ${BOLD}|${RESET}  '
line2 = '  ${BOLD}|${RESET}  '

for i, s in enumerate(stages):
    sid = s['id'][:8]
    done = s.get('done', False)

    if i > 0:
        line1 += f' {D}--->{R} '
        line2 += '      '

    if done:
        line1 += f'{G}[x]{R}'
        line2 += f'{D}{sid:<8s}{R}'
    elif not found_running:
        found_running = True
        line1 += f'{Y}[>]{R}'
        line2 += f'{Y}{B}{sid:<8s}{R}'
    else:
        line1 += f'{D}[ ]{R}'
        line2 += f'{D}{sid:<8s}{R}'

print(line1)
print(line2)
" 2>/dev/null

  echo -e "  ${BOLD}|${RESET}"

  # --- Plan queue ---
  if [[ -n "$PROJECT_ROOT" ]]; then
    QUEUE_DIR="$PROJECT_ROOT/docs/plan-queue"
    DONE_DIR="$PROJECT_ROOT/docs/plan-done"
    PLAN_DIR="$PROJECT_ROOT/docs/plan"

    ACTIVE_PLAN=""
    [[ -d "$PLAN_DIR" ]] && ACTIVE_PLAN=$(find "$PLAN_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)
    QUEUED_PLANS=$(find "$QUEUE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null 2>&1 | sort || true)
    QUEUED_COUNT=$(echo "$QUEUED_PLANS" | grep -c . 2>/dev/null || echo "0")
    [[ -z "$QUEUED_PLANS" ]] && QUEUED_COUNT=0
    DONE_PLANS=$(find "$DONE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null 2>&1 | sort || true)
    DONE_PLAN_COUNT=$(echo "$DONE_PLANS" | grep -c . 2>/dev/null || echo "0")
    [[ -z "$DONE_PLANS" ]] && DONE_PLAN_COUNT=0

    if [[ "$QUEUED_COUNT" -gt 0 ]] || [[ "$DONE_PLAN_COUNT" -gt 0 ]] || [[ -n "$ACTIVE_PLAN" ]]; then
      echo -e "  ${BOLD}|${RESET}  ${BOLD}plans${RESET}"

      # Show done plans
      if [[ -n "$DONE_PLANS" ]] && [[ "$DONE_PLAN_COUNT" -gt 0 ]]; then
        echo "$DONE_PLANS" | while read -r d; do
          [[ -z "$d" ]] && continue
          name=$(basename "$d")
          echo -e "  ${BOLD}|${RESET}    ${GREEN}[x]${RESET} ${DIM}${name}${RESET}"
        done
      fi

      # Show active plan
      if [[ -n "$ACTIVE_PLAN" ]]; then
        name=$(basename "$ACTIVE_PLAN")
        echo -e "  ${BOLD}|${RESET}    ${YELLOW}[>]${RESET} ${BOLD}${name}${RESET}  ${DIM}<-- active${RESET}"
      fi

      # Show queued plans
      if [[ -n "$QUEUED_PLANS" ]] && [[ "$QUEUED_COUNT" -gt 0 ]]; then
        echo "$QUEUED_PLANS" | while read -r d; do
          [[ -z "$d" ]] && continue
          name=$(basename "$d")
          echo -e "  ${BOLD}|${RESET}    ${GRAY}[ ]${RESET} ${DIM}${name}${RESET}"
        done
      fi

      echo -e "  ${BOLD}|${RESET}"
    fi
  fi

  # --- Footer ---
  echo -e "  ${BOLD}+-------------------------------------------+${RESET}"
  if [[ -f "$LOG_FILE" ]]; then
    echo -e "  ${DIM}log: tail -f ${LOG_FILE/$HOME/\~}${RESET}"
  fi
  echo -e "  ${DIM}cancel: rm ${f/$HOME/\~}${RESET}"
  echo ""

done

if [[ $found -eq 0 ]]; then
  echo ""
  if [[ -n "$FILTER_PROJECT" ]]; then
    echo -e "  ${DIM}no active pipeline for '${FILTER_PROJECT}'${RESET}"
  else
    echo -e "  ${DIM}no active pipelines${RESET}"
  fi
  echo ""
fi
