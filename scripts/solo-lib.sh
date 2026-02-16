#!/usr/bin/env bash
# solo-lib.sh — shared functions for solo pipeline scripts
#
# Sourced by solo-dev.sh. Testable via BATS (tests/test_helper.bash).
# All functions use globals set by the caller (LOG_FILE, STATES_DIR, etc.)

# --- Argument parsing ---
# Parses CLI args into globals. Validates required args and --from stage.
# Does NOT resolve context file paths (caller handles filesystem checks).
# Sets: PROJECT_NAME, STACK, FEATURE, CONTEXT_FILE, START_FROM,
#       MAX_ITERATIONS, MAX_HOURS, NO_DASHBOARD, SKIP_RETRO, SKIP_AUTOPLAN
parse_args() {
  PROJECT_NAME=""
  STACK=""
  FEATURE=""
  CONTEXT_FILE=""
  START_FROM=""
  MAX_ITERATIONS=15
  MAX_HOURS=6
  NO_DASHBOARD=false
  SKIP_RETRO=false
  SKIP_AUTOPLAN=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --feature) FEATURE="$2"; shift 2 ;;
      --file) CONTEXT_FILE="$2"; shift 2 ;;
      --from) START_FROM="$2"; shift 2 ;;
      --max) MAX_ITERATIONS="$2"; shift 2 ;;
      --max-hours) MAX_HOURS="$2"; shift 2 ;;
      --no-dashboard) NO_DASHBOARD=true; shift ;;
      --no-retro) SKIP_RETRO=true; shift ;;
      --no-autoplan) SKIP_AUTOPLAN=true; shift ;;
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
    echo "Usage: solo-dev.sh \"project\" \"stack\" [--feature \"desc\"] [--file path|dir] [--from stage] [--max N] [--no-dashboard] [--no-retro] [--no-autoplan]"
    echo ""
    echo "Stages: scaffold, setup, plan, build, deploy, review"
    echo "  --from setup       # skip scaffold"
    echo "  --from plan        # skip scaffold + setup"
    echo "  --from build       # skip scaffold + setup + plan"
    echo "  --from deploy      # skip to deploy"
    echo "  --from review      # skip to review"
    echo "  --max-hours 6      # global timeout in hours (default: 6)"
    echo "  --no-dashboard     # skip tmux dashboard"
    echo "  --no-retro         # skip post-completion retro"
    echo "  --no-autoplan      # skip post-completion auto-plan"
    return 1
  fi

  # Validate --from stage
  if [[ -n "$START_FROM" ]]; then
    local VALID_STAGES="scaffold setup plan build deploy review"
    if ! echo "$VALID_STAGES" | grep -qw "$START_FROM"; then
      echo "Error: Unknown stage '$START_FROM'. Valid: $VALID_STAGES"
      return 1
    fi
  fi

  return 0
}

# --- Log helper ---
log_entry() {
  local tag="$1"
  shift
  echo "[$(date +%H:%M:%S)] $tag | $*" | tee -a "$LOG_FILE"
}

# --- Signal handling ---
# Detects <solo:done/> and <solo:redo/> in output, manages markers.
# Sets: HAS_REDO (global, used by caller for re-exec decisions)
# Uses: REDO_COUNT, REDO_MAX, STATES_DIR, LOG_FILE
handle_signals() {
  local OUTFILE="$1"
  local CHECK="$2"

  HAS_REDO=false
  if grep -q '<solo:redo/>' "$OUTFILE" 2>/dev/null; then
    HAS_REDO=true
  fi

  if [[ "$HAS_REDO" != "true" ]] && grep -q '<solo:done/>' "$OUTFILE" 2>/dev/null; then
    local CHECK_FILE
    if [[ "$CHECK" == *"*"* ]]; then
      local CHECK_DIR
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

  if [[ "$HAS_REDO" == "true" ]]; then
    REDO_COUNT=$((REDO_COUNT + 1))
    if [[ $REDO_COUNT -gt $REDO_MAX ]]; then
      log_entry "REDO" "Redo limit reached ($REDO_MAX) — forcing done to save credits"
      for marker in build deploy review; do
        if [[ ! -f "$STATES_DIR/$marker" ]]; then
          mkdir -p "$STATES_DIR"
          echo "Forced: $(date -u +%Y-%m-%dT%H:%M:%SZ) (redo limit)" > "$STATES_DIR/$marker"
        fi
      done
    else
      log_entry "REDO" "<solo:redo/> cycle $REDO_COUNT/$REDO_MAX — going back to build"
      for marker in build deploy review; do
        if [[ -f "$STATES_DIR/$marker" ]]; then
          log_entry "SIGNAL" "<solo:redo/> → removing .solo/states/$marker"
          rm -f "$STATES_DIR/$marker"
        fi
      done
    fi
  fi
}

