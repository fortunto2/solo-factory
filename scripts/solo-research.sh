#!/bin/bash

# Solo Research Pipeline
# Chains: /research -> /validate (produces research.md -> prd.md)
# Runs claude --dangerously-skip-permissions --print in a loop (Ralph-style)
#
# Usage:
#   solo-research.sh "idea name" [--project name] [--file path] [--from stage] [--max N] [--no-dashboard]
#
# Examples:
#   solo-research.sh "AI therapist app"
#   solo-research.sh "AI therapist app" --project lovon
#   solo-research.sh "Jarvis voice agent" --file 3-inbox/jarvis-research.md
#   solo-research.sh "Jarvis voice agent" --file 4-opportunities/jarvis/   # directory
#   solo-research.sh "Jarvis voice agent" --from validate                  # skip research
#   solo-research.sh "AI therapist app" --project lovon --max 8
#   solo-research.sh "AI therapist app" --no-dashboard                     # skip tmux

set -euo pipefail

PIPELINES_DIR="$HOME/.solo/pipelines"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCH_DIR="$(pwd)"

# Save original args for tmux re-exec
SAVED_ARGS=("$@")

# --- Parse arguments ---
IDEA=""
PROJECT=""
CONTEXT_FILE=""
START_FROM=""
MAX_ITERATIONS=5
NO_DASHBOARD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --file) CONTEXT_FILE="$2"; shift 2 ;;
    --from) START_FROM="$2"; shift 2 ;;
    --max) MAX_ITERATIONS="$2"; shift 2 ;;
    --no-dashboard) NO_DASHBOARD=true; shift ;;
    *) IDEA="$1"; shift ;;
  esac
done

if [[ -z "$IDEA" ]]; then
  echo "Usage: solo-research.sh \"idea name\" [--project name] [--file path|dir] [--from stage] [--max N] [--no-dashboard]"
  echo ""
  echo "Stages: research, validate"
  echo "  --from validate    # skip research, start from validate"
  echo "  --file path        # file or directory with context for all stages"
  echo "  --no-dashboard     # skip tmux dashboard"
  exit 1
fi

# Resolve context file/dir to absolute path
if [[ -n "$CONTEXT_FILE" ]]; then
  if [[ -f "$CONTEXT_FILE" ]]; then
    CONTEXT_FILE=$(cd "$(dirname "$CONTEXT_FILE")" && pwd)/$(basename "$CONTEXT_FILE")
  elif [[ -d "$CONTEXT_FILE" ]]; then
    CONTEXT_FILE=$(cd "$CONTEXT_FILE" && pwd)
  else
    echo "Error: Context path not found: $CONTEXT_FILE"
    exit 1
  fi
fi

# Validate --from stage
if [[ -n "$START_FROM" ]]; then
  case "$START_FROM" in
    research|validate) ;;
    *) echo "Error: Unknown stage '$START_FROM'. Valid: research, validate"; exit 1 ;;
  esac
fi

