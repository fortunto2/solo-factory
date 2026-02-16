#!/usr/bin/env bats
# integration.bats — end-to-end tests running real solo-dev.sh with mock binaries
#
# Runs the actual script (main loop, stage progression, signal handling)
# with mocked claude/git/python3/sleep. Verifies markers, logs, flow control.

setup() {
  SOLO_DEV_REAL="$(cd "$BATS_TEST_DIRNAME/../scripts" && pwd)/solo-dev.sh"
  TEST_TMPDIR="$BATS_TEST_TMPDIR"
  export HOME="$TEST_TMPDIR/home"
  PROJECT="inttest"

  # Project root (matches $HOME/startups/active/$PROJECT)
  PROJECT_ROOT="$HOME/startups/active/$PROJECT"
  mkdir -p "$PROJECT_ROOT/.solo/states"
  mkdir -p "$PROJECT_ROOT/.solo/pipelines"
  mkdir -p "$PROJECT_ROOT/docs/plan"
  mkdir -p "$HOME/.solo/pipelines"

  # Pre-create scaffold + setup + plan checks (--from build skips them,
  # but they're needed for stage completion detection)
  echo "ok" > "$PROJECT_ROOT/CLAUDE.md"
  mkdir -p "$PROJECT_ROOT/docs"
  echo "ok" > "$PROJECT_ROOT/docs/workflow.md"
  mkdir -p "$PROJECT_ROOT/docs/plan/01-test"
  echo "# Plan" > "$PROJECT_ROOT/docs/plan/01-test/spec.md"

  # Mock binaries
  MOCK_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"

  # Mock sleep (instant)
  printf '#!/bin/bash\ntrue\n' > "$MOCK_BIN/sleep"
  chmod +x "$MOCK_BIN/sleep"

  # Mock git
  cat > "$MOCK_BIN/git" << 'EOF'
#!/bin/bash
case "$1" in
  rev-parse) echo "abc1234" ;;
  -C) echo "abc1234" ;;
  *) true ;;
esac
EOF
  chmod +x "$MOCK_BIN/git"

  # Mock tmux (unavailable — forces --no-dashboard path internally)
  printf '#!/bin/bash\nexit 127\n' > "$MOCK_BIN/tmux"
  chmod +x "$MOCK_BIN/tmux"

  # Mock python3 (pass-through for stream-fmt pipe)
  cat > "$MOCK_BIN/python3" << 'EOF'
#!/bin/bash
if [[ "$*" == *"solo-stream-fmt"* ]]; then cat; elif [[ "$*" == *"yaml"* ]]; then echo ""; else /usr/bin/python3 "$@"; fi
EOF
  chmod +x "$MOCK_BIN/python3"

  # Pre-flight checks $PLUGIN_DIR/skills/{stage}/SKILL.md
  # These exist in the real solo-factory, no mocking needed.

  # Default: claude outputs <solo:done/>
  MOCK_CLAUDE_SCRIPT='#!/bin/bash
echo "${MOCK_CLAUDE_OUTPUT:-<solo:done/>}"'
  echo "$MOCK_CLAUDE_SCRIPT" > "$MOCK_BIN/claude"
  chmod +x "$MOCK_BIN/claude"
}

# Helper: run solo-dev.sh with common args
run_pipeline() {
  # Set MOCK_CLAUDE_OUTPUT before calling if custom output needed
  run bash "$SOLO_DEV_REAL" "$PROJECT" "nextjs-supabase" --from build --no-dashboard --no-retro --max 10 "$@"
}

# =============================================================
# Happy path
# =============================================================

@test "integration: happy path — build→deploy→review completes" {
  export MOCK_CLAUDE_OUTPUT='<solo:done/>'

  run_pipeline

  [ "$status" -eq 0 ]

  # All 3 stage markers created
  [ -f "$PROJECT_ROOT/.solo/states/build" ]
  [ -f "$PROJECT_ROOT/.solo/states/deploy" ]
  [ -f "$PROJECT_ROOT/.solo/states/review" ]

  # Log shows completion
  [[ "$output" == *"All stages complete"* ]]
}

@test "integration: pipeline log file created" {
  export MOCK_CLAUDE_OUTPUT='<solo:done/>'

  run_pipeline

  LOG_FILE="$PROJECT_ROOT/.solo/pipelines/pipeline.log"
  [ -f "$LOG_FILE" ]
  grep -q "START" "$LOG_FILE"
  grep -q "DONE" "$LOG_FILE"
}

# =============================================================
# Redo flow
# =============================================================

