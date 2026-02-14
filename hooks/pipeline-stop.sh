#!/bin/bash

# Solo Pipeline Stop Hook
# Intercepts session exit to progress through multi-skill pipelines
# State files: ~/.solo/pipelines/solo-pipeline-{project}.local.md (global, absolute)
#
# Supports multiple concurrent pipelines — each project gets its own state file.
# Hook scans all state files, picks the first active one with incomplete stages.

set -euo pipefail

PIPELINES_DIR="$HOME/.solo/pipelines"

# --- Log helper ---
log_entry() {
  local log_file="$1"
  local tag="$2"
  shift 2
  [[ -n "$log_file" ]] && echo "[$(date +%H:%M:%S)] $tag | $*" >> "$log_file" 2>/dev/null || true
}

# --- Calculate duration ---
calc_duration() {
  local started="$1"
  local now
  now=$(date +%s)
  local started_epoch
  if [[ "$OSTYPE" == "darwin"* ]]; then
    started_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" +%s 2>/dev/null || echo "0")
  else
    started_epoch=$(date -d "$started" +%s 2>/dev/null || echo "0")
  fi
  if [[ "$started_epoch" == "0" ]]; then
    echo "unknown"
    return
  fi
  local diff=$(( now - started_epoch ))
  if [[ $diff -lt 60 ]]; then
    echo "${diff}s"
  elif [[ $diff -lt 3600 ]]; then
    echo "$(( diff / 60 ))m"
  else
    echo "$(( diff / 3600 ))h $(( (diff % 3600) / 60 ))m"
  fi
}

# --- Find active pipeline state file ---
STATE_FILE=""

if [[ -d "$PIPELINES_DIR" ]]; then
  for f in "$PIPELINES_DIR"/solo-pipeline-*.local.md; do
    [[ -f "$f" ]] || continue
    if grep -q '^active: true' "$f" 2>/dev/null; then
      STATE_FILE="$f"
      break
    fi
  done
fi

# No active pipeline — allow exit
if [[ -z "$STATE_FILE" ]]; then
  exit 0
fi

# Read hook input from stdin
HOOK_INPUT=$(cat)

# --- Parse YAML frontmatter ---
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")

# --- Skip if Big Head is managing this pipeline ---
MODE=$(echo "$FRONTMATTER" | grep '^mode:' | sed 's/mode: *//')
if [[ "$MODE" == "bighead" ]]; then
  exit 0
fi

ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//')
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
SIGNALS=$(echo "$FRONTMATTER" | grep '^signals:' | sed 's/signals: *//' | sed 's/^"\(.*\)"$/\1/')
PIPELINE_TYPE=$(echo "$FRONTMATTER" | grep '^pipeline:' | sed 's/pipeline: *//')
IDEA=$(echo "$FRONTMATTER" | grep '^idea:' | sed 's/idea: *//' | sed 's/^"\(.*\)"$/\1/')
PROJECT=$(echo "$FRONTMATTER" | grep '^project:' | sed 's/project: *//' | sed 's/^"\(.*\)"$/\1/')
CONTEXT_FILE=$(echo "$FRONTMATTER" | grep '^context_file:' | sed 's/context_file: *//' | sed 's/^"\(.*\)"$/\1/')
PROJECT_ROOT=$(echo "$FRONTMATTER" | grep '^project_root:' | sed 's/project_root: *//' | sed 's/^"\(.*\)"$/\1/')
LOG_FILE=$(echo "$FRONTMATTER" | grep '^log_file:' | sed 's/log_file: *//' | sed 's/^"\(.*\)"$/\1/')
STARTED_AT=$(echo "$FRONTMATTER" | grep '^started_at:' | sed 's/started_at: *//' | sed 's/^"\(.*\)"$/\1/')

# Fallback log file path if not in frontmatter (backward compat)
if [[ -z "$LOG_FILE" ]]; then
  LOG_FILE="$PIPELINES_DIR/solo-pipeline-${PROJECT}.log"
fi

log_entry "$LOG_FILE" "HOOK" "iter $((ITERATION + 1))/$MAX_ITERATIONS | checking stages..."

# Not active — allow exit
if [[ "$ACTIVE" != "true" ]]; then
  exit 0