# --- Circuit breaker ---
# Tracks consecutive identical failures by fingerprint (stage + last 5 lines md5).
# Uses: CONSECUTIVE_FAILS, LAST_FAIL_FINGERPRINT, CIRCUIT_BREAKER_LIMIT
# Returns: 0 ok, 1 circuit breaker triggered
check_circuit_breaker() {
  local STAGE_ID="$1"
  local OUTFILE="$2"
  local STAGE_RESULT="$3"

  if [[ "$STAGE_RESULT" == "continuing" ]]; then
    local FAIL_FP
    FAIL_FP="${STAGE_ID}:$(grep -v '^$' "$OUTFILE" 2>/dev/null | tail -5 | md5sum 2>/dev/null | cut -c1-8 || echo "nofp")"
    if [[ "$FAIL_FP" == "$LAST_FAIL_FINGERPRINT" ]]; then
      CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
    else
      CONSECUTIVE_FAILS=1
      LAST_FAIL_FINGERPRINT="$FAIL_FP"
    fi
    if [[ $CONSECUTIVE_FAILS -ge $CIRCUIT_BREAKER_LIMIT ]]; then
      log_entry "CIRCUIT" "Stage '$STAGE_ID' same failure $CONSECUTIVE_FAILS times (fp: ${FAIL_FP##*:}) — aborting"
      return 1
    fi
  else
    CONSECUTIVE_FAILS=0
    LAST_FAIL_FINGERPRINT=""
  fi
  return 0
}

# --- Rate limit detection ---
# Detects API 429, usage limits, overloaded errors, empty output (CLI crash).
# Uses: RATE_LIMIT_RETRIES, RATE_LIMIT_MAX_RETRIES, RATE_LIMIT_BACKOFF, RATE_LIMIT_MAX_BACKOFF
# Returns: 0 rate limited (caller should sleep + retry), 1 not rate limited, 2 exhausted retries
check_rate_limit() {
  local OUTFILE="$1"
  local CLAUDE_EXIT="${2:-0}"
  local OUTPUT_SIZE

  OUTPUT_SIZE=$(wc -c < "$OUTFILE" 2>/dev/null | tr -d ' ')
  IS_RATE_LIMITED=false

  if grep -qiE 'rate.?limit|too many requests|429|quota exceeded|overloaded|capacity|usage.?limit|try again later|throttl' "$OUTFILE" 2>/dev/null && \
     ! grep -q '<solo:done/>' "$OUTFILE" 2>/dev/null; then
    IS_RATE_LIMITED=true
  elif [[ "$CLAUDE_EXIT" -ne 0 ]] && [[ "${OUTPUT_SIZE:-0}" -lt 100 ]]; then
    IS_RATE_LIMITED=true
    log_entry "RATELIMIT" "CLI exited with code $CLAUDE_EXIT and near-empty output (${OUTPUT_SIZE}B) — treating as rate limit"
  fi

  if [[ "$IS_RATE_LIMITED" == "true" ]]; then
    RATE_LIMIT_RETRIES=$((RATE_LIMIT_RETRIES + 1))
    if [[ $RATE_LIMIT_RETRIES -ge $RATE_LIMIT_MAX_RETRIES ]]; then
      log_entry "RATELIMIT" "Exhausted $RATE_LIMIT_MAX_RETRIES retries — aborting"
      return 2
    fi
    log_entry "RATELIMIT" "Detected rate limit (attempt $RATE_LIMIT_RETRIES/$RATE_LIMIT_MAX_RETRIES) — waiting ${RATE_LIMIT_BACKOFF}s"
    # Exponential backoff: 60 → 120 → 240 → 480 → ... (capped at max)
    RATE_LIMIT_BACKOFF=$((RATE_LIMIT_BACKOFF * 2))
    [[ $RATE_LIMIT_BACKOFF -gt $RATE_LIMIT_MAX_BACKOFF ]] && RATE_LIMIT_BACKOFF=$RATE_LIMIT_MAX_BACKOFF
    return 0
  fi

  # Reset backoff on successful invocation
  RATE_LIMIT_RETRIES=0
  RATE_LIMIT_BACKOFF=60
  return 1
}

# --- Global timeout check ---
# Uses: STARTED_EPOCH, MAX_SECONDS, MAX_HOURS
# Returns: 0 timed out, 1 still ok
check_timeout() {
  local ELAPSED=$(( $(date +%s) - STARTED_EPOCH ))
  if [[ $ELAPSED -ge $MAX_SECONDS ]]; then
    local ELAPSED_H=$(( ELAPSED / 3600 ))
    log_entry "TIMEOUT" "Global timeout reached (${ELAPSED_H}h/${MAX_HOURS}h) — stopping to save credits"
    return 0
  fi
  return 1
}