@test "integration: redo cycles back to build" {
  # First 2 calls: done (build, deploy), 3rd: redo (review sends back),
  # then 3 more done (build, deploy, review)
  CALL_COUNT_FILE="$TEST_TMPDIR/call_count"
  echo "0" > "$CALL_COUNT_FILE"

  cat > "$MOCK_BIN/claude" << MOCKEOF
#!/bin/bash
COUNT=\$(cat "$CALL_COUNT_FILE")
COUNT=\$((COUNT + 1))
echo "\$COUNT" > "$CALL_COUNT_FILE"
if [ "\$COUNT" -eq 3 ]; then
  echo "<solo:redo/>"
else
  echo "<solo:done/>"
fi
MOCKEOF
  chmod +x "$MOCK_BIN/claude"

  run_pipeline

  [ "$status" -eq 0 ]
  [ -f "$PROJECT_ROOT/.solo/states/build" ]
  [ -f "$PROJECT_ROOT/.solo/states/deploy" ]
  [ -f "$PROJECT_ROOT/.solo/states/review" ]

  # Should have called claude more than 3 times (redo caused restart)
  TOTAL_CALLS=$(cat "$CALL_COUNT_FILE")
  [ "$TOTAL_CALLS" -ge 5 ]
}

# =============================================================
# Circuit breaker
# =============================================================

@test "integration: circuit breaker aborts after 3 identical failures" {
  # Claude never outputs done signal — same failure every time
  export MOCK_CLAUDE_OUTPUT="Error: something went wrong consistently"

  run_pipeline --max 10

  [ "$status" -eq 0 ]  # script exits 0 after break

  # Build marker should NOT exist (never completed)
  [ ! -f "$PROJECT_ROOT/.solo/states/build" ]

  # Log shows circuit breaker
  [[ "$output" == *"CIRCUIT"* ]] || grep -q "CIRCUIT" "$PROJECT_ROOT/.solo/pipelines/pipeline.log"
}

# =============================================================
# Rate limit
# =============================================================

@test "integration: rate limit triggers backoff and retry" {
  CALL_COUNT_FILE="$TEST_TMPDIR/call_count"
  echo "0" > "$CALL_COUNT_FILE"

  # First call: rate limit. Second: success.
  cat > "$MOCK_BIN/claude" << MOCKEOF
#!/bin/bash
COUNT=\$(cat "$CALL_COUNT_FILE")
COUNT=\$((COUNT + 1))
echo "\$COUNT" > "$CALL_COUNT_FILE"
if [ "\$COUNT" -eq 1 ]; then
  echo "Error: 429 Too Many Requests"
else
  echo "<solo:done/>"
fi
MOCKEOF
  chmod +x "$MOCK_BIN/claude"

  run_pipeline

  [ "$status" -eq 0 ]

  # Should eventually complete
  [ -f "$PROJECT_ROOT/.solo/states/build" ]

  # Log shows rate limit detection
  grep -q "RATELIMIT" "$PROJECT_ROOT/.solo/pipelines/pipeline.log"
}

# =============================================================
# Plan cycling
# =============================================================

@test "integration: plan queue cycles to next plan" {
  export MOCK_CLAUDE_OUTPUT='<solo:done/>'

  # Queue a second plan
  mkdir -p "$PROJECT_ROOT/docs/plan-queue/02-auth"
  echo "# Auth" > "$PROJECT_ROOT/docs/plan-queue/02-auth/spec.md"

  run_pipeline --max 15

  [ "$status" -eq 0 ]

  # First plan archived
  [ -d "$PROJECT_ROOT/docs/plan-done/01-test" ]

  # Second plan was activated and completed
  [ -d "$PROJECT_ROOT/docs/plan/02-auth" ] || [ -d "$PROJECT_ROOT/docs/plan-done/02-auth" ]

  # Log shows queue cycling
  grep -q "QUEUE" "$PROJECT_ROOT/.solo/pipelines/pipeline.log"
}

# =============================================================
# Timeout
# =============================================================

@test "integration: global timeout stops pipeline" {
  export MOCK_CLAUDE_OUTPUT='not-a-signal'
  # Set start epoch to 7 hours ago, max 6 hours
  export SOLO_PIPELINE_START_EPOCH=$(( $(date +%s) - 7 * 3600 ))

  run bash "$SOLO_DEV_REAL" "$PROJECT" "nextjs-supabase" \
    --from build --no-dashboard --no-retro --max 10 --max-hours 6

  [ "$status" -eq 0 ]

  # Build not completed (timed out before anything ran)
  [ ! -f "$PROJECT_ROOT/.solo/states/build" ]

  # Log shows timeout
  grep -q "TIMEOUT" "$PROJECT_ROOT/.solo/pipelines/pipeline.log"
}

# =============================================================
# Control file
# =============================================================

@test "integration: stop control file halts pipeline" {
  # Claude is slow — write stop file before first iteration completes
  cat > "$MOCK_BIN/claude" << MOCKEOF
#!/bin/bash
# Write stop control on first call
echo "stop" > "$PROJECT_ROOT/.solo/pipelines/control"
echo "<solo:done/>"
MOCKEOF
  chmod +x "$MOCK_BIN/claude"

  run_pipeline

  # Pipeline exited (stop causes exit 0)
  [ "$status" -eq 0 ]

  # State file removed by stop handler
  [ ! -f "$HOME/.solo/pipelines/solo-pipeline-${PROJECT}.local.md" ]
}
