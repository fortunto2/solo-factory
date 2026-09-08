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

# Bounded, and the bound is the one this repo publishes for this placement. A
# 4000-file change took 163s in FAST mode, measured — so the gate could block a
# turn for minutes with no output at all, and our own rule says a gate that costs
# minutes gets bypassed.
BUDGET="${SOLO_SENSOR_BUDGET:-150}"
ERR=$(mktemp)
if command -v timeout >/dev/null 2>&1; then
  REC=$(timeout "$BUDGET" "$VERIFY" "${ARGS[@]}" 2>"$ERR"); RC=$?
elif command -v gtimeout >/dev/null 2>&1; then
  REC=$(gtimeout "$BUDGET" "$VERIFY" "${ARGS[@]}" 2>"$ERR"); RC=$?
else
  # No timeout binary — the ordinary case on macOS, where neither `timeout` nor
  # `gtimeout` exists without coreutils. The first version set UNBOUNDED=1 here and
  # never read it: a comment saying "say so rather than pretend the run was bounded"
  # above code that pretended. Measured by asking for a 3s budget on a 4000-file
  # tree and watching it take 114s in silence.
  REC=$("$VERIFY" "${ARGS[@]}" 2>"$ERR"); RC=$?
  UNBOUNDED="  (ran UNBOUNDED: no timeout(1) here, so SOLO_SENSOR_BUDGET=${BUDGET}s was not enforced — install coreutils or narrow the scope yourself)"
fi
STDERR=$(cat "$ERR"); rm -f "$ERR"

if [[ "$RC" -eq 124 ]]; then
  # A timed-out run never observed the thing under test. Rule 3a: not a pass.
  jq -n --arg ctx "The turn cannot end yet: verification did not finish within ${BUDGET}s.

A run that was killed observed nothing. This is not a pass and not a failure —
it is an absence of a result. Narrow the change, run \`solo-verify --files ...\`
on what matters, or set SOLO_SENSOR_BUDGET deliberately and say why." \
    '{hookSpecificOutput:{hookEventName:"Stop", continue:true, additionalContext:$ctx}}'
  exit 0
fi

if [[ -z "$REC" ]]; then
  # This used to `exit 0` in silence: a verifier that produced nothing reading as a
  # turn that passed — the false green this whole harness exists to prevent, in the
  # gate itself. Its stderr was discarded too, so every named cause solo-verify
  # learned to print went straight to /dev/null.
  jq -n --arg ctx "The turn cannot end yet: the verifier produced no receipt (exit ${RC}).

${STDERR:-It printed nothing on stderr either.}

Nothing was verified. Say plainly that this change is unchecked, or make the
verifier runnable." \
    '{hookSpecificOutput:{hookEventName:"Stop", continue:true, additionalContext:$ctx}}'
  exit 0
fi

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
# A budget that was not enforced must be visible next to the time it did not bound.
[[ -n "${UNBOUNDED:-}" ]] && HUMAN="${HUMAN}
${UNBOUNDED}"

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
