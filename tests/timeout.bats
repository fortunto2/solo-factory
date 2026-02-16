#!/usr/bin/env bats
# timeout.bats — global timeout tests (IMPORTANT)

load test_helper

setup() {
  common_setup
}

@test "timeout check passes when under limit" {
  STARTED_EPOCH=$(date +%s)
  MAX_SECONDS=$((6 * 3600))

  run check_timeout
  [ "$status" -eq 1 ]  # 1 = not timed out
}

@test "timeout check triggers when over limit" {
  STARTED_EPOCH=$(( $(date +%s) - 7 * 3600 ))
  MAX_SECONDS=$((6 * 3600))

  run check_timeout
  [ "$status" -eq 0 ]  # 0 = timed out
}

@test "timeout check triggers at exact boundary" {
  STARTED_EPOCH=$(( $(date +%s) - MAX_SECONDS ))

  run check_timeout
  [ "$status" -eq 0 ]
}

@test "SOLO_PIPELINE_START_EPOCH preserved across re-exec" {
  ORIGINAL_EPOCH=1700000000
  export SOLO_PIPELINE_START_EPOCH="$ORIGINAL_EPOCH"

  # Simulate what solo-dev.sh does on line 171
  STARTED_EPOCH=${SOLO_PIPELINE_START_EPOCH:-$(date +%s)}

  [ "$STARTED_EPOCH" -eq "$ORIGINAL_EPOCH" ]
}

@test "timeout with custom max-hours" {
  MAX_HOURS=1
  MAX_SECONDS=$((MAX_HOURS * 3600))
  STARTED_EPOCH=$(( $(date +%s) - 2 * 3600 ))

  run check_timeout
  [ "$status" -eq 0 ]
}

@test "timeout not triggered with large max-hours" {
  MAX_HOURS=24
  MAX_SECONDS=$((MAX_HOURS * 3600))
  STARTED_EPOCH=$(date +%s)

  run check_timeout
  [ "$status" -eq 1 ]
}
