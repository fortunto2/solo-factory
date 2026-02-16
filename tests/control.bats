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
  echo "pause" > "$CONTROL_FILE"

  (sleep 1 && rm -f "$CONTROL_FILE") &
  BG_PID=$!

  check_control

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
