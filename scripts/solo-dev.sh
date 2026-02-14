#!/bin/bash

# Solo Dev Pipeline
# Chains: /scaffold -> /setup -> /plan -> /build -> /deploy -> /review
# Runs claude --dangerously-skip-permissions --print in a loop (Ralph-style)
#
# Plan Queue: If docs/plan-queue/ contains plan directories, after each
# build→review cycle the next plan is auto-activated and the cycle repeats.
# Completed plans are archived to docs/plan-done/.
#
# Usage:
#   solo-dev.sh "project-name" "stack" [--feature "desc"] [--file path] [--from stage] [--max N] [--no-dashboard]
#
# Examples:
#   solo-dev.sh "lovon" "nextjs-supabase"
#   solo-dev.sh "lovon" "nextjs-supabase" --feature "user onboarding flow"
#   solo-dev.sh "lovon" "ios-swift" --file docs/design-notes.md
#   solo-dev.sh "lovon" "ios-swift" --file 4-opportunities/lovon/   # directory
#   solo-dev.sh "lovon" "ios-swift" --from setup                    # skip scaffold
#   solo-dev.sh "lovon" "ios-swift" --from plan --feature "auth"    # skip scaffold+setup
#   solo-dev.sh "lovon" "ios-swift" --no-dashboard                  # skip tmux

set -euo pipefail

PIPELINES_DIR="$HOME/.solo/pipelines"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCH_DIR="$(pwd)"

# Save original args for tmux re-exec
SAVED_ARGS=("$@")

# --- Parse arguments ---
PROJECT_NAME=""
STACK=""
FEATURE=""
CONTEXT_FILE=""
START_FROM=""
MAX_ITERATIONS=15
NO_DASHBOARD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature) FEATURE="$2"; shift 2 ;;
    --file) CONTEXT_FILE="$2"; shift 2 ;;
    --from) START_FROM="$2"; shift 2 ;;
    --max) MAX_ITERATIONS="$2"; shift 2 ;;
    --no-dashboard) NO_DASHBOARD=true; shift ;;
    *)
      if [[ -z "$PROJECT_NAME" ]]; then
        PROJECT_NAME="$1"
      elif [[ -z "$STACK" ]]; then
        STACK="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$PROJECT_NAME" ]] || [[ -z "$STACK" ]]; then
  echo "Usage: solo-dev.sh \"project\" \"stack\" [--feature \"desc\"] [--file path|dir] [--from stage] [--max N] [--no-dashboard]"
  echo ""
  echo "Stages: scaffold, setup, plan, build, deploy, review"
  echo "  --from setup       # skip scaffold"
  echo "  --from plan        # skip scaffold + setup"
  echo "  --from build       # skip scaffold + setup + plan"
  echo "  --from deploy      # skip to deploy"
  echo "  --from review      # skip to review"
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
VALID_STAGES="scaffold setup plan build deploy review"
if [[ -n "$START_FROM" ]]; then
  if ! echo "$VALID_STAGES" | grep -qw "$START_FROM"; then
    echo "Error: Unknown stage '$START_FROM'. Valid: $VALID_STAGES"
    exit 1
  fi
fi

# --- Determine check paths (absolute) ---
ACTIVE_DIR="$HOME/startups/active/$PROJECT_NAME"
PROJECT_ROOT="$ACTIVE_DIR"
SCAFFOLD_CHECK="$ACTIVE_DIR/CLAUDE.md"
SETUP_CHECK="$ACTIVE_DIR/docs/workflow.md"
PLAN_CHECK="$ACTIVE_DIR/docs/plan"
PLAN_QUEUE_DIR="$ACTIVE_DIR/docs/plan-queue"
PLAN_DONE_DIR="$ACTIVE_DIR/docs/plan-done"
STATES_DIR="$ACTIVE_DIR/.solo/states"
BUILD_CHECK="$STATES_DIR/build"
DEPLOY_CHECK="$STATES_DIR/deploy"
REVIEW_CHECK="$STATES_DIR/review"

