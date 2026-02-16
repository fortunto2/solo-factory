#!/usr/bin/env bash
# test_helper.bash — shared setup for solo-dev.sh BATS tests
#
# Every .bats file should: load test_helper
# Then define its own setup() calling common_setup + any extras.

REAL_SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/../scripts" && pwd)"
SOLO_DEV="$REAL_SCRIPT_DIR/solo-dev.sh"

# Source the real library (no mirrors — tests run the actual code)
source "$REAL_SCRIPT_DIR/solo-lib.sh"

# --- Common setup: temp dirs + env vars ---
common_setup() {
  TEST_TMPDIR="$BATS_TEST_TMPDIR"

  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME/.solo/pipelines"

  export PROJECT_NAME="testproject"
  export STACK="nextjs-supabase"
  export PROJECT_ROOT="$TEST_TMPDIR/project"
  export ACTIVE_DIR="$PROJECT_ROOT"
  mkdir -p "$PROJECT_ROOT/.solo/pipelines"
  mkdir -p "$PROJECT_ROOT/.solo/states"
  mkdir -p "$PROJECT_ROOT/docs/plan"

  export SCAFFOLD_CHECK="$PROJECT_ROOT/CLAUDE.md"
  export SETUP_CHECK="$PROJECT_ROOT/docs/workflow.md"
  export PLAN_CHECK="$PROJECT_ROOT/docs/plan"
  export PLAN_QUEUE_DIR="$PROJECT_ROOT/docs/plan-queue"
  export PLAN_DONE_DIR="$PROJECT_ROOT/docs/plan-done"
  export STATES_DIR="$PROJECT_ROOT/.solo/states"
  export BUILD_CHECK="$STATES_DIR/build"
  export DEPLOY_CHECK="$STATES_DIR/deploy"
  export REVIEW_CHECK="$STATES_DIR/review"
  export CONTROL_FILE="$PROJECT_ROOT/.solo/pipelines/control"
  export MSG_FILE="$PROJECT_ROOT/.solo/pipelines/messages"
  export STATE_FILE="$HOME/.solo/pipelines/solo-pipeline-${PROJECT_NAME}.local.md"
  export LOG_FILE="$PROJECT_ROOT/.solo/pipelines/pipeline.log"
  touch "$LOG_FILE"

  export SKIP_STAGE=false
  export SKIP_RETRO=true
  export SKIP_AUTOPLAN=true
  export NO_DASHBOARD=true
  export MAX_HOURS=6
  export MAX_ITERATIONS=15
  export FEATURE=""
  export CONTEXT_FILE=""
  export START_FROM=""

  STARTED_EPOCH=$(date +%s)
  export STARTED_EPOCH
  export SOLO_PIPELINE_START_EPOCH="$STARTED_EPOCH"
  export MAX_SECONDS=$((MAX_HOURS * 3600))

  export CONSECUTIVE_FAILS=0
  export LAST_FAIL_FINGERPRINT=""
  export CIRCUIT_BREAKER_LIMIT=3

  export REDO_COUNT=0
  export REDO_MAX=2

  export RATE_LIMIT_BACKOFF=60
  export RATE_LIMIT_MAX_BACKOFF=3600
  export RATE_LIMIT_RETRIES=0
  export RATE_LIMIT_MAX_RETRIES=10

  # Mock binaries
  MOCK_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"

  printf '#!/bin/bash\necho "${MOCK_CLAUDE_OUTPUT:-<solo:done/>}"\n' > "$MOCK_BIN/claude"
  chmod +x "$MOCK_BIN/claude"

  printf '#!/bin/bash\nexit 0\n' > "$MOCK_BIN/codex"
  chmod +x "$MOCK_BIN/codex"

  cat > "$MOCK_BIN/python3" << 'MOCKEOF'
#!/bin/bash
if [[ "$*" == *"solo-stream-fmt"* ]]; then cat; else /usr/bin/python3 "$@"; fi
MOCKEOF
  chmod +x "$MOCK_BIN/python3"

  cat > "$MOCK_BIN/git" << 'MOCKEOF'
#!/bin/bash
if [[ "$1" == "rev-parse" ]]; then echo "abc1234"; else exit 0; fi
MOCKEOF
  chmod +x "$MOCK_BIN/git"
}

# --- Source functions from solo-dev.sh ---
# Extracts: check_control, cycle_next_plan, run_plan_retro, archive_active_plans
# (log_entry + handle_signals + check_* are in solo-lib.sh, already sourced above)
source_solo_functions() {
  eval "$(sed -n '/^check_control()/,/^}/p' "$SOLO_DEV")"
  eval "$(sed -n '/^cycle_next_plan()/,/^}/p' "$SOLO_DEV")"
  eval "$(sed -n '/^run_plan_retro()/,/^}/p' "$SOLO_DEV")"
  eval "$(sed -n '/^archive_active_plans()/,/^}/p' "$SOLO_DEV")"
}
