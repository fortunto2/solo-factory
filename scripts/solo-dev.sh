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
#   solo-dev.sh "project-name" "stack" [--feature "desc"] [--file path] [--from stage] [--max N] [--max-hours H] [--no-dashboard] [--no-retro] [--no-autoplan]
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
source "$SCRIPT_DIR/solo-lib.sh"
LAUNCH_DIR="$(pwd)"

# Save original args for tmux re-exec
SAVED_ARGS=("$@")

# --- Parse arguments (solo-lib.sh: parse_args) ---
parse_args "$@" || exit 1

# Resolve context file/dir to absolute path (filesystem-dependent, stays here)
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
# Preserve original start epoch across re-execs
STARTED_EPOCH=${SOLO_PIPELINE_START_EPOCH:-$(date +%s)}
export SOLO_PIPELINE_START_EPOCH="$STARTED_EPOCH"
MAX_SECONDS=$((MAX_HOURS * 3600))

# Rotate log on fresh run (not on --no-dashboard re-exec)
if [[ "$NO_DASHBOARD" == "false" ]] && [[ -s "$LOG_FILE" ]]; then
  mv "$LOG_FILE" "${LOG_FILE%.log}-$(date +%Y%m%d-%H%M%S).log" 2>/dev/null || true
fi

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

# --- Run retro + codex for completed plan ---
# Called after each plan cycle (build→deploy→review) completes
# Logs saved per-plan: .solo/pipelines/retro-{plan-name}.log
run_plan_retro() {
  [[ "$SKIP_RETRO" == "true" ]] && return

  local ACTIVE_PLAN_DIR PLAN_NAME RETRO_LOG CODEX_LOG RETRO_FLAGS RETRO_MCP_FLAGS
  local PIPELINES_LOG_DIR="$PROJECT_ROOT/.solo/pipelines"
  ACTIVE_PLAN_DIR=$(find "$PLAN_CHECK" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)
  PLAN_NAME=""
  [[ -n "$ACTIVE_PLAN_DIR" ]] && PLAN_NAME=$(basename "$ACTIVE_PLAN_DIR")

  log_entry "RETRO" "Running retro for plan: ${PLAN_NAME:-current}..."

  # Per-plan log files (not overwritten between plans)
  RETRO_LOG="$PIPELINES_LOG_DIR/retro-${PLAN_NAME:-post}.log"
  CODEX_LOG="$PIPELINES_LOG_DIR/codex-${PLAN_NAME:-post}.log"

  RETRO_FLAGS="--dangerously-skip-permissions --verbose --print --output-format stream-json"
  RETRO_MCP_FLAGS=""
  [[ -f "$HOME/.mcp.json" ]] && RETRO_MCP_FLAGS="$RETRO_MCP_FLAGS --mcp-config $HOME/.mcp.json"
  [[ -f "$PROJECT_ROOT/.mcp.json" ]] && RETRO_MCP_FLAGS="$RETRO_MCP_FLAGS --mcp-config $PROJECT_ROOT/.mcp.json"

  (cd "$PROJECT_ROOT" && claude $RETRO_FLAGS $RETRO_MCP_FLAGS -p "/solo:retro $PROJECT_NAME") \
    2>&1 | python3 "$SCRIPT_DIR/solo-stream-fmt.py" | tee "$RETRO_LOG" || true

  log_entry "RETRO" "Retro complete — see $RETRO_LOG"

  # Codex factory critique (second critic)
  if command -v codex &>/dev/null; then
    log_entry "RETRO" "Running Codex factory critique..."
    "$SCRIPT_DIR/solo-codex.sh" "$PROJECT_NAME" --factory 2>&1 \
      | tee "$CODEX_LOG" || true
    log_entry "RETRO" "Codex factory critique complete"
  fi
}

