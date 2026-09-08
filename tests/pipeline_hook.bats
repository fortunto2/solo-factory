#!/usr/bin/env bats
# pipeline-stop.sh — the fourth hook, and the one my own count missed.
#
# Last cycle's commit said "all three hooks are now probed". There are four. The
# number came from memory rather than from `ls hooks/*.sh`, which is the third time
# this week a count was published without being enumerated.
#
# The unexamined one was the largest: 321 lines, driving the pipeline's done/redo
# signals, its timeout and its iteration counter.

H="${BATS_TEST_DIRNAME}/../hooks/pipeline-stop.sh"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  FAKE="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE/.solo/pipelines"
  printf '{"role":"assistant","message":{"content":[{"type":"text","text":"done <solo:done/>"}]}}\n' \
    > "$BATS_TEST_TMPDIR/tr.jsonl"
}

# A fresh state file per invocation. The hook DELETES it when the pipeline
# completes, so a second probe in the same fixture runs against no pipeline at all
# and goes silent — which is how three "silent" measurements were nearly reported
# as a finding.
fixture() {
  cat > "$FAKE/.solo/pipelines/solo-pipeline-proj.local.md" <<EOF
---
active: true
project: proj
mode: normal
log_file: $BATS_TEST_TMPDIR/pipe.log
started_at: 2026-09-08T10:00:00Z
max_hours: 6
iteration: 1
max_iterations: 15
stages:
  - build
---
EOF
}

fire() { printf '{"transcript_path":"%s"}' "$1" | env HOME="$FAKE" bash "$H" 2>&1; }

@test "a state file missing optional fields does not kill the hook" {
  # `set -euo pipefail` is on and every field was read with its own `grep '^field:'`,
  # so a state file WITHOUT one of them made grep exit 1 and killed the hook
  # outright — silently, with exit 1, before the signal check, the timeout check and
  # the iteration counter had run. Twelve fields, each fatal by absence.
  fixture   # deliberately has no signals:, idea:, pipeline:, context_file:
  run bash -c "printf '{\"transcript_path\":\"$BATS_TEST_TMPDIR/tr.jsonl\"}' | HOME='$FAKE' bash '$H'"
  [ "$status" -eq 0 ]
}

@test "a signal in the transcript is acted on" {
  # Positive control: if the hook simply did nothing, the tests below would pass
  # while the pipeline never advanced.
  fixture
  run fire "$BATS_TEST_TMPDIR/tr.jsonl"
  [[ "$output" == *"proj"* ]]
  [[ "$output" == *"complete"* ]]
}

@test "an unreadable transcript is named, not read as no signal" {
  # They decide the same thing and are not the same fact: a lost <solo:done/>
  # re-runs a finished stage, a lost <solo:redo/> advances past work the agent asked
  # to redo. Measured: a missing transcript produced output identical to one with no
  # signal in it.
  fixture
  run fire "$BATS_TEST_TMPDIR/nowhere.jsonl"
  [[ "$output" == *"transcript not readable"* ]]
  [[ "$output" == *"NOT checked this turn"* ]]
  [[ "$output" == *"not the same as no signal"* ]]
}

@test "no active pipeline stays silent" {
  # The hook fires on every Stop. With nothing running it must say nothing at all.
  rm -f "$FAKE/.solo/pipelines/"*.local.md
  run fire "$BATS_TEST_TMPDIR/tr.jsonl"
  [ "$output" = "" ]
}