# Generate project slug from idea if not provided
if [[ -z "$PROJECT" ]]; then
  PROJECT=$(echo "$IDEA" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
fi

# --- Detect project root (KB path) ---
PROJECT_ROOT=""
if [[ -d "4-opportunities" ]]; then
  PROJECT_ROOT="$(pwd)"
elif [[ -d "$HOME/startups/solopreneur/4-opportunities" ]]; then
  PROJECT_ROOT="$HOME/startups/solopreneur"
else
  echo "Error: Cannot find 4-opportunities/ directory"
  exit 1
fi

KB_PATH="$PROJECT_ROOT/4-opportunities"
RESEARCH_CHECK="$KB_PATH/$PROJECT/research.md"
PRD_CHECK="$KB_PATH/$PROJECT/prd.md"

# --- State & log files ---
mkdir -p "$PIPELINES_DIR"
mkdir -p "$PROJECT_ROOT/.solo/pipelines"
STATE_FILE="$PIPELINES_DIR/solo-pipeline-${PROJECT}.local.md"
LOG_FILE="$PROJECT_ROOT/.solo/pipelines/pipeline.log"
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Truncate log on fresh run (not on --no-dashboard re-exec)
if [[ "$NO_DASHBOARD" == "false" ]]; then
  : > "$LOG_FILE"
fi

# --- Log helper ---
log_entry() {
  local tag="$1"
  shift
  echo "[$(date +%H:%M:%S)] $tag | $*" | tee -a "$LOG_FILE"
}

# --- Check for existing pipeline (skip on tmux re-exec) ---
if [[ -f "$STATE_FILE" ]] && [[ "$NO_DASHBOARD" == "false" ]]; then
  echo "Warning: Pipeline already exists for '$PROJECT'"
  echo "  State: $STATE_FILE"
  echo "  Delete it first to restart: rm $STATE_FILE"
  exit 1
fi

# --- Build stages array ---
declare -a STAGE_IDS STAGE_SKILLS STAGE_ARGS STAGE_CHECKS
IDX=0

if [[ "$START_FROM" != "validate" ]]; then
  STAGE_IDS[$IDX]="research"
  STAGE_SKILLS[$IDX]="/solo:research"
  STAGE_ARGS[$IDX]="\"$IDEA\""
  STAGE_CHECKS[$IDX]="$RESEARCH_CHECK"
  IDX=$((IDX + 1))
fi

STAGE_IDS[$IDX]="validate"
STAGE_SKILLS[$IDX]="/solo:validate"
STAGE_ARGS[$IDX]="\"$IDEA\""
STAGE_CHECKS[$IDX]="$PRD_CHECK"

TOTAL_STAGES=${#STAGE_IDS[@]}

# --- Build context instruction ---
CONTEXT_INSTRUCTION=""
if [[ -n "$CONTEXT_FILE" ]]; then
  if [[ -d "$CONTEXT_FILE" ]]; then
    MD_FILES=$(find "$CONTEXT_FILE" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
    if [[ -n "$MD_FILES" ]]; then
      FILE_LIST=$(echo "$MD_FILES" | sed 's/^/  /')
      CONTEXT_INSTRUCTION="

IMPORTANT: Read the context files in this directory for background research and data:
$FILE_LIST
Use their content as input — competitors, tech stack, market data, pain points, etc."
    fi
  elif [[ -f "$CONTEXT_FILE" ]]; then
    CONTEXT_INSTRUCTION="

IMPORTANT: Read the context file first for background research and data:
  $CONTEXT_FILE
Use its content as input — competitors, tech stack, market data, pain points, etc."
  fi
fi

# --- Create state file (skip if already exists from outer invocation) ---
RESEARCH_DONE="false"
VALIDATE_DONE="false"
if [[ "$START_FROM" == "validate" ]]; then
  RESEARCH_DONE="true"
fi

CONTEXT_FILE_YAML="context_file: \"\""
if [[ -n "$CONTEXT_FILE" ]]; then
  CONTEXT_FILE_YAML="context_file: \"$CONTEXT_FILE\""
fi

if [[ ! -f "$STATE_FILE" ]]; then
cat > "$STATE_FILE" << STATEEOF
---
active: true
mode: bighead
pipeline: research
iteration: 0
max_iterations: $MAX_ITERATIONS
idea: "$IDEA"
project: "$PROJECT"
project_root: "$PROJECT_ROOT"
stack: ""
$CONTEXT_FILE_YAML
log_file: "$LOG_FILE"
signals: "<solo:done/> and <solo:redo/>"
started_at: "$STARTED_AT"
stages:
  - id: research
    skill: "/solo:research"
    args: "\"$IDEA\""
    check: "$RESEARCH_CHECK"
    done: $RESEARCH_DONE
  - id: validate
    skill: "/solo:validate"
    args: "\"$IDEA\""
    check: "$PRD_CHECK"
    done: $VALIDATE_DONE
---

Solo Pipeline: Research -> Validate
STATEEOF
fi

# --- Stages display ---
STAGES_DISPLAY=""
for i in "${!STAGE_IDS[@]}"; do
  [[ -n "$STAGES_DISPLAY" ]] && STAGES_DISPLAY="$STAGES_DISPLAY -> "
  STAGES_DISPLAY="${STAGES_DISPLAY}/${STAGE_IDS[$i]}"
done

echo ""
echo "Solo Pipeline: Research"
echo "  Idea:    $IDEA"
echo "  Project: $PROJECT"
if [[ -n "$CONTEXT_FILE" ]]; then
  if [[ -d "$CONTEXT_FILE" ]]; then
    echo "  Dir:     $CONTEXT_FILE"
  else
    echo "  File:    $CONTEXT_FILE"
  fi
fi
echo "  Stages:  $STAGES_DISPLAY"
echo "  Max:     $MAX_ITERATIONS iterations"
echo "  State:   $STATE_FILE"
echo "  Log:     $LOG_FILE"
echo ""

# --- Launch in tmux: re-exec self inside work pane ---
if [[ "$NO_DASHBOARD" == "false" ]] && command -v tmux &>/dev/null; then
  "$SCRIPT_DIR/solo-dashboard.sh" create "$PROJECT"

  # Build re-exec command with --no-dashboard
  REEXEC="cd $(printf '%q' "$LAUNCH_DIR") && $(printf '%q' "$SCRIPT_DIR/$(basename "$0")")"
  for arg in "${SAVED_ARGS[@]}"; do
    REEXEC+=" $(printf '%q' "$arg")"
  done
  REEXEC+=" --no-dashboard"

  # Clear all panes on re-run (removes old scroll buffer)
  for pane_id in $(tmux list-panes -t "solo-$PROJECT" -F '#{pane_id}'); do
    tmux send-keys -t "$pane_id" C-c 2>/dev/null || true
    tmux send-keys -t "$pane_id" "clear" C-m 2>/dev/null || true
  done
  sleep 0.5

  # Restart log tail and status watch in their panes
  PANE_IDS=($(tmux list-panes -t "solo-$PROJECT" -F '#{pane_id}'))
  WORK_PANE="${PANE_IDS[0]}"
  if [[ ${#PANE_IDS[@]} -ge 2 ]]; then
    LOG_PANE="${PANE_IDS[1]}"
    tmux send-keys -t "$LOG_PANE" "tail -f '$LOG_FILE'" C-m
  fi
  if [[ ${#PANE_IDS[@]} -ge 3 ]]; then
    STATUS_PANE="${PANE_IDS[2]}"
    STATUS_CMD="$SCRIPT_DIR/solo-pipeline-status.sh $PROJECT"
    if command -v watch &>/dev/null; then
      tmux send-keys -t "$STATUS_PANE" "watch -n2 -c '$STATUS_CMD'" C-m
    else
      tmux send-keys -t "$STATUS_PANE" "while true; do clear; $STATUS_CMD; sleep 2; done" C-m
    fi
  fi

  # Send pipeline command into work pane
  tmux send-keys -t "$WORK_PANE" "$REEXEC" C-m

  echo ""
  echo "Pipeline running in tmux session: solo-$PROJECT"
  echo "  Attach: tmux attach -t solo-$PROJECT"
  echo "  Cancel: rm $STATE_FILE"
  echo ""

  # Attach to dashboard
  sleep 1
  "$SCRIPT_DIR/solo-dashboard.sh" attach "$PROJECT"
  exit 0
fi

# =============================================
# Main loop: run claude --print for each stage
# =============================================
log_entry "START" "$PROJECT | stages: $STAGES_DISPLAY | max: $MAX_ITERATIONS"

for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do
  # Find next incomplete stage
  CURRENT_STAGE=-1
  for i in "${!STAGE_IDS[@]}"; do
    CHECK="${STAGE_CHECKS[$i]}"
    if [[ "$CHECK" == *"*"* ]]; then
      # Glob check
      if ! compgen -G "$CHECK" > /dev/null 2>&1; then
        CURRENT_STAGE=$i
        break
      fi
    else
      if [[ ! -f "$CHECK" ]]; then
        CURRENT_STAGE=$i
        break
      fi
    fi
  done

  # All stages complete
  if [[ $CURRENT_STAGE -lt 0 ]]; then
    log_entry "DONE" "All stages complete!"
    break
  fi

  STAGE_ID="${STAGE_IDS[$CURRENT_STAGE]}"
  SKILL="${STAGE_SKILLS[$CURRENT_STAGE]}"
  ARGS="${STAGE_ARGS[$CURRENT_STAGE]}"
  CHECK="${STAGE_CHECKS[$CURRENT_STAGE]}"
  STAGE_NUM=$((CURRENT_STAGE + 1))

  # Update iteration in state file
  TEMP_FILE="${STATE_FILE}.tmp.$$"
  sed "s/^iteration: .*/iteration: $ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$STATE_FILE"

  echo ""
  echo "==============================================================="
  log_entry "STAGE" "iter $ITERATION/$MAX_ITERATIONS | stage $STAGE_NUM/$TOTAL_STAGES: $STAGE_ID"
  echo "==============================================================="

  # Load running docs (progress from previous iterations)
  PROGRESS_FILE="$PROJECT_ROOT/.solo/pipelines/progress.md"
  PROGRESS_CONTEXT=""
  if [[ -f "$PROGRESS_FILE" ]]; then
    PROGRESS_CONTEXT="

## Previous iterations (running docs)
$(tail -50 "$PROGRESS_FILE")

Use this context to understand what was already done. Do NOT repeat completed work."
  fi

  # Build prompt
  PROMPT="$SKILL $ARGS$CONTEXT_INSTRUCTION$PROGRESS_CONTEXT

This is stage $STAGE_NUM/$TOTAL_STAGES ($STAGE_ID) of the research pipeline (project: $PROJECT).
When done with this stage, output exactly: <solo:done/>
If the stage needs to go back (e.g. review found issues), output exactly: <solo:redo/>"

  # Run Claude Code (stream-json for real-time tool visibility)
  log_entry "INVOKE" "$SKILL $ARGS"
  OUTFILE=$(mktemp /tmp/solo-claude-XXXXXX)
  MCP_FLAG=""
  if [[ -f "$HOME/.mcp.json" ]]; then
    MCP_FLAG="--mcp-config $HOME/.mcp.json"
  fi
  claude --dangerously-skip-permissions --verbose --print \
    $MCP_FLAG --output-format stream-json -p "$PROMPT" 2>&1 \
    | python3 "$SCRIPT_DIR/solo-stream-fmt.py" \
    | tee "$OUTFILE" || true
  OUTPUT=$(cat "$OUTFILE")

  # --- Per-iteration log (in project .solo/) ---
  ITER_DIR="$PROJECT_ROOT/.solo/pipelines"
  mkdir -p "$ITER_DIR"
  cp "$OUTFILE" "$ITER_DIR/iter-$(printf '%03d' $ITERATION)-${STAGE_ID}.log"

  # --- Running docs (progress.md) ---
  PROGRESS_FILE="$ITER_DIR/progress.md"
  COMMIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "none")
  STAGE_RESULT="continuing"
  if [[ -f "$CHECK" ]]; then
    STAGE_RESULT="stage complete"
  fi
  LAST_LINES=$(grep -v '^$' "$OUTFILE" | tail -5 | sed 's/^/  > /')
  cat >> "$PROGRESS_FILE" << PROGRESSEOF

## Iteration $ITERATION — $STAGE_ID ($(date +"%Y-%m-%d %H:%M"))
- **Stage:** $STAGE_ID ($STAGE_NUM/$TOTAL_STAGES)
- **Commit:** $COMMIT_SHA
- **Result:** $STAGE_RESULT
- **Last 5 lines:**
$LAST_LINES

PROGRESSEOF
  log_entry "ITER" "saved iter-$(printf '%03d' $ITERATION)-${STAGE_ID}.log | commit: $COMMIT_SHA | result: $STAGE_RESULT"

  rm -f "$OUTFILE"

  # Check output file
  if [[ -f "$CHECK" ]]; then
    log_entry "CHECK" "$STAGE_ID | $CHECK -> FOUND"
  else
    log_entry "CHECK" "$STAGE_ID | $CHECK -> NOT FOUND"
  fi

  # Check if all stages are complete (early exit)
  ALL_DONE=true
  for j in "${!STAGE_IDS[@]}"; do
    C="${STAGE_CHECKS[$j]}"
    if [[ "$C" == *"*"* ]]; then
      compgen -G "$C" > /dev/null 2>&1 || { ALL_DONE=false; break; }
    else
      [[ -f "$C" ]] || { ALL_DONE=false; break; }
    fi
  done
  if [[ "$ALL_DONE" == "true" ]]; then
    log_entry "DONE" "All stages complete!"
    break
  fi

  sleep 2
done

# --- Calculate duration ---
END_TIME=$(date +%s)
if [[ "$OSTYPE" == "darwin"* ]]; then
  START_EPOCH=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED_AT" +%s 2>/dev/null || echo "0")
else
  START_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || echo "0")
fi
if [[ "$START_EPOCH" != "0" ]]; then
  DURATION=$(( (END_TIME - START_EPOCH) / 60 ))
  log_entry "FINISH" "Duration: ${DURATION}m"
else
  log_entry "FINISH" "Duration: unknown"
fi

# --- Final status ---
ALL_COMPLETE=true
for i in "${!STAGE_IDS[@]}"; do
  if [[ ! -f "${STAGE_CHECKS[$i]}" ]]; then
    ALL_COMPLETE=false
    break
  fi
done

if [[ "$ALL_COMPLETE" == "true" ]]; then
  echo ""
  echo "Pipeline complete! All stages done."
  log_entry "DONE" "Pipeline complete!"
else
  echo ""
  echo "Pipeline reached max iterations ($MAX_ITERATIONS) without completing all stages."
  log_entry "MAXITER" "Reached max iterations ($MAX_ITERATIONS)"
fi

# Cleanup state file
rm -f "$STATE_FILE"
