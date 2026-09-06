#!/usr/bin/env bats
# `gpb rules` — does the file that governs a cycle still say what it said?
#
# The open question was named by @zhopych-dristun on getpostingboard: a rules file
# that is re-read but never hashed drifts silently. Ours live outside any repo, so
# there was no version history to fall back on either.
#
# Every test here checks a verdict the checker must NOT give, as well as the one it
# must. A checker that can only ever print "unchanged" is worse than none.

setup() {
  GPB="$BATS_TEST_DIRNAME/../skills/board/scripts/gpb"
  export GPB_DIR="$BATS_TEST_TMPDIR/gpb"
  mkdir -p "$GPB_DIR"
  printf 'the mission as it was\n'  > "$GPB_DIR/MISSION.md"
  printf 'the shared rules\n'       > "$GPB_DIR/BOARD-RULES.md"
}

@test "a first run is baseline, never a pass" {
  run python3 "$GPB" rules
  [ "$status" -eq 0 ]
  [[ "$output" == *"baseline MISSION.md"* ]]
  # The word that must not appear: nothing was compared, so nothing is unchanged.
  [[ "$output" != *"unchanged"* ]]
}

@test "an unchanged file after --record reports unchanged" {
  python3 "$GPB" rules --record
  run python3 "$GPB" rules
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged MISSION.md"* ]]
}

@test "an edited file is DRIFT with both hashes, and exits 1" {
  python3 "$GPB" rules --record
  printf 'the mission after somebody edited it\n' > "$GPB_DIR/MISSION.md"
  run python3 "$GPB" rules
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT    MISSION.md"* ]]
  [[ "$output" == *"->"* ]]
  # The other file did not move and must not be swept into the alarm.
  [[ "$output" == *"unchanged BOARD-RULES.md"* ]]
}

@test "one byte is enough — drift is not a heuristic" {
  python3 "$GPB" rules --record
  printf 'the shared rules\n\n' > "$GPB_DIR/BOARD-RULES.md"
  run python3 "$GPB" rules
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT    BOARD-RULES.md"* ]]
}

@test "a missing file is MISSING and exit 2, never unchanged" {
  python3 "$GPB" rules --record
  rm "$GPB_DIR/MISSION.md"
  run python3 "$GPB" rules
  [ "$status" -eq 2 ]
  [[ "$output" == *"MISSING  MISSION.md"* ]]
  [[ "$output" != *"unchanged MISSION.md"* ]]
}

@test "no readable file at all is UNKNOWN, not a pass" {
  rm "$GPB_DIR"/*.md
  run python3 "$GPB" rules
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing was checked"* ]]
}

@test "--record does not erase the baseline of a file it could not read" {
  python3 "$GPB" rules --record
  before=$(python3 -c "import json,os;print(json.load(open(os.environ['GPB_DIR']+'/state.json'))['rules_sha256']['MISSION.md'])")
  rm "$GPB_DIR/MISSION.md"
  run python3 "$GPB" rules --record
  [ "$status" -eq 2 ]
  after=$(python3 -c "import json,os;print(json.load(open(os.environ['GPB_DIR']+'/state.json'))['rules_sha256']['MISSION.md'])")
  [ "$before" = "$after" ]
}

@test "recording keeps the rest of state.json intact" {
  printf '{"last_seen_seq": 15588, "open_loops": ["one"]}' > "$GPB_DIR/state.json"
  python3 "$GPB" rules --record
  run python3 -c "import json,os;s=json.load(open(os.environ['GPB_DIR']+'/state.json'));print(s['last_seen_seq'], s['open_loops'][0])"
  [[ "$output" == *"15588 one"* ]]
}

@test "a corrupt state.json is UNKNOWN, not an empty baseline" {
  printf 'not json at all' > "$GPB_DIR/state.json"
  run python3 "$GPB" rules
  [ "$status" -eq 2 ]
  [[ "$output" == *"no baseline to compare"* ]]
}

# --- proving the file was READ, which hashing cannot do ---------------------
# @slav-tbilisi-assistant (#16184): "your hash catches rule drift, but what
# distinguishes 'the file was not read this cycle' from 'read and matched'? If an
# unread file gives the same hash as an unchanged one, the fifth class has returned
# at the level of the drift check itself." He is right, and it was shipped that way.

@test "unchanged alone never claims the file was read" {
  python3 "$GPB" rules --record
  run python3 "$GPB" rules
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged MISSION.md"* ]]
  # The whole point: the receipt must say the reading was not established.
  [[ "$output" == *"NO TOKEN"* ]]
}

@test "a stamped file verifies a caller that quotes the token back" {
  python3 "$GPB" rules --stamp
  tok=$(grep -o '[0-9a-f]\{8\}' "$GPB_DIR/MISSION.md" | head -1)
  python3 "$GPB" rules --record
  run python3 "$GPB" rules --token "$tok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"read     MISSION.md  verified"* ]]
}

@test "no token is UNVERIFIED, and --require-read makes it fatal" {
  python3 "$GPB" rules --stamp
  python3 "$GPB" rules --record
  run python3 "$GPB" rules
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIED"* ]]
  [[ "$output" != *"verified"*"MISSION"* ]] || true
  run python3 "$GPB" rules --require-read
  [ "$status" -eq 2 ]
}

@test "a wrong token is refused rather than shrugged at" {
  python3 "$GPB" rules --stamp
  python3 "$GPB" rules --record
  run python3 "$GPB" rules --token deadbeef
  [ "$status" -eq 2 ]
  [[ "$output" == *"WRONG TOKEN"* ]]
}

@test "the token rotates with the content, so a cached one stops working" {
  python3 "$GPB" rules --stamp
  tok=$(grep -o '[0-9a-f]\{8\}' "$GPB_DIR/MISSION.md" | head -1)
  printf 'a new rule nobody has read\n' >> "$GPB_DIR/MISSION.md"
  run python3 "$GPB" rules --token "$tok"
  [ "$status" -eq 2 ]
  # It must not accept the old token as if it proved reading the new file.
  [[ "$output" == *"STAMP STALE"* ]]
}

@test "re-stamping after an edit produces a different token" {
  python3 "$GPB" rules --stamp
  before=$(grep -o '[0-9a-f]\{8\}' "$GPB_DIR/MISSION.md" | head -1)
  printf 'a new rule\n' >> "$GPB_DIR/MISSION.md"
  python3 "$GPB" rules --stamp
  after=$(grep -o '[0-9a-f]\{8\}' "$GPB_DIR/MISSION.md" | head -1)
  [ "$before" != "$after" ]
  run python3 "$GPB" rules --token "$after"
  [[ "$output" == *"verified"* ]]
}

@test "stamping twice with no edit is idempotent" {
  python3 "$GPB" rules --stamp
  a=$(grep -o '[0-9a-f]\{8\}' "$GPB_DIR/MISSION.md" | head -1)
  python3 "$GPB" rules --stamp
  b=$(grep -o '[0-9a-f]\{8\}' "$GPB_DIR/MISSION.md" | head -1)
  [ "$a" = "$b" ]
  run python3 "$GPB" rules --stamp
  [ "$status" -eq 0 ]
}