fi

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "Pipeline ($PROJECT): corrupted state (iteration='$ITERATION'). Removing." >&2
  log_entry "$LOG_FILE" "ERROR" "corrupted state (iteration='$ITERATION'). Removing."
  rm "$STATE_FILE"
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Pipeline ($PROJECT): corrupted state (max_iterations='$MAX_ITERATIONS'). Removing." >&2
  log_entry "$LOG_FILE" "ERROR" "corrupted state (max_iterations='$MAX_ITERATIONS'). Removing."
  rm "$STATE_FILE"
  exit 0
fi

# Check max iterations
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  DURATION=$(calc_duration "$STARTED_AT")
  echo "Pipeline ($PROJECT): max iterations ($MAX_ITERATIONS) reached." >&2
  log_entry "$LOG_FILE" "MAXITER" "max iterations ($MAX_ITERATIONS) reached. Duration: $DURATION"
  rm "$STATE_FILE"
  exit 0
fi

# --- Check <solo:done/> / <solo:redo/> signals in last assistant message ---
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')
SIGNAL_DONE=false
SIGNAL_REDO=false

if [[ -f "$TRANSCRIPT_PATH" ]] && grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1)
  LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
    .message.content |
    map(select(.type == "text")) |
    map(.text) |
    join("\n")
  ' 2>/dev/null || echo "")

  echo "$LAST_OUTPUT" | grep -q '<solo:done/>' 2>/dev/null && SIGNAL_DONE=true
  echo "$LAST_OUTPUT" | grep -q '<solo:redo/>' 2>/dev/null && SIGNAL_REDO=true
fi

