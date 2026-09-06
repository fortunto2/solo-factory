#!/usr/bin/env bash
# sensor-stop.sh — Stop hook: the step boundary where semantic checks run.
#
# Why a blocking gate exists at all: without it, "done" is a claim the agent
# makes about itself. The failure it removes is the one @siert-hermes measured
# on the board — reporting "saved" after a command that exited 0 without ever
# doing the work. If the turn cannot end while the receipt is red, reporting
# success without verifying stops being a reachable state.
#
# Three calibrations, each from a counterexample rather than from theory:
#
#  1. ONE block per turn. stop_hook_active short-circuits everything. A gate
#     that can fire twice becomes a cage when the cause is unfixable (no
#     network, broken external service).
#  2. UNKNOWN blocks too. Changes exist but nothing was verified is the exact
#     shape of a false green (@antigravity-scout-99's False Green on Zero
#     Scope). Silence is not consent.
#  3. Editing the harness does NOT block. In 3 of 5 real cases the correct
#     repair was the rule, not the code (@zhopych-dristun). So a harness edit
#     is surfaced loudly and left to the human, never forbidden.
#
# Off switch:  SOLO_SENSOR_STOP=off|fast|full   (default: full)

set -uo pipefail

INPUT=$(cat)
MODE="${SOLO_SENSOR_STOP:-full}"
[[ "$MODE" == "off" ]] && exit 0

ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[[ "$ACTIVE" == "true" ]] && exit 0   # already blocked once this turn

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
ROOT="${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}"

VERIFY="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts/solo-verify"
[[ -x "$VERIFY" ]] || exit 0

git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

ARGS=(--root "$ROOT" --json)
[[ "$MODE" == "full" ]] && ARGS+=(--full)

REC=$("$VERIFY" "${ARGS[@]}" 2>/dev/null) || true
[[ -z "$REC" ]] && exit 0

VERDICT=$(printf '%s' "$REC" | jq -r '.verdict // "UNKNOWN"' 2>/dev/null)
SCOPE=$(printf '%s' "$REC" | jq -r '.scope | length' 2>/dev/null)
[[ -z "$SCOPE" || "$SCOPE" == "null" ]] && SCOPE=0

# Nothing changed this turn — nothing to verify, nothing to block.
[[ "$SCOPE" -eq 0 ]] && exit 0

HUMAN=$(printf '%s' "$REC" | jq -r '
  "VERIFY \(.verdict) (\(.mode), \(.elapsed)s)",
  "  scope: \(.scope|length) changed, \(.covered|length) covered",
  "  ran: " + ([.ran[] | "\(.name)=\(.status)"] | join(", ")),
  (if (.unchecked|length) > 0 then "  UNCHECKED: " + (.unchecked | join(", ")) else empty end),
  (if (.harness_touched|length) > 0 then "  HARNESS TOUCHED: " + (.harness_touched | join(", ")) else empty end),
  (if (.findings|length) > 0 then "  findings:" else empty end),
  (.findings[:15][] | "    " + .)
' 2>/dev/null)

block() {
  jq -n --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"Stop", continue:true, additionalContext:$ctx}}'
  exit 0
}

case "$VERDICT" in
  FAIL)
    block "The turn cannot end yet: verification is red.

$HUMAN

Fix the findings, or state explicitly which one you are leaving and why.
If a finding is wrong because the RULE is wrong, say which promise you are
changing — do not weaken a threshold silently."
    ;;
  UNKNOWN)
    block "The turn cannot end yet: ${SCOPE} file(s) changed and NOTHING was verified.

$HUMAN

An empty result is not a pass. Either make the checks runnable (install the
missing tool, widen the scope) or tell the operator plainly that this change
is unverified, and why."
    ;;
  PASS)
    TOUCHED=$(printf '%s' "$REC" | jq -r '.harness_touched | length' 2>/dev/null)
    if [[ "${TOUCHED:-0}" -gt 0 ]]; then
      # Visible, not blocking: the green light and the edit to the apparatus
      # that produced it belong on the same screen.
      jq -n --arg ctx "Verification is green, but this change also edits the measuring apparatus:
$(printf '%s' "$REC" | jq -r '.harness_touched[]' | sed 's/^/  /')

Mention this in the commit message and say which promise changed." \
        '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$ctx}}'
    fi
    exit 0
    ;;
esac

exit 0
