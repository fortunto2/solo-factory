#!/usr/bin/env bats
# circuit_breaker.bats — failure detection + rate limit tests

load test_helper

setup() {
  common_setup
}

# --- Circuit Breaker ---

@test "circuit breaker increments on same fingerprint" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  printf "line1\nline2\nline3\nline4\nline5\n" > "$OUTFILE"

  check_circuit_breaker "build" "$OUTFILE" "continuing"
  [ "$CONSECUTIVE_FAILS" -eq 1 ]

  check_circuit_breaker "build" "$OUTFILE" "continuing"
  [ "$CONSECUTIVE_FAILS" -eq 2 ]
}

@test "circuit breaker resets on different fingerprint" {
  OUTFILE1="$BATS_TEST_TMPDIR/output1.txt"
  printf "error type A\nfailure A\nline3\nline4\nline5\n" > "$OUTFILE1"

  OUTFILE2="$BATS_TEST_TMPDIR/output2.txt"
  printf "error type B\nfailure B\nline3\nline4\nline5\n" > "$OUTFILE2"

  check_circuit_breaker "build" "$OUTFILE1" "continuing"
  [ "$CONSECUTIVE_FAILS" -eq 1 ]

  check_circuit_breaker "build" "$OUTFILE2" "continuing"
  [ "$CONSECUTIVE_FAILS" -eq 1 ]
}

@test "circuit breaker triggers at limit" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  printf "same error\nsame error\nsame error\nsame error\nsame error\n" > "$OUTFILE"

  check_circuit_breaker "build" "$OUTFILE" "continuing"
  [ "$CONSECUTIVE_FAILS" -eq 1 ]

  check_circuit_breaker "build" "$OUTFILE" "continuing"
  [ "$CONSECUTIVE_FAILS" -eq 2 ]

  run check_circuit_breaker "build" "$OUTFILE" "continuing"
  [ "$status" -eq 1 ]
}

@test "circuit breaker resets on stage success" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  printf "some error\n" > "$OUTFILE"

  check_circuit_breaker "build" "$OUTFILE" "continuing"
  [ "$CONSECUTIVE_FAILS" -eq 1 ]

  check_circuit_breaker "build" "$OUTFILE" "stage complete"
  [ "$CONSECUTIVE_FAILS" -eq 0 ]
  [ -z "$LAST_FAIL_FINGERPRINT" ]
}

@test "circuit breaker uses stage in fingerprint" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  printf "identical output\n" > "$OUTFILE"

  check_circuit_breaker "build" "$OUTFILE" "continuing"
  FP1="$LAST_FAIL_FINGERPRINT"

  CONSECUTIVE_FAILS=0
  LAST_FAIL_FINGERPRINT=""
  check_circuit_breaker "deploy" "$OUTFILE" "continuing"
  FP2="$LAST_FAIL_FINGERPRINT"

  [ "$FP1" != "$FP2" ]
}

# --- Rate Limit Detection ---

@test "rate limit detection on 429 pattern" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "Error: 429 Too Many Requests" > "$OUTFILE"

  run check_rate_limit "$OUTFILE" "0"
  [ "$status" -eq 0 ]
}

@test "rate limit detection on usage limit pattern" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "Your account has reached its usage limit" > "$OUTFILE"

  run check_rate_limit "$OUTFILE" "0"
  [ "$status" -eq 0 ]
}

@test "rate limit detection on empty output with non-zero exit" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "err" > "$OUTFILE"

  run check_rate_limit "$OUTFILE" "1"
  [ "$status" -eq 0 ]
}

@test "rate limit not triggered on normal output" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  printf '%0.s=' {1..200} > "$OUTFILE"
  echo "<solo:done/>" >> "$OUTFILE"

  run check_rate_limit "$OUTFILE" "0"
  [ "$status" -eq 1 ]
}

@test "rate limit not triggered when solo:done present despite rate limit text" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "Warning: rate limit approaching" > "$OUTFILE"
  echo "<solo:done/>" >> "$OUTFILE"

  run check_rate_limit "$OUTFILE" "0"
  [ "$status" -eq 1 ]
}

@test "rate limit backoff doubles" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "429 rate limit" > "$OUTFILE"

  RATE_LIMIT_BACKOFF=60
  check_rate_limit "$OUTFILE" "0" || true
  [ "$RATE_LIMIT_BACKOFF" -eq 120 ]

  check_rate_limit "$OUTFILE" "0" || true
  [ "$RATE_LIMIT_BACKOFF" -eq 240 ]
}

@test "rate limit backoff caps at max" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "429 rate limit" > "$OUTFILE"

  RATE_LIMIT_BACKOFF=2000
  RATE_LIMIT_MAX_BACKOFF=3600
  check_rate_limit "$OUTFILE" "0" || true
  [ "$RATE_LIMIT_BACKOFF" -eq 3600 ]
}

@test "rate limit exhausts retries" {
  OUTFILE="$BATS_TEST_TMPDIR/output.txt"
  echo "429 rate limit" > "$OUTFILE"

  RATE_LIMIT_RETRIES=9
  RATE_LIMIT_MAX_RETRIES=10

  run check_rate_limit "$OUTFILE" "0"
  [ "$status" -eq 2 ]
}