# --- Pipeline control files (in project dir) ---
CONTROL_FILE="$ACTIVE_DIR/.solo/pipelines/control"
MSG_FILE="$ACTIVE_DIR/.solo/pipelines/messages"

# --- Visual testing detection (from stack YAML) ---
VISUAL_TYPE=""
BROWSER_AVAILABLE=false
SIMULATOR_AVAILABLE=false
EMULATOR_AVAILABLE=false

# Extract visual_testing.type from stack YAML
STACK_YAML=""
for search_dir in "$SCRIPT_DIR/../templates/stacks" "$LAUNCH_DIR/solo-factory/templates/stacks" "$LAUNCH_DIR/1-methodology/stacks"; do
  if [[ -f "$search_dir/${STACK}.yaml" ]]; then
    STACK_YAML="$search_dir/${STACK}.yaml"
    break
  fi
done

if [[ -n "$STACK_YAML" ]]; then
  VISUAL_TYPE=$(python3 -c "
import yaml, sys
with open('$STACK_YAML') as f:
    d = yaml.safe_load(f)
vt = d.get('visual_testing', {})
print(vt.get('type', '') if isinstance(vt, dict) else '')
" 2>/dev/null || true)
fi

# Check tool availability based on visual type
case "$VISUAL_TYPE" in
  browser)
    # Playwright MCP is available via ~/.mcp.json (passed as --mcp-config)
    # No Chrome binary check needed — Playwright manages its own browsers
    BROWSER_AVAILABLE=true
    ;;
  simulator)
    if command -v xcrun &>/dev/null && xcrun simctl list devices 2>/dev/null | grep -q "iPhone"; then
      SIMULATOR_AVAILABLE=true
    fi
    ;;
  emulator)
    if command -v emulator &>/dev/null && emulator -list-avds 2>/dev/null | grep -q "."; then
      EMULATOR_AVAILABLE=true
    fi
    ;;
esac

# --- State & log files ---
mkdir -p "$PIPELINES_DIR"
mkdir -p "$PROJECT_ROOT/.solo/pipelines"
mkdir -p "$STATES_DIR"
STATE_FILE="$PIPELINES_DIR/solo-pipeline-${PROJECT_NAME}.local.md"
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

# --- Pipeline control check ---
# Reads control file: stop, pause, skip. Called at top of each iteration.
SKIP_STAGE=false

check_control() {
  SKIP_STAGE=false
  [[ ! -f "$CONTROL_FILE" ]] && return
  local CMD
  CMD=$(head -1 "$CONTROL_FILE")
  case "$CMD" in
    stop)
      log_entry "CTRL" "Stop requested"
      rm -f "$CONTROL_FILE"
      rm -f "$STATE_FILE"
      exit 0
      ;;
    pause)
      log_entry "CTRL" "Paused — waiting for resume (rm $CONTROL_FILE)"
      while [[ -f "$CONTROL_FILE" ]]; do sleep 2; done
      log_entry "CTRL" "Resumed"
      ;;
    skip)
      log_entry "CTRL" "Skip stage requested"
      rm -f "$CONTROL_FILE"
      SKIP_STAGE=true
      ;;
  esac
}

