#!/bin/bash

# Solo Pipeline Status
# Displays colored status of active pipelines from ~/.solo/pipelines/
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
BOLD='\033[1m'
RESET='\033[0m'

CHECKMARK="${GREEN}\xE2\x9C\x94${RESET}"
SPINNER="${YELLOW}\xE2\x97\x8F${RESET}"
WAITING="${GRAY}\xE2\x97\x8B${RESET}"

# --- Helper: time ago ---
time_ago() {
  local started="$1"
  local now
  now=$(date +%s)
  # Parse ISO 8601 date
  local started_epoch
  if [[ "$OSTYPE" == "darwin"* ]]; then
    started_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" +%s 2>/dev/null || echo "0")
  else
    started_epoch=$(date -u -d "$started" +%s 2>/dev/null || echo "0")
  fi
  if [[ "$started_epoch" == "0" ]]; then
    echo "unknown"
    return
  fi
  local diff=$(( now - started_epoch ))
  if [[ $diff -lt 60 ]]; then
    echo "${diff}s ago"
  elif [[ $diff -lt 3600 ]]; then
    echo "$(( diff / 60 ))m ago"
  else
    echo "$(( diff / 3600 ))h $(( (diff % 3600) / 60 ))m ago"
  fi
}

# --- Find pipeline state files ---
if [[ ! -d "$PIPELINES_DIR" ]]; then
  echo -e "${GRAY}No pipelines directory at $PIPELINES_DIR${RESET}"
  exit 0
fi

found=0
for f in "$PIPELINES_DIR"/solo-pipeline-*.local.md; do
  [[ -f "$f" ]] || continue

  # Parse YAML frontmatter (flat keys)
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
  LOG_FILE="$PIPELINES_DIR/solo-pipeline-${PROJECT}.log"

  # Parse stages with Python (handles YAML arrays)
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
        if check and not s.get('done', False):
            if '*' in check:
                s['done'] = len(glob.glob(os.path.expanduser(check))) > 0
            else:
                s['done'] = os.path.exists(os.path.expanduser(check))
    print(json.dumps(stages))
else:
    print('[]')
" 2>/dev/null || echo "[]")

  # Build stage chain display
  STAGE_CHAIN=$(echo "$STAGES_JSON" | python3 -c "
import json, sys
stages = json.load(sys.stdin)
print(' -> '.join(s['id'] for s in stages))
" 2>/dev/null || echo "unknown")

  found=1
  ELAPSED=$(time_ago "$STARTED_AT")
  STARTED_TIME=""
  # Convert UTC started_at to local time for display
  _epoch=0
  if [[ "$OSTYPE" == "darwin"* ]]; then
    _epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED_AT" +%s 2>/dev/null || echo "0")
  else
    _epoch=$(date -u -d "$STARTED_AT" +%s 2>/dev/null || echo "0")
  fi
  if [[ "$_epoch" != "0" ]]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      STARTED_TIME=$(date -j -r "$_epoch" "+%H:%M" 2>/dev/null || echo "")
    else
      STARTED_TIME=$(date -d "@$_epoch" "+%H:%M" 2>/dev/null || echo "")
    fi
  fi

  # Print header
  echo ""
  echo -e " ${BOLD}Pipeline:${RESET} $PROJECT"
  [[ -n "$IDEA" ]] && echo -e " ${BOLD}Idea:${RESET}     $IDEA"
  echo -e " ${BOLD}Pipeline:${RESET} $STAGE_CHAIN"
  echo -e " ${BOLD}Iter:${RESET}     ${ITERATION}/${MAX_ITER}  Started: ${STARTED_TIME} (${ELAPSED})"
  echo ""

  # Print each stage
  echo "$STAGES_JSON" | python3 -c "
import json, sys

stages = json.load(sys.stdin)
found_running = False
for s in stages:
    sid = s['id']
    done = s.get('done', False)
    check = s.get('check', '')
    # Derive output filename from check path
    out = check.split('/')[-1] if check else ''
    if done:
        # Green checkmark
        print(f'   \033[0;32m\u2714\033[0m  {\"done\":<10s} {sid:<12s} {out}')
    elif not found_running:
        found_running = True
        # Yellow spinner
        print(f'   \033[1;33m\u25CF\033[0m  {\"running\":<10s} {sid:<12s} {out}')
    else:
        # Gray waiting
        print(f'   \033[0;90m\u25CB\033[0m  {\"waiting\":<10s} {sid:<12s} {out}')
" 2>/dev/null

  echo ""
  if [[ -f "$LOG_FILE" ]]; then
    echo -e " ${GRAY}Log: tail -f $LOG_FILE${RESET}"
  fi
  echo ""

done

if [[ $found -eq 0 ]]; then
  if [[ -n "$FILTER_PROJECT" ]]; then
    echo -e "${GRAY}No active pipeline for '$FILTER_PROJECT'${RESET}"
  else
    echo -e "${GRAY}No active pipelines${RESET}"
  fi
fi
