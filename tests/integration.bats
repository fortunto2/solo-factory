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

@test "integration: three identical failures stop the pipeline" {
  # Measured 2026-09-09: replacing the caller's `break` with `:` — so the circuit
  # breaker's answer is ignored entirely — killed 0 tests. The unit tests verify the
  # counter and the return value; nothing verified that anything ACTS on them.
  #
  # This is what the breaker exists for: a stage failing identically forever burns
  # tokens and wall clock until a human notices. The claim had been in CLAUDE.md
  # since it was written ("fingerprint-based, limit 3") and deferred here three
  # cycles running.
  # Exit 0 with identical output and no completion marker — the stage keeps
  # "continuing" forever. A non-zero exit goes down the rate-limit path instead and
  # never reaches the breaker at all, which is what the first version of this test
  # measured without meaning to.
  cat > "$MOCK_BIN/claude" << 'MOCKEOF'
#!/bin/bash
echo "count" >> "$MOCK_CALLS"
echo "working on it, the same way as last time"
exit 0
MOCKEOF
  chmod +x "$MOCK_BIN/claude"
  export MOCK_CALLS="$BATS_TEST_TMPDIR/calls"
  : > "$MOCK_CALLS"

  run_pipeline

  # --max 10 would allow ten iterations. The breaker must end it well before that,
  # and the ceiling is what makes this test able to fail: with the breaker ignored
  # the mock is called until the cap.
  calls=$(wc -l < "$MOCK_CALLS" | tr -d ' ')
  [ "$calls" -ge 3 ]      # it did retry — otherwise nothing was exercised
  [ "$calls" -lt 10 ]     # and it stopped short of the iteration cap
  # The breaker announces itself in the pipeline log, not on stdout — log_entry
  # writes to a file. Asserting on $output would have been a claim about the wrong
  # channel, and it is the reason this line failed while the counts above passed.
  run bash -c "grep -rl CIRCUIT '$PROJECT_ROOT/.solo' 2>/dev/null | head -1"
  [ -n "$output" ]
}

@test "integration: a skip control file advances past the stuck stage" {
  # Measured 2026-09-09: making the pipeline ignore SKIP_STAGE entirely — `if false`
  # at the point that acts on it — killed 0 tests. control.bats verifies that
  # check_control SETS the flag; nothing verified that the pipeline reads it.
  #
  # Third operator-facing control in a row with the same shape: the decision is
  # tested, the action is not. Skip is the escape hatch for a stage that will never
  # produce its marker, so a dead skip leaves an operator with only stop.
  #
  # The first version of this test asserted the state MARKER exists at the end. It
  # does not — the run cleans markers on the way out — and the pipeline had in fact
  # skipped correctly. Asserting a post-condition instead of the event is the same
  # mistake this sweep exists to find, made while writing the test for it.
  # Unquoted heredoc on purpose: $PROJECT_ROOT is expanded HERE, into a literal path
  # inside the mock. Quoting it defers the expansion to the mock's own shell, where
  # the variable is unset — the mock then writes the control file nowhere, no CTRL
  # line appears, and the run looks exactly like a pipeline ignoring skip. Third
  # probe-construction error this cycle to wear the symptoms of the finding it was
  # written to test.
  cat > "$MOCK_BIN/claude" << MOCKEOF
#!/bin/bash
if [ ! -f "$PROJECT_ROOT/.solo/pipelines/skipped-once" ]; then
  touch "$PROJECT_ROOT/.solo/pipelines/skipped-once"
  echo "skip" > "$PROJECT_ROOT/.solo/pipelines/control"
fi
echo "still working, no marker"
MOCKEOF
  chmod +x "$MOCK_BIN/claude"

  run_pipeline

  LOG="$PROJECT_ROOT/.solo/pipelines/pipeline.log"
  # The event: the pipeline acted on the flag.
  grep -q "Skipping stage: build" "$LOG"
  # And its consequence: it moved off a stage that never produced a marker. Without
  # the skip it would repeat `build` until the circuit breaker or the cap.
  grep -q "stage 2/3: deploy" "$LOG"
}