# --- Plan queue cycling ---
# After build→review completes for one plan, activate next from queue
cycle_next_plan() {
  [[ ! -d "$PLAN_QUEUE_DIR" ]] && return 1

  # Find next queued plan (alphabetical order: 02-* before 03-*)
  NEXT_PLAN=$(find "$PLAN_QUEUE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)
  [[ -z "$NEXT_PLAN" ]] && return 1

  NEXT_PLAN_NAME=$(basename "$NEXT_PLAN")
  log_entry "QUEUE" "Next plan in queue: $NEXT_PLAN_NAME"

  # Archive completed plan(s) from docs/plan/ → docs/plan-done/
  mkdir -p "$PLAN_DONE_DIR"
  for completed in "$PLAN_CHECK"/*/; do
    [[ -d "$completed" ]] || continue
    COMPLETED_NAME=$(basename "$completed")
    log_entry "QUEUE" "Archiving: $COMPLETED_NAME → docs/plan-done/"
    mv "$completed" "$PLAN_DONE_DIR/$COMPLETED_NAME"
  done

  # Move next plan from queue to active
  log_entry "QUEUE" "Activating: $NEXT_PLAN_NAME → docs/plan/"
  mv "$NEXT_PLAN" "$PLAN_CHECK/$NEXT_PLAN_NAME"

  # Reset build/deploy/review markers for new cycle
  rm -f "$STATES_DIR/build" "$STATES_DIR/deploy" "$STATES_DIR/review"
  log_entry "QUEUE" "Reset state markers (build, deploy, review)"

  # Clean up empty queue dir
  rmdir "$PLAN_QUEUE_DIR" 2>/dev/null || true

  return 0
}

# --- Check for existing pipeline (skip on tmux re-exec) ---
if [[ -f "$STATE_FILE" ]] && [[ "$NO_DASHBOARD" == "false" ]]; then
  echo "Warning: Pipeline already exists for '$PROJECT_NAME'"
  echo "  State: $STATE_FILE"
  echo "  Delete it first to restart: rm $STATE_FILE"
  exit 1
fi

# --- Build stages array ---
declare -a STAGE_IDS STAGE_SKILLS STAGE_ARGS STAGE_CHECKS
IDX=0

# Determine which stages to include based on --from
INCLUDE=true
[[ -n "$START_FROM" ]] && INCLUDE=false

for stage in scaffold setup plan build deploy review; do
  [[ "$stage" == "$START_FROM" ]] && INCLUDE=true
  [[ "$INCLUDE" != "true" ]] && continue

  STAGE_IDS[$IDX]="$stage"

  case "$stage" in
    scaffold)
      STAGE_SKILLS[$IDX]="/solo:scaffold"
      STAGE_ARGS[$IDX]="$PROJECT_NAME $STACK"
      STAGE_CHECKS[$IDX]="$SCAFFOLD_CHECK"
      ;;
    setup)
      STAGE_SKILLS[$IDX]="/solo:setup"
      STAGE_ARGS[$IDX]=""
      STAGE_CHECKS[$IDX]="$SETUP_CHECK"
      ;;
    plan)
      STAGE_SKILLS[$IDX]="/solo:plan"
      STAGE_ARGS[$IDX]="${FEATURE:+\"$FEATURE\"}"
      STAGE_CHECKS[$IDX]="$PLAN_CHECK/*/*.md"
      ;;
    build)
      STAGE_SKILLS[$IDX]="/solo:build"
      STAGE_ARGS[$IDX]=""
      STAGE_CHECKS[$IDX]="$BUILD_CHECK"
      ;;
    deploy)
      STAGE_SKILLS[$IDX]="/solo:deploy"
      STAGE_ARGS[$IDX]=""
      STAGE_CHECKS[$IDX]="$DEPLOY_CHECK"
      ;;
    review)
      STAGE_SKILLS[$IDX]="/solo:review"
      STAGE_ARGS[$IDX]=""
      STAGE_CHECKS[$IDX]="$REVIEW_CHECK"
      ;;
  esac

  IDX=$((IDX + 1))
done

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
SCAFFOLD_DONE="false"; SETUP_DONE="false"; PLAN_DONE="false"; BUILD_DONE="false"; DEPLOY_DONE="false"; REVIEW_DONE="false"
case "$START_FROM" in
  setup)  SCAFFOLD_DONE="true" ;;
  plan)   SCAFFOLD_DONE="true"; SETUP_DONE="true" ;;
  build)  SCAFFOLD_DONE="true"; SETUP_DONE="true"; PLAN_DONE="true" ;;
  deploy) SCAFFOLD_DONE="true"; SETUP_DONE="true"; PLAN_DONE="true"; BUILD_DONE="true" ;;
  review) SCAFFOLD_DONE="true"; SETUP_DONE="true"; PLAN_DONE="true"; BUILD_DONE="true"; DEPLOY_DONE="true" ;;
