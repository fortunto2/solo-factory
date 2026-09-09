#!/usr/bin/env bats
# control.bats — pipeline control tests (IMPORTANT)

load test_helper

setup() {
  common_setup
  source_solo_functions
}

@test "check_control does nothing without control file" {
  SKIP_STAGE=false
  check_control
  [ "$SKIP_STAGE" == "false" ]
}

@test "check_control stop removes state file and exits" {
  echo "stop" > "$CONTROL_FILE"
  echo "pipeline state" > "$STATE_FILE"

  run check_control
  [ "$status" -eq 0 ]

  [ ! -f "$CONTROL_FILE" ]
  [ ! -f "$STATE_FILE" ]
}

@test "check_control skip sets SKIP_STAGE true" {
  echo "skip" > "$CONTROL_FILE"

  check_control

  [ "$SKIP_STAGE" == "true" ]
  [ ! -f "$CONTROL_FILE" ]
}

@test "check_control skip resets on next call" {
  echo "skip" > "$CONTROL_FILE"
  check_control
  [ "$SKIP_STAGE" == "true" ]

  check_control
  [ "$SKIP_STAGE" == "false" ]
}

@test "check_control pause blocks until file removed" {
  # This test used to assert only the post-conditions: the control file gone and
  # SKIP_STAGE false. Both are true even if check_control returns IMMEDIATELY —
  # `wait` then blocks for the background job and the state looks identical.
  # Measured 2026-09-09: replacing the whole `while [[ -f ... ]]; do sleep 2; done`
  # with `:` killed 0 tests. The pause is how an operator halts a running pipeline,
  # and nothing verified that it pauses.
  #
  # The discriminating observation, with no clock in it: the background job touches
  # a marker BEFORE removing the control file. If check_control blocked, the marker
  # exists by the time it returns. If it did not, the marker does not exist yet.
  echo "pause" > "$CONTROL_FILE"
  MARKER="$BATS_TEST_TMPDIR/resumed"

  (sleep 0.5; touch "$MARKER"; rm -f "$CONTROL_FILE") &
  BG_PID=$!

  check_control

  # The property in this test's name.
  [ -f "$MARKER" ]

  wait $BG_PID 2>/dev/null || true

  [ ! -f "$CONTROL_FILE" ]
  [ "$SKIP_STAGE" == "false" ]
}

@test "check_control with unknown command does nothing" {
  echo "unknown_command" > "$CONTROL_FILE"

  check_control

  [ -f "$CONTROL_FILE" ]
  [ "$SKIP_STAGE" == "false" ]
}