# --- Archive all active plans to plan-done ---
archive_active_plans() {
  [[ ! -d "$PLAN_CHECK" ]] && return
  mkdir -p "$PLAN_DONE_DIR"
  for completed in "$PLAN_CHECK"/*/; do
    [[ -d "$completed" ]] || continue
    local COMPLETED_NAME
    COMPLETED_NAME=$(basename "$completed")
    log_entry "ARCHIVE" "Archiving: $COMPLETED_NAME → docs/plan-done/"
    mv "$completed" "$PLAN_DONE_DIR/$COMPLETED_NAME"
  done
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
echo "  Max:     $MAX_ITERATIONS iterations / ${MAX_HOURS}h timeout"
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

# --- Pre-flight: verify all required skills exist ---
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_MISSING=false
for i in "${!STAGE_IDS[@]}"; do
  STAGE="${STAGE_IDS[$i]}"
  SKILL_FILE="$PLUGIN_DIR/skills/$STAGE/SKILL.md"
  if [[ ! -f "$SKILL_FILE" ]]; then
    log_entry "PREFLIGHT" "MISSING skill file: $SKILL_FILE"
    SKILLS_MISSING=true
  elif ! grep -q "^name: solo-$STAGE" "$SKILL_FILE"; then
    ACTUAL_NAME=$(grep "^name:" "$SKILL_FILE" | head -1)
    log_entry "PREFLIGHT" "WRONG name in $STAGE/SKILL.md — got '$ACTUAL_NAME', expected 'name: solo-$STAGE'"
    SKILLS_MISSING=true
  fi
done
if [[ "$SKILLS_MISSING" == "true" ]]; then
  log_entry "ABORT" "Pre-flight failed — fix skill files and retry"
  echo "ERROR: Required skills not found or misconfigured. Check $PLUGIN_DIR/skills/"
  exit 1
fi

# --- Circuit breaker: track consecutive identical failures ---
CONSECUTIVE_FAILS=0
LAST_FAIL_FINGERPRINT=""
CIRCUIT_BREAKER_LIMIT=3

# --- Redo cycle counter: limit review→build loops per plan ---
REDO_COUNT=0
REDO_MAX=2  # max redo cycles per plan (review→build→deploy→review counts as 1)

# --- Rate limit: exponential backoff ---
RATE_LIMIT_BACKOFF=60        # start at 60s
RATE_LIMIT_MAX_BACKOFF=3600  # cap at 1 hour
RATE_LIMIT_RETRIES=0
RATE_LIMIT_MAX_RETRIES=10    # give up after 10 consecutive rate limits

for ITERATION in $(seq 1 "$MAX_ITERATIONS"); do
  # --- Check control file (pause/stop/skip) ---
  check_control

  # --- Global timeout ---
  if check_timeout; then
    break
  fi

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

  # All stages complete — retro + archive + cycle to next plan
  if [[ $CURRENT_STAGE -lt 0 ]]; then
    run_plan_retro
    if cycle_next_plan; then
      REDO_COUNT=0  # reset redo counter for new plan
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
Use git log/diff actively for context — commit history is the source of truth for what was built, changed, and deployed.
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
  CLAUDE_EXIT=0
  (cd "$CLAUDE_CWD" && claude $CLAUDE_FLAGS -p "$PROMPT" 2>&1) \
    | python3 "$SCRIPT_DIR/solo-stream-fmt.py" \
    | tee "$OUTFILE" || CLAUDE_EXIT=$?
  OUTPUT=$(cat "$OUTFILE")

  # --- Rate limit detection + exponential backoff ---
  # Note: check_rate_limit returns 1 for "not rate limited" — use || to avoid set -e exit
  RATE_LIMIT_STATUS=0
  check_rate_limit "$OUTFILE" "$CLAUDE_EXIT" || RATE_LIMIT_STATUS=$?
  if [[ $RATE_LIMIT_STATUS -eq 2 ]]; then
    rm -f "$OUTFILE"
    break
  elif [[ $RATE_LIMIT_STATUS -eq 0 ]]; then
    sleep "$RATE_LIMIT_BACKOFF"
    rm -f "$OUTFILE"
    continue  # retry same stage, don't count toward circuit breaker
  fi

  # --- Signal-based markers (solo-lib.sh: handle_signals) ---
  handle_signals "$OUTFILE" "$CHECK"

  if [[ "$HAS_REDO" == "true" ]]; then
    # If build is not in current stages (e.g. --from deploy), re-exec from build
    # Skip re-exec if redo limit was reached (markers were force-created above)
    BUILD_IN_STAGES=false
    for s in "${STAGE_IDS[@]}"; do
      [[ "$s" == "build" ]] && BUILD_IN_STAGES=true
    done

    if [[ "$BUILD_IN_STAGES" != "true" ]] && [[ $REDO_COUNT -le $REDO_MAX ]]; then
      REMAINING=$((MAX_ITERATIONS - ITERATION))
      log_entry "SIGNAL" "<solo:redo/> → build not in stages, re-exec from build ($REMAINING iters left)"
      # Save iter log before re-exec
      cp "$OUTFILE" "$ITER_DIR/iter-$(printf '%03d' $ITERATION)-${STAGE_ID}.log" 2>/dev/null || true
      rm -f "$STATE_FILE" "$OUTFILE"
      REEXEC_ARGS=("$PROJECT_NAME" "$STACK" --from build --no-dashboard --max "$REMAINING" --max-hours "$MAX_HOURS")
      [[ -n "$FEATURE" ]] && REEXEC_ARGS+=(--feature "$FEATURE")
      [[ -n "$CONTEXT_FILE" ]] && REEXEC_ARGS+=(--file "$CONTEXT_FILE")
      [[ "$SKIP_RETRO" == "true" ]] && REEXEC_ARGS+=(--no-retro)
      [[ "$SKIP_AUTOPLAN" == "true" ]] && REEXEC_ARGS+=(--no-autoplan)
      exec "$SCRIPT_DIR/solo-dev.sh" "${REEXEC_ARGS[@]}"
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

  # --- Circuit breaker: abort after N consecutive identical failures ---
  if ! check_circuit_breaker "$STAGE_ID" "$OUTFILE" "$STAGE_RESULT"; then
    rm -f "$OUTFILE"
    break
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
    run_plan_retro
    if cycle_next_plan; then
      REDO_COUNT=0  # reset redo counter for new plan
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

# --- Post-completion: archive + auto-plan ---
# Note: retro already ran in the main loop (before cycle_next_plan or break)
if [[ "$ALL_COMPLETE" == "true" ]]; then

  # Step 1: Archive completed plans (they stay in docs/plan/ when queue is empty)
  archive_active_plans

  # Step 2: Auto-plan from backlog
  if [[ "$SKIP_AUTOPLAN" != "true" ]]; then
    # Build context from backlog + completed plans + PRD
    AUTOPLAN_CONTEXT=""

    # Collect backlog files
    for f in "$PROJECT_ROOT"/docs/backlog*.md; do
      [[ -f "$f" ]] && AUTOPLAN_CONTEXT="$AUTOPLAN_CONTEXT
Read $(basename "$f") for backlog items."
    done

    # Reference completed plans for continuity
    if [[ -d "$PLAN_DONE_DIR" ]]; then
      DONE_PLANS=$(ls -d "$PLAN_DONE_DIR"/*/ 2>/dev/null | xargs -I{} basename {} | tr '\n' ', ')
      [[ -n "$DONE_PLANS" ]] && AUTOPLAN_CONTEXT="$AUTOPLAN_CONTEXT