esac

CONTEXT_FILE_YAML="context_file: \"\""
[[ -n "$CONTEXT_FILE" ]] && CONTEXT_FILE_YAML="context_file: \"$CONTEXT_FILE\""

SCAFFOLD_ARGS_STR="$PROJECT_NAME $STACK"
PLAN_ARGS_STR="${FEATURE:+\"$FEATURE\"}"

if [[ ! -f "$STATE_FILE" ]]; then
cat > "$STATE_FILE" << STATEEOF
---
active: true
mode: bighead
pipeline: dev
iteration: 0
max_iterations: $MAX_ITERATIONS
idea: "$FEATURE"
project: "$PROJECT_NAME"
project_root: "$PROJECT_ROOT"
stack: "$STACK"
$CONTEXT_FILE_YAML
log_file: "$LOG_FILE"
signals: "<solo:done/> and <solo:redo/>"
started_at: "$STARTED_AT"
stages:
  - id: scaffold
    skill: "/solo:scaffold"
    args: "$SCAFFOLD_ARGS_STR"
    check: "$SCAFFOLD_CHECK"
    done: $SCAFFOLD_DONE
  - id: setup
    skill: "/solo:setup"
    args: ""
    check: "$SETUP_CHECK"
    done: $SETUP_DONE
  - id: plan
    skill: "/solo:plan"
    args: "$PLAN_ARGS_STR"
    check: "$PLAN_CHECK/*/*.md"
    done: $PLAN_DONE
  - id: build
    skill: "/solo:build"
    args: ""
    check: "$BUILD_CHECK"
    done: $BUILD_DONE
  - id: deploy
    skill: "/solo:deploy"
    args: ""
    check: "$DEPLOY_CHECK"
    done: $DEPLOY_DONE
  - id: review
    skill: "/solo:review"
    args: ""
    check: "$REVIEW_CHECK"
    done: $REVIEW_DONE
---

Solo Pipeline: Scaffold -> Setup -> Plan -> Build -> Deploy -> Review
STATEEOF
fi

# --- Stages display ---
STAGES_DISPLAY=""
for i in "${!STAGE_IDS[@]}"; do
  [[ -n "$STAGES_DISPLAY" ]] && STAGES_DISPLAY="$STAGES_DISPLAY -> "
  STAGES_DISPLAY="${STAGES_DISPLAY}/${STAGE_IDS[$i]}"
done

echo ""
echo "Solo Pipeline: Dev"
echo "  Project: $PROJECT_NAME"
echo "  Stack:   $STACK"
[[ -n "$FEATURE" ]] && echo "  Feature: $FEATURE"
if [[ -n "$CONTEXT_FILE" ]]; then
  if [[ -d "$CONTEXT_FILE" ]]; then
    echo "  Dir:     $CONTEXT_FILE"
  else
    echo "  File:    $CONTEXT_FILE"
  fi
fi
echo "  Stages:  $STAGES_DISPLAY"
QUEUE_COUNT=0
if [[ -d "$PLAN_QUEUE_DIR" ]]; then
  QUEUE_COUNT=$(find "$PLAN_QUEUE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
fi
[[ "$QUEUE_COUNT" -gt 0 ]] && echo "  Queue:   $QUEUE_COUNT plans in docs/plan-queue/"
if [[ -n "$VISUAL_TYPE" ]]; then
  VT_STATUS="$VISUAL_TYPE"
  case "$VISUAL_TYPE" in
    browser)   [[ "$BROWSER_AVAILABLE" == "true" ]] && VT_STATUS="$VT_STATUS (playwright MCP)" || VT_STATUS="$VT_STATUS (no browser tools, skipping)" ;;
    simulator) [[ "$SIMULATOR_AVAILABLE" == "true" ]] && VT_STATUS="$VT_STATUS (ready)" || VT_STATUS="$VT_STATUS (no simulator, skipping)" ;;
    emulator)  [[ "$EMULATOR_AVAILABLE" == "true" ]] && VT_STATUS="$VT_STATUS (ready)" || VT_STATUS="$VT_STATUS (no emulator, skipping)" ;;
  esac
  echo "  Visual:  $VT_STATUS"
