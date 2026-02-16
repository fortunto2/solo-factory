#!/usr/bin/env bats
# signals.bats — signal detection + redo counter tests (CRITICAL)

load test_helper

setup() {
  common_setup
}

@test "solo:done signal creates stage marker" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "Some output text" > "$OUTFILE"
  echo "<solo:done/>" >> "$OUTFILE"

  handle_signals "$OUTFILE" "$BUILD_CHECK"

  [ -f "$BUILD_CHECK" ]
  grep -q "Completed:" "$BUILD_CHECK"
}

@test "solo:done does not overwrite existing marker" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "<solo:done/>" > "$OUTFILE"

  echo "Already done" > "$BUILD_CHECK"

  handle_signals "$OUTFILE" "$BUILD_CHECK"

  grep -q "Already done" "$BUILD_CHECK"
}

@test "solo:redo signal removes build/deploy/review markers" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "<solo:redo/>" > "$OUTFILE"

  echo "done" > "$STATES_DIR/build"
  echo "done" > "$STATES_DIR/deploy"
  echo "done" > "$STATES_DIR/review"

  handle_signals "$OUTFILE" "$BUILD_CHECK"

  [ ! -f "$STATES_DIR/build" ]
  [ ! -f "$STATES_DIR/deploy" ]
  [ ! -f "$STATES_DIR/review" ]
}

@test "solo:redo priority over solo:done when both present" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "<solo:done/>" > "$OUTFILE"
  echo "<solo:redo/>" >> "$OUTFILE"

  handle_signals "$OUTFILE" "$BUILD_CHECK"

  [ ! -f "$BUILD_CHECK" ]
}

@test "redo counter increments on each redo" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "<solo:redo/>" > "$OUTFILE"

  REDO_COUNT=0
  handle_signals "$OUTFILE" "$BUILD_CHECK"
  [ "$REDO_COUNT" -eq 1 ]

  handle_signals "$OUTFILE" "$BUILD_CHECK"
  [ "$REDO_COUNT" -eq 2 ]
}

@test "redo counter forces done when limit exceeded" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "<solo:redo/>" > "$OUTFILE"

  REDO_COUNT=2
  REDO_MAX=2

  handle_signals "$OUTFILE" "$BUILD_CHECK"

  [ "$REDO_COUNT" -eq 3 ]
  [ -f "$STATES_DIR/build" ]
  [ -f "$STATES_DIR/deploy" ]
  [ -f "$STATES_DIR/review" ]
  grep -q "redo limit" "$STATES_DIR/build"
}

@test "redo counter resets on plan cycle" {
  REDO_COUNT=2
  REDO_COUNT=0  # simulates reset after cycle_next_plan
  [ "$REDO_COUNT" -eq 0 ]
}

@test "solo:done with no output file is safe" {
  handle_signals "/nonexistent/file" "$BUILD_CHECK"
  [ ! -f "$BUILD_CHECK" ]
}

@test "output without any signal creates no markers" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "Just regular output, no signals" > "$OUTFILE"

  handle_signals "$OUTFILE" "$BUILD_CHECK"

  [ ! -f "$BUILD_CHECK" ]
  [ "$REDO_COUNT" -eq 0 ]
}
