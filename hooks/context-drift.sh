#!/bin/bash
# context-drift.sh — Context Drift Detector (SessionStart hook)
# Checks if code changed recently but docs/CLAUDE.md weren't updated.
# Output: JSON with warnings array. Silent exit 0 if no drift or not in git repo.
# AI-NOTE: Implements "Codified Context" G6 — stale specs mislead.

set -euo pipefail

# Must be in a git repo
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

SINCE_CODE="2 weeks ago"
SINCE_CLAUDE="30 days ago"

# Count code file commits (last 2 weeks)
CODE_COUNT=$(git log --oneline --since="$SINCE_CODE" --diff-filter=M \
  -- '*.py' '*.ts' '*.tsx' '*.swift' '*.kt' '*.rs' '*.go' 2>/dev/null | wc -l | tr -d ' ')

# Count doc commits (last 2 weeks)
DOC_COUNT=$(git log --oneline --since="$SINCE_CODE" --diff-filter=M \
  -- '*.md' 2>/dev/null | wc -l | tr -d ' ')

# Check CLAUDE.md staleness
CLAUDE_RECENT=$(git log --oneline --since="$SINCE_CLAUDE" -- CLAUDE.md 2>/dev/null | wc -l | tr -d ' ')

# Count files with AI-TODO items (cap search depth to stay fast)
AI_TODO_COUNT=$({ grep -rl "# AI-TODO:" . \
  --include="*.py" --include="*.ts" --include="*.tsx" \
  --include="*.swift" --include="*.kt" --include="*.rs" \
  2>/dev/null || true; } | head -50 | wc -l | tr -d ' ')

# Build warnings
WARNINGS=""

if [[ "$CODE_COUNT" -gt 10 && "$DOC_COUNT" -eq 0 ]]; then
  WARNINGS="${WARNINGS},\"CODE DRIFT: ${CODE_COUNT} code commits in 2 weeks but no docs updated\""
fi

if [[ "$CODE_COUNT" -gt 5 && "$CLAUDE_RECENT" -eq 0 ]]; then
  WARNINGS="${WARNINGS},\"STALE CLAUDE.MD: not updated in 30+ days despite ${CODE_COUNT} code changes\""
fi

if [[ "$AI_TODO_COUNT" -gt 0 ]]; then
  WARNINGS="${WARNINGS},\"AI-TODO BACKLOG: ${AI_TODO_COUNT} files have unresolved AI-TODO items\""
fi

# Silent exit if no warnings
[[ -z "$WARNINGS" ]] && exit 0

# Strip leading comma
WARNINGS="${WARNINGS#,}"

echo "{\"context_drift\": {\"warnings\": [${WARNINGS}], \"code_commits\": ${CODE_COUNT}, \"doc_commits\": ${DOC_COUNT}}}"