fi
echo "  Max:     $MAX_ITERATIONS iterations"
echo "  State:   $STATE_FILE"
echo "  Log:     $LOG_FILE"
echo ""

# --- Launch in tmux: re-exec self inside work pane ---
if [[ "$NO_DASHBOARD" == "false" ]] && command -v tmux &>/dev/null; then
  "$SCRIPT_DIR/solo-dashboard.sh" create "$PROJECT_NAME"

  # Build re-exec command with --no-dashboard
  REEXEC="cd $(printf '%q' "$LAUNCH_DIR") && $(printf '%q' "$SCRIPT_DIR/$(basename "$0")")"
  for arg in "${SAVED_ARGS[@]}"; do
    REEXEC+=" $(printf '%q' "$arg")"
  done
  REEXEC+=" --no-dashboard"

  # Clear all panes on re-run (removes old scroll buffer)
  for pane_id in $(tmux list-panes -t "solo-$PROJECT_NAME" -F '#{pane_id}'); do
    tmux send-keys -t "$pane_id" C-c 2>/dev/null || true
    tmux send-keys -t "$pane_id" "clear" C-m 2>/dev/null || true
  done
  sleep 0.5

  # Restart log tail and status watch in their panes
  PANE_IDS=($(tmux list-panes -t "solo-$PROJECT_NAME" -F '#{pane_id}'))
  WORK_PANE="${PANE_IDS[0]}"
  if [[ ${#PANE_IDS[@]} -ge 2 ]]; then
    LOG_PANE="${PANE_IDS[1]}"
    tmux send-keys -t "$LOG_PANE" "tail -f '$LOG_FILE'" C-m
  fi
  if [[ ${#PANE_IDS[@]} -ge 3 ]]; then
    STATUS_PANE="${PANE_IDS[2]}"
    STATUS_CMD="$SCRIPT_DIR/solo-pipeline-status.sh $PROJECT_NAME"
    if command -v watch &>/dev/null; then
      tmux send-keys -t "$STATUS_PANE" "watch -n2 -c '$STATUS_CMD'" C-m
    else
      tmux send-keys -t "$STATUS_PANE" "while true; do clear; $STATUS_CMD; sleep 2; done" C-m
    fi
  fi

  # Send pipeline command into work pane
  tmux send-keys -t "$WORK_PANE" "$REEXEC" C-m

  echo ""
  echo "Pipeline running in tmux session: solo-$PROJECT_NAME"
  echo "  Attach: tmux attach -t solo-$PROJECT_NAME"
  echo "  Cancel: rm $STATE_FILE"
  echo ""

  # Attach to dashboard
  sleep 1
  "$SCRIPT_DIR/solo-dashboard.sh" attach "$PROJECT_NAME"
  exit 0
fi

# =============================================
# Main loop: run claude --print for each stage
# =============================================
log_entry "START" "$PROJECT_NAME | stages: $STAGES_DISPLAY | max: $MAX_ITERATIONS"

# --- Circuit breaker: track consecutive failures for same stage ---
CONSECUTIVE_FAILS=0
LAST_FAIL_STAGE=""
CIRCUIT_BREAKER_LIMIT=5

for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do
  # --- Check control file (pause/stop/skip) ---
  check_control

  # Find next incomplete stage
  CURRENT_STAGE=-1
  for i in "${!STAGE_IDS[@]}"; do
    CHECK="${STAGE_CHECKS[$i]}"
    if [[ "$CHECK" == *"*"* ]]; then
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

  # All stages complete — try cycling to next plan from queue
  if [[ $CURRENT_STAGE -lt 0 ]]; then
    if cycle_next_plan; then
      log_entry "QUEUE" "Cycling to next plan — restarting build→review"
      continue
    fi
    log_entry "DONE" "All stages complete (no more plans in queue)"
    break
  fi

  STAGE_ID="${STAGE_IDS[$CURRENT_STAGE]}"
  SKILL="${STAGE_SKILLS[$CURRENT_STAGE]}"
  ARGS="${STAGE_ARGS[$CURRENT_STAGE]}"
  CHECK="${STAGE_CHECKS[$CURRENT_STAGE]}"
  STAGE_NUM=$((CURRENT_STAGE + 1))

  # Handle skip: create stage marker and move to next
  if [[ "$SKIP_STAGE" == "true" ]]; then
    log_entry "CTRL" "Skipping stage: $STAGE_ID"
    if [[ "$CHECK" != *"*"* ]]; then
      mkdir -p "$(dirname "$CHECK")"
      echo "Skipped: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$CHECK"
    fi
    continue
  fi

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
  PROMPT="$SKILL"
  [[ -n "$ARGS" ]] && PROMPT="$PROMPT $ARGS"

  # For build/review stages: inject active plan track ID so Claude finds the right plan
  if [[ "$STAGE_ID" == "build" ]] || [[ "$STAGE_ID" == "review" ]]; then
    ACTIVE_PLAN_DIR=$(find "$PLAN_CHECK" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)
    if [[ -n "$ACTIVE_PLAN_DIR" ]]; then
      TRACK_ID=$(basename "$ACTIVE_PLAN_DIR")
      PROMPT="$PROMPT $TRACK_ID"
      log_entry "PLAN" "Active plan track: $TRACK_ID"
    fi
  fi

  # --- Visual testing instructions (injected for build/review stages) ---
  VISUAL_INSTRUCTION=""
  if [[ "$STAGE_ID" == "build" ]] || [[ "$STAGE_ID" == "review" ]]; then
    case "$VISUAL_TYPE" in
      browser)
        if [[ "$BROWSER_AVAILABLE" == "true" ]]; then
          VISUAL_INSTRUCTION="

## Visual Testing (Playwright MCP)
You have Playwright browser tools available via MCP. After implementing changes or during review:
1. Start the dev server if not running
2. Use playwright MCP tools to navigate to the app URL
3. Take screenshots of key pages to verify visual output
4. Check for console errors or hydration mismatches
5. Test at mobile viewport (375px width) for responsive layout
If playwright tools fail or are unavailable — skip visual checks, do not block progress."
        fi
        ;;
      simulator)
        if [[ "$SIMULATOR_AVAILABLE" == "true" ]]; then
          VISUAL_INSTRUCTION="

## Visual Testing (iOS Simulator)
After implementing changes or during review:
1. Boot the iOS Simulator: xcrun simctl boot 'iPhone 16' 2>/dev/null || true
2. Build and install: xcodebuild -scheme {Name} -sdk iphonesimulator build
3. Install on simulator: xcrun simctl install booted {path-to-app}
4. Launch and take screenshot: xcrun simctl io booted screenshot /tmp/sim-screenshot.png
5. Check logs for crashes: xcrun simctl spawn booted log stream --style compact --timeout 10
If simulator is unavailable — skip visual checks, do not block progress."
        fi
        ;;
      emulator)
        if [[ "$EMULATOR_AVAILABLE" == "true" ]]; then
          VISUAL_INSTRUCTION="

## Visual Testing (Android Emulator)
After implementing changes or during review:
1. Start emulator if not running: emulator -avd \$(emulator -list-avds | head -1) -no-window -no-audio &
2. Wait for boot: adb wait-for-device && adb shell getprop sys.boot_completed | grep -q 1
3. Build and install: ./gradlew assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk
4. Take screenshot: adb exec-out screencap -p > /tmp/emu-screenshot.png
5. Check logcat for crashes: adb logcat '*:E' --format=time -d 2>&1 | tail -20
If emulator is unavailable — skip visual checks, do not block progress."
        fi
        ;;
    esac
  fi

  # --- Inject user messages (mid-pipeline) ---
  MSG_INSTRUCTION=""
  if [[ -f "$MSG_FILE" ]] && [[ -s "$MSG_FILE" ]]; then
    MSG_INSTRUCTION="

--- USER INSTRUCTIONS (mid-pipeline) ---
$(cat "$MSG_FILE")
---"
    rm -f "$MSG_FILE"
    log_entry "MSG" "Injected user message into prompt"
  fi

  PROMPT="$PROMPT$CONTEXT_INSTRUCTION$PROGRESS_CONTEXT$VISUAL_INSTRUCTION$MSG_INSTRUCTION

This is stage $STAGE_NUM/$TOTAL_STAGES ($STAGE_ID) of the dev pipeline (project: $PROJECT_NAME).
When done with this stage, output exactly: <solo:done/>
If the stage needs to go back (e.g. review found issues), output exactly: <solo:redo/>"

  # cd to project dir for stages that operate on the project (not scaffold)
  CLAUDE_CWD="$(pwd)"
  if [[ "$STAGE_ID" != "scaffold" ]] && [[ -d "$PROJECT_ROOT" ]]; then
    CLAUDE_CWD="$PROJECT_ROOT"
    log_entry "CWD" "$CLAUDE_CWD"
  fi

  # Run Claude Code (stream-json for real-time tool visibility)
  CLAUDE_FLAGS="--dangerously-skip-permissions --verbose --print --output-format stream-json"
  # Load MCP servers (global + project) so solograph tools are available
  if [[ -f "$HOME/.mcp.json" ]]; then
    CLAUDE_FLAGS="$CLAUDE_FLAGS --mcp-config $HOME/.mcp.json"
  fi
  if [[ -f "$CLAUDE_CWD/.mcp.json" ]]; then
    CLAUDE_FLAGS="$CLAUDE_FLAGS --mcp-config $CLAUDE_CWD/.mcp.json"
  fi
  # Playwright MCP is loaded via --mcp-config (no --chrome flag needed)
  if [[ "$BROWSER_AVAILABLE" == "true" ]] && [[ "$STAGE_ID" == "build" || "$STAGE_ID" == "review" ]]; then
    log_entry "PLAYWRIGHT" "Browser tools available via MCP for $STAGE_ID"
  fi
  log_entry "INVOKE" "$SKILL $ARGS"
  OUTFILE=$(mktemp /tmp/solo-claude-XXXXXX)
  (cd "$CLAUDE_CWD" && claude $CLAUDE_FLAGS -p "$PROMPT" 2>&1) \
    | python3 "$SCRIPT_DIR/solo-stream-fmt.py" \
    | tee "$OUTFILE" || true
  OUTPUT=$(cat "$OUTFILE")

  # --- Signal-based markers (2 universal signals, bash owns all files) ---
  # Claude outputs <solo:done/> or <solo:redo/>, bash creates/removes markers.
  # Claude does NOT need to know about marker file names or paths.
  if grep -q '<solo:done/>' "$OUTFILE" 2>/dev/null; then
    # Resolve CHECK path for glob patterns (e.g. .solo/states/build)
    if [[ "$CHECK" == *"*"* ]]; then
      CHECK_DIR=$(compgen -G "$(dirname "$CHECK")" 2>/dev/null | head -1)
      CHECK_FILE="$CHECK_DIR/$(basename "$CHECK")"
    else
      CHECK_FILE="$CHECK"
    fi
    if [[ -n "$CHECK_FILE" ]] && [[ "$CHECK_FILE" != *"*"* ]] && [[ ! -f "$CHECK_FILE" ]]; then
      log_entry "SIGNAL" "<solo:done/> → creating $(basename "$CHECK_FILE")"
      mkdir -p "$(dirname "$CHECK_FILE")"
      echo "Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$CHECK_FILE"
    fi
  fi

  if grep -q '<solo:redo/>' "$OUTFILE" 2>/dev/null; then
    # Go back: remove build marker (review → build loop)
    if [[ -f "$STATES_DIR/build" ]]; then
      log_entry "SIGNAL" "<solo:redo/> → removing .solo/states/build (back to build)"
      rm -f "$STATES_DIR/build"
    fi
  fi

  # --- Per-iteration log (in project .solo/) ---
  ITER_DIR="$PROJECT_ROOT/.solo/pipelines"
  mkdir -p "$ITER_DIR"
  cp "$OUTFILE" "$ITER_DIR/iter-$(printf '%03d' $ITERATION)-${STAGE_ID}.log"

  # --- Running docs (progress.md) ---
  PROGRESS_FILE="$ITER_DIR/progress.md"
  COMMIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "none")
  STAGE_RESULT="continuing"
  if [[ "$CHECK" == *"*"* ]]; then
    compgen -G "$CHECK" > /dev/null 2>&1 && STAGE_RESULT="stage complete"
  else
    [[ -f "$CHECK" ]] && STAGE_RESULT="stage complete"
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

  # --- Circuit breaker: abort after N consecutive failures for same stage ---
  if [[ "$STAGE_RESULT" == "continuing" ]]; then
    if [[ "$STAGE_ID" == "$LAST_FAIL_STAGE" ]]; then
      CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
    else
      CONSECUTIVE_FAILS=1
      LAST_FAIL_STAGE="$STAGE_ID"
    fi
    if [[ $CONSECUTIVE_FAILS -ge $CIRCUIT_BREAKER_LIMIT ]]; then
      log_entry "CIRCUIT" "Stage '$STAGE_ID' failed $CONSECUTIVE_FAILS times consecutively — aborting"
      rm -f "$OUTFILE"
      break
    fi
  else
    CONSECUTIVE_FAILS=0
    LAST_FAIL_STAGE=""
  fi

  rm -f "$OUTFILE"

  # Check output file
  if [[ "$CHECK" == *"*"* ]]; then
    if compgen -G "$CHECK" > /dev/null 2>&1; then
      log_entry "CHECK" "$STAGE_ID | $CHECK -> FOUND"
    else
      log_entry "CHECK" "$STAGE_ID | $CHECK -> NOT FOUND"
    fi
  else
    if [[ -f "$CHECK" ]]; then
      log_entry "CHECK" "$STAGE_ID | $CHECK -> FOUND"
    else
      log_entry "CHECK" "$STAGE_ID | $CHECK -> NOT FOUND"
    fi
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
    if cycle_next_plan; then
      log_entry "QUEUE" "Cycling to next plan — restarting build→review"
      continue
    fi
    log_entry "DONE" "All stages complete (no more plans in queue)"
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
  C="${STAGE_CHECKS[$i]}"
  if [[ "$C" == *"*"* ]]; then
    compgen -G "$C" > /dev/null 2>&1 || { ALL_COMPLETE=false; break; }
  else
    [[ -f "$C" ]] || { ALL_COMPLETE=false; break; }
  fi
done

if [[ "$ALL_COMPLETE" == "true" ]]; then
  echo ""
  # Count completed plans
  DONE_COUNT=0
  [[ -d "$PLAN_DONE_DIR" ]] && DONE_COUNT=$(find "$PLAN_DONE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  ACTIVE_COUNT=$(find "$PLAN_CHECK" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  TOTAL_PLANS=$((DONE_COUNT + ACTIVE_COUNT))
  if [[ "$TOTAL_PLANS" -gt 1 ]]; then
    echo "Pipeline complete! All $TOTAL_PLANS plans done (build→review each)."
    log_entry "DONE" "Pipeline complete! $TOTAL_PLANS plans cycled."
  else
    echo "Pipeline complete! All stages done."
    log_entry "DONE" "Pipeline complete!"
  fi
else
  echo ""
  echo "Pipeline reached max iterations ($MAX_ITERATIONS) without completing all stages."
  log_entry "MAXITER" "Reached max iterations ($MAX_ITERATIONS)"
fi

# Cleanup state file
rm -f "$STATE_FILE"