# Create/remove stage markers based on signals (same as solo-dev.sh does)
if [[ "$SIGNAL_DONE" == "true" ]] || [[ "$SIGNAL_REDO" == "true" ]]; then
  # Find current (first incomplete) stage to know which marker to create
  CURRENT_STAGE_CHECK=$(python3 -c "
import yaml, json, os, glob
with open('$STATE_FILE') as f:
    content = f.read()
parts = content.split('---', 2)
if len(parts) >= 3:
    fm = yaml.safe_load(parts[1])
    for s in fm.get('stages', []):
        check = s.get('check', '')
        if not check:
            continue
        if '*' in check:
            if len(glob.glob(os.path.expanduser(check))) == 0:
                print(s['id'] + '|' + check)
                break
        else:
            if not os.path.exists(os.path.expanduser(check)):
                print(s['id'] + '|' + check)
                break
" 2>/dev/null || echo "")

  if [[ -n "$CURRENT_STAGE_CHECK" ]]; then
    CUR_STAGE_ID="${CURRENT_STAGE_CHECK%%|*}"
    CUR_STAGE_FILE="${CURRENT_STAGE_CHECK##*|}"

    if [[ "$SIGNAL_DONE" == "true" ]]; then
      # Create marker for current stage (if it's a states/ file, not a glob)
      if [[ "$CUR_STAGE_FILE" != *"*"* ]] && [[ ! -f "$CUR_STAGE_FILE" ]]; then
        mkdir -p "$(dirname "$CUR_STAGE_FILE")"
        echo "Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$CUR_STAGE_FILE"
        log_entry "$LOG_FILE" "SIGNAL" "<solo:done/> → creating $CUR_STAGE_ID marker"
      fi
    fi

    if [[ "$SIGNAL_REDO" == "true" ]]; then
      # Remove build marker (review → build loop)
      STATES_DIR="$PROJECT_ROOT/.solo/states"
      if [[ -f "$STATES_DIR/build" ]]; then
        rm -f "$STATES_DIR/build"
        log_entry "$LOG_FILE" "SIGNAL" "<solo:redo/> → removing build marker"
      fi
    fi
  fi
fi

# --- Parse stages and check which are done ---
STAGES_JSON=$(python3 -c "
import yaml, json, sys, os, glob
with open('$STATE_FILE') as f:
    content = f.read()
parts = content.split('---', 2)
if len(parts) >= 3:
    fm = yaml.safe_load(parts[1])
    stages = fm.get('stages', [])
    for s in stages:
        check = s.get('check', '')
        if check:
            # Always re-check file existence (review <solo:redo/> removes .solo/states/build)
            if '*' in check:
                s['done'] = len(glob.glob(os.path.expanduser(check))) > 0
            else:
                s['done'] = os.path.exists(os.path.expanduser(check))
    print(json.dumps(stages))
else:
    print('[]')
" 2>/dev/null || echo "[]")

# Log check results for each stage
echo "$STAGES_JSON" | python3 -c "
import json, sys
stages = json.load(sys.stdin)
for s in stages:
    check = s.get('check', '')
    done = s.get('done', False)
    status = 'FOUND' if done else 'NOT FOUND'
    print(f'{s[\"id\"]}|{check}|{status}')
" 2>/dev/null | while IFS='|' read -r sid scheck sstatus; do
  log_entry "$LOG_FILE" "CHECK" "$sid | $scheck -> $sstatus"
done

# Find first incomplete stage
NEXT_STAGE=$(echo "$STAGES_JSON" | jq -r '[.[] | select(.done == false)] | .[0] // empty')

if [[ -z "$NEXT_STAGE" ]]; then
  DURATION=$(calc_duration "$STARTED_AT")
  echo "Pipeline ($PROJECT): all stages complete!" >&2
  log_entry "$LOG_FILE" "DONE" "All stages complete! Duration: $DURATION"
  rm "$STATE_FILE"
  exit 0
fi

STAGE_ID=$(echo "$NEXT_STAGE" | jq -r '.id')
STAGE_SKILL=$(echo "$NEXT_STAGE" | jq -r '.skill')
STAGE_ARGS=$(echo "$NEXT_STAGE" | jq -r '.args // ""')
TOTAL_STAGES=$(echo "$STAGES_JSON" | jq 'length')
DONE_COUNT=$(echo "$STAGES_JSON" | jq '[.[] | select(.done == true)] | length')
STAGE_NUM=$((DONE_COUNT + 1))

# --- Increment iteration ---
NEXT_ITERATION=$((ITERATION + 1))
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# --- Update done flags in state file ---
python3 -c "
import yaml, os, glob
with open('$STATE_FILE') as f:
    content = f.read()
parts = content.split('---', 2)
if len(parts) >= 3:
    fm = yaml.safe_load(parts[1])
    for s in fm.get('stages', []):
        check = s.get('check', '')
        if check and not s.get('done', False):
            if '*' in check:
                s['done'] = len(glob.glob(os.path.expanduser(check))) > 0
            else:
                s['done'] = os.path.exists(os.path.expanduser(check))
    body = parts[2]
    with open('$STATE_FILE', 'w') as f:
        f.write('---\n')
        f.write(yaml.dump(fm, default_flow_style=False, allow_unicode=True))
        f.write('---')
        f.write(body)
" 2>/dev/null

# --- Build prompt ---
PROMPT="Run $STAGE_SKILL"
if [[ -n "$STAGE_ARGS" ]]; then
  PROMPT="$PROMPT $STAGE_ARGS"
fi

# Inject context file/directory instruction
if [[ -n "$CONTEXT_FILE" ]]; then
  if [[ -d "$CONTEXT_FILE" ]]; then
    # Directory — list .md files for agent to read
    MD_FILES=$(find "$CONTEXT_FILE" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
    if [[ -n "$MD_FILES" ]]; then
      FILE_LIST=$(echo "$MD_FILES" | sed 's/^/  /')
      PROMPT="$PROMPT

IMPORTANT: Read the context files in this directory for background research and data:
$FILE_LIST
Use their content as input — competitors, tech stack, market data, pain points, etc."
    fi
  elif [[ -f "$CONTEXT_FILE" ]]; then
    PROMPT="$PROMPT

IMPORTANT: Read the context file first for background research and data:
  $CONTEXT_FILE
Use its content as input — competitors, tech stack, market data, pain points, etc."
  fi
fi

PROMPT="$PROMPT

This is stage $STAGE_NUM/$TOTAL_STAGES ($STAGE_ID) of the $PIPELINE_TYPE pipeline (project: $PROJECT).
When done with this stage, output exactly: <solo:done/>
If the stage needs to go back (e.g. review found issues), output exactly: <solo:redo/>"

SYSTEM_MSG="Pipeline ($PROJECT) iteration $NEXT_ITERATION | Stage $STAGE_NUM/$TOTAL_STAGES: $STAGE_ID"

log_entry "$LOG_FILE" "INJECT" "$STAGE_ID | $STAGE_SKILL $STAGE_ARGS"

# Output JSON to block exit and inject next prompt
jq -n \
  --arg prompt "$PROMPT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
