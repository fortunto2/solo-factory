#!/bin/bash

# Solo Codex — optional secondary agent (OpenAI Codex CLI)
# Runs codex review + adversarial tests + quick fix on a project
#
# Usage:
#   solo-codex.sh <project> [--review] [--test] [--fix "issues"] [--all]
#
# Examples:
#   solo-codex.sh life2film --review              # code review only
#   solo-codex.sh life2film --test                 # adversarial tests only
#   solo-codex.sh life2film --all                  # review + test
#   solo-codex.sh life2film --fix "XSS in form"    # quick fix
#   solo-codex.sh life2film --review --test        # both
#   solo-codex.sh life2film --factory              # factory critique (evaluate pipeline skills/scripts)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Check codex ---
if ! command -v codex &>/dev/null; then
  echo "Error: codex CLI not found. Install: npm install -g @openai/codex"
  exit 1
fi

# --- Parse arguments ---
PROJECT=""
DO_REVIEW=false
DO_TEST=false
DO_FIX=false
DO_FACTORY=false
FIX_PROMPT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --review)  DO_REVIEW=true; shift ;;
    --test)    DO_TEST=true; shift ;;
    --fix)     DO_FIX=true; FIX_PROMPT="$2"; shift 2 ;;
    --all)     DO_REVIEW=true; DO_TEST=true; shift ;;
    --factory) DO_FACTORY=true; shift ;;
    *)         PROJECT="$1"; shift ;;
  esac
done

if [[ -z "$PROJECT" ]]; then
  echo "Usage: solo-codex.sh <project> [--review] [--test] [--fix \"issues\"] [--all]"
  exit 1
fi

# Default to --all if nothing specified
if [[ "$DO_REVIEW" == "false" ]] && [[ "$DO_TEST" == "false" ]] && [[ "$DO_FIX" == "false" ]] && [[ "$DO_FACTORY" == "false" ]]; then
  DO_REVIEW=true
  DO_TEST=true
fi

# --- Find project directory ---
PROJECT_DIR="$HOME/startups/active/$PROJECT"
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Error: Project not found: $PROJECT_DIR"
  exit 1
fi

# --- Log helper ---
LOG_DIR="$PROJECT_DIR/.solo/pipelines"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/codex.log"

log_entry() {
  local tag="$1"; shift
  echo "[$(date +%H:%M:%S)] CODEX.$tag | $*" | tee -a "$LOG_FILE"
}

echo ""
echo "Solo Codex: $PROJECT"
echo "  Dir:     $PROJECT_DIR"
echo "  Codex:   $(codex --version 2>/dev/null)"
echo "  Review:  $DO_REVIEW"
echo "  Test:    $DO_TEST"
echo "  Fix:     $DO_FIX"
echo "  Log:     $LOG_FILE"
echo ""

# =============================================
# 1. Code Review
# =============================================
if [[ "$DO_REVIEW" == "true" ]]; then
  log_entry "REVIEW" "Starting code review..."
  OUTFILE=$(mktemp /tmp/solo-codex-review-XXXXXX)

  # codex review --uncommitted reads AGENTS.md for review instructions
  # Prompt cannot be combined with --uncommitted, so AGENTS.md is the source of truth
  (cd "$PROJECT_DIR" && codex review --uncommitted 2>&1) \
    | tee "$OUTFILE" || true

  cp "$OUTFILE" "$LOG_DIR/codex-review-$(date +%Y%m%d-%H%M%S).log"

  # Check verdict
  if grep -qi 'BLOCK' "$OUTFILE" 2>/dev/null; then
    log_entry "REVIEW" "Verdict: BLOCK"
    REVIEW_ISSUES=$(grep -A2 'Critical' "$OUTFILE" 2>/dev/null | head -10)
  elif grep -qi 'ISSUES_FOUND' "$OUTFILE" 2>/dev/null; then
    log_entry "REVIEW" "Verdict: ISSUES_FOUND"
  else
    log_entry "REVIEW" "Verdict: PASS"
  fi

  rm -f "$OUTFILE"
  echo ""
fi