Completed plans (already done, do NOT repeat): $DONE_PLANS"
    fi

    # Reference retro report if just generated
    LATEST_RETRO=$(find "$PROJECT_ROOT/docs/retro" -name "*.md" -type f 2>/dev/null | sort | tail -1 || true)
    [[ -n "$LATEST_RETRO" ]] && AUTOPLAN_CONTEXT="$AUTOPLAN_CONTEXT
Read $(basename "$LATEST_RETRO") for retro recommendations."

    # Check if there's backlog content to plan from
    BACKLOG_EXISTS=false
    for f in "$PROJECT_ROOT"/docs/backlog*.md "$PROJECT_ROOT"/docs/prd.md "$PROJECT_ROOT"/docs/roadmap*.md; do
      [[ -f "$f" ]] && { BACKLOG_EXISTS=true; break; }
    done

    if [[ "$BACKLOG_EXISTS" == "true" ]]; then
      log_entry "POST" "Running auto-plan from backlog..."

      AUTOPLAN_PROMPT="/solo:plan Pick the highest-priority unimplemented item from the project backlog (docs/backlog*.md, docs/prd.md, docs/roadmap*.md). Review completed plans in docs/plan-done/ AND git log (commit history is the source of truth) to avoid repeating work. Read the latest retro in docs/retro/ for process recommendations.$AUTOPLAN_CONTEXT"

      PLAN_LOG="$PROJECT_ROOT/.solo/pipelines/autoplan-$(date +%Y%m%d-%H%M%S).log"

      AUTOPLAN_FLAGS="--dangerously-skip-permissions --verbose --print --output-format stream-json"
      AUTOPLAN_MCP=""
      [[ -f "$HOME/.mcp.json" ]] && AUTOPLAN_MCP="$AUTOPLAN_MCP --mcp-config $HOME/.mcp.json"
      [[ -f "$PROJECT_ROOT/.mcp.json" ]] && AUTOPLAN_MCP="$AUTOPLAN_MCP --mcp-config $PROJECT_ROOT/.mcp.json"

      (cd "$PROJECT_ROOT" && claude $AUTOPLAN_FLAGS $AUTOPLAN_MCP -p "$AUTOPLAN_PROMPT") \
        2>&1 | python3 "$SCRIPT_DIR/solo-stream-fmt.py" | tee "$PLAN_LOG" || true

      log_entry "POST" "Auto-plan complete — see $PLAN_LOG"

      # Check if a new plan was created → restart build->review cycle
      NEW_PLAN=$(find "$PLAN_CHECK" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)
      if [[ -n "$NEW_PLAN" ]]; then
        # Check global timeout before re-exec
        ELAPSED=$(( $(date +%s) - STARTED_EPOCH ))
        if [[ $ELAPSED -ge $MAX_SECONDS ]]; then
          ELAPSED_H=$(( ELAPSED / 3600 ))
          log_entry "TIMEOUT" "Global timeout (${ELAPSED_H}h/${MAX_HOURS}h) — skipping re-exec"
        else
        NEW_PLAN_NAME=$(basename "$NEW_PLAN")
        log_entry "POST" "New plan created: $NEW_PLAN_NAME — restarting build→deploy→review"

        # Reset state markers for new cycle
        rm -f "$STATES_DIR/build" "$STATES_DIR/deploy" "$STATES_DIR/review"

        # Truncate progress.md for fresh cycle
        : > "$PROJECT_ROOT/.solo/pipelines/progress.md"

        # Build re-exec args: preserve --max, --feature, --file from original invocation
        REEXEC_ARGS=("$PROJECT_NAME" "$STACK" --from build --no-dashboard --max-hours "$MAX_HOURS")
        [[ -n "$FEATURE" ]] && REEXEC_ARGS+=(--feature "$FEATURE")
        [[ -n "$CONTEXT_FILE" ]] && REEXEC_ARGS+=(--file "$CONTEXT_FILE")
        [[ "$MAX_ITERATIONS" != "15" ]] && REEXEC_ARGS+=(--max "$MAX_ITERATIONS")
        [[ "$SKIP_RETRO" == "true" ]] && REEXEC_ARGS+=(--no-retro)
        [[ "$SKIP_AUTOPLAN" == "true" ]] && REEXEC_ARGS+=(--no-autoplan)

        # Re-exec pipeline from build stage (plan already exists)
        exec "$SCRIPT_DIR/solo-dev.sh" "${REEXEC_ARGS[@]}"
        fi  # timeout check
      else
        log_entry "POST" "No new plan created — pipeline fully done"
      fi
    else
      log_entry "POST" "No backlog/roadmap found — skipping auto-plan"
    fi
  fi
fi

# Cleanup state file
rm -f "$STATE_FILE"