# =============================================
# 2. Adversarial Tests
# =============================================
if [[ "$DO_TEST" == "true" ]]; then
  log_entry "TEST" "Writing adversarial tests..."
  OUTFILE=$(mktemp /tmp/solo-codex-test-XXXXXX)

  # Detect test framework
  TEST_CMD="pnpm test -- --run"
  if [[ -f "$PROJECT_DIR/pyproject.toml" ]]; then
    TEST_CMD="uv run pytest"
  fi

  (cd "$PROJECT_DIR" && codex exec --full-auto \
    "Write edge-case tests for code changed in the last 3 commits.
Rules:
- Put tests next to source in __tests__/ directories
- Focus on: boundary values, null/undefined, concurrent calls, malformed input, empty arrays, max-length strings
- Run '$TEST_CMD' after writing to confirm they pass
- If tests reveal bugs, document them clearly
- Keep changes minimal — tests only, no refactoring
- Do NOT modify existing tests or source code" \
    2>&1) | tee "$OUTFILE" || true

  cp "$OUTFILE" "$LOG_DIR/codex-test-$(date +%Y%m%d-%H%M%S).log"

  # Check if tests pass
  if (cd "$PROJECT_DIR" && eval "$TEST_CMD" 2>&1 | tail -5 | grep -q 'passed'); then
    log_entry "TEST" "All tests pass"
  else
    log_entry "TEST" "Some tests may have failed — check log"
  fi

  rm -f "$OUTFILE"
  echo ""
fi

# =============================================
# 3. Quick Fix
# =============================================
if [[ "$DO_FIX" == "true" ]] && [[ -n "$FIX_PROMPT" ]]; then
  log_entry "FIX" "Fixing: $FIX_PROMPT"
  OUTFILE=$(mktemp /tmp/solo-codex-fix-XXXXXX)

  # Detect test/lint commands
  TEST_CMD="pnpm test -- --run"
  LINT_CMD="pnpm lint"
  if [[ -f "$PROJECT_DIR/pyproject.toml" ]]; then
    TEST_CMD="uv run pytest"
    LINT_CMD="uv run ruff check ."
  fi

  (cd "$PROJECT_DIR" && codex exec --full-auto \
    "Fix the following issues. ONLY fix what's listed — no refactoring, no cleanup.
After fixing:
1. Run '$TEST_CMD' to verify tests pass
2. Run '$LINT_CMD' to verify lint passes
3. Commit with message: fix(codex): <description>

Issues to fix:
$FIX_PROMPT" \
    2>&1) | tee "$OUTFILE" || true

  cp "$OUTFILE" "$LOG_DIR/codex-fix-$(date +%Y%m%d-%H%M%S).log"
  log_entry "FIX" "Done"
  rm -f "$OUTFILE"
  echo ""
fi

# =============================================
# 4. Factory Critique
# =============================================
if [[ "$DO_FACTORY" == "true" ]]; then
  log_entry "FACTORY" "Starting factory critique..."
  OUTFILE=$(mktemp /tmp/solo-codex-factory-XXXXXX)
  EVOLUTION_FILE="$HOME/.solo/evolution.md"

  # Find solo-factory root (relative to this script)
  FACTORY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

  # Collect pipeline artifacts
  PIPELINE_LOG="$PROJECT_DIR/.solo/pipelines/pipeline.log"
  RETRO_FILE=$(find "$PROJECT_DIR/docs/retro" -name "*.md" -type f 2>/dev/null | sort | tail -1)

  # Build context for codex
  FACTORY_CONTEXT="pipeline log: $PIPELINE_LOG"
  [[ -n "$RETRO_FILE" ]] && FACTORY_CONTEXT="$FACTORY_CONTEXT, retro: $RETRO_FILE"

  (cd "$FACTORY_DIR" && codex exec --full-auto --writable-path "$HOME/.solo" \
    "You are a factory critic. Evaluate the solo-factory pipeline tools that just built project '$PROJECT'.

Read these artifacts:
- $PIPELINE_LOG (pipeline execution log — parse STAGE/SIGNAL/ITER/CHECK lines)
$([ -n "$RETRO_FILE" ] && echo "- $RETRO_FILE (retro report with failure patterns)")
- scripts/solo-dev.sh (pipeline runner)
- Look at skills/ directory — read SKILL.md files for stages that had failures

Your job: find defects in the FACTORY (skills, scripts, pipeline logic), NOT in the project code.

For each defect found, output a structured block:
DEFECT: <severity: critical|high|medium|low>
SKILL: <skill or script name>
FILE: <path relative to solo-factory>
ISSUE: <what went wrong>
FIX: <concrete change needed>

Also note what worked well.

After analysis, append your findings to $EVOLUTION_FILE in this format:
## $(date +%Y-%m-%d) | $PROJECT | Codex Factory Critique
<your structured findings>

Rules:
- Be brutally honest
- Every defect must have a concrete fix
- Do NOT modify any solo-factory files — only write to $EVOLUTION_FILE
- Keep it compact (under 2000 chars)" \
    2>&1) | tee "$OUTFILE" || true

  cp "$OUTFILE" "$LOG_DIR/codex-factory-$(date +%Y%m%d-%H%M%S).log"
  log_entry "FACTORY" "Done — findings appended to $EVOLUTION_FILE"
  rm -f "$OUTFILE"
  echo ""
fi

# --- Summary ---
echo "==============================================================="
log_entry "DONE" "Codex tasks complete for $PROJECT"
echo "==============================================================="
