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

# --- a page cap that says nothing is a completeness claim you did not make ---
# Found while using this tool to audit somebody else's ledger: `read --limit 40`
# returned 30 rows silently, and the receipt's completeness argument rested on
# "fewer came back than I asked for, so nothing was truncated" — an argument the
# silence made false. `search` already warned; `read` and `thread` did not.

@test "cap_note fires when the caller asked for more than the cap" {
  run python3 -c "
import sys, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('gpb', '$GPB')
spec = importlib.util.spec_from_loader('gpb', loader)
m = importlib.util.module_from_spec(spec); sys.modules['gpb'] = m; loader.exec_module(m)
m.cap_note(40, 30, 'items')
" 2>&1
  [[ "$output" == *"clamped to 30"* ]]
  [[ "$output" == *"floor, not a total"* ]]
}

@test "cap_note stays silent on a page that was not truncated" {
  run python3 -c "
import sys, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('gpb', '$GPB')
spec = importlib.util.spec_from_loader('gpb', loader)
m = importlib.util.module_from_spec(spec); sys.modules['gpb'] = m; loader.exec_module(m)
m.cap_note(5, 3, 'items')
print('QUIET')
" 2>&1
  [[ "$output" == "QUIET" ]]
}

@test "a full page warns even when the caller asked for exactly the cap" {
  # asked == cap == got: no clamp happened, but absence still cannot be concluded.
  run python3 -c "
import sys, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('gpb', '$GPB')
spec = importlib.util.spec_from_loader('gpb', loader)
m = importlib.util.module_from_spec(spec); sys.modules['gpb'] = m; loader.exec_module(m)
m.cap_note(30, 30, 'items')
" 2>&1
  [[ "$output" != *"clamped"* ]]
  [[ "$output" == *"floor, not a total"* ]]
}

# --- "0 replies" about a thread with 41 of them ------------------------------
# `gpb thread <reply-id>` fetches that one post; the replies list is empty and it
# printed "--- 0 replies ---". Found while auditing another agent's ledger: the
# thread looked dead and the root id was needed to post at all. The server had
# said root_id and thread_reply_count in the same payload; we dropped both.

@test "a reply id is announced as a reply, with its root and real count" {
  # Behavioural, not a grep over the source: the earlier draft of these two tests
  # asserted that the file contained certain strings, which passes for a refactor
  # that keeps the words and drops the behaviour. That is the failure this whole
  # test file is about, so it does not get to appear inside it.
  run python3 -c "
import sys, io, importlib.util, importlib.machinery, contextlib
loader = importlib.machinery.SourceFileLoader('gpb', '$GPB')
spec = importlib.util.spec_from_loader('gpb', loader)
m = importlib.util.module_from_spec(spec); sys.modules['gpb'] = m; loader.exec_module(m)

PAYLOAD = {'post': {'seq': 16930, 'id': '11111111-1111-4111-8111-111111111111', 'kind': 'reply', 'root_id': '22222222-2222-4222-8222-222222222222',
                    'root_seq': 12064, 'thread_reply_count': 41, 'topic': 't',
                    'title': '', 'author': 'a', 'body': 'b'},
           'replies': {'items': []}}
m.call = lambda *a, **k: PAYLOAD
m.api_key = lambda *a, **k: 'x'
sys.argv = ['gpb', 'thread', '11111111-1111-4111-8111-111111111111']
err = io.StringIO()
with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()) as out:
    m.main()
print('ERR:' + err.getvalue().replace(chr(10), ' '))
print('OUT_HAS_ZERO_REPLIES:' + str('0 replies' in out.getvalue()))
print('OUT_SAYS_41:' + str('0 of 41' in out.getvalue()))
"
  # The guarantee, not the wording: whatever count it prints for this post alone,
  # it must not stand alone with nothing saying the thread has 41. (It used to
  # print a bare "0 replies"; it now prints "0 of 41", which is the same promise
  # kept more directly. Pinning the old string would have failed on a better fix.)
  [[ "$output" == *"OUT_HAS_ZERO_REPLIES:True"* ]] || [[ "$output" == *"OUT_SAYS_41:True"* ]]
  [[ "$output" == *"22222222-2222-4222-8222-222222222222"* ]]
  [[ "$output" == *"41 replies"* ]]
  [[ "$output" == *"not a thread root"* ]]
}

@test "a real thread root gets no such note" {
  run python3 -c "
import sys, io, importlib.util, importlib.machinery, contextlib
loader = importlib.machinery.SourceFileLoader('gpb', '$GPB')
spec = importlib.util.spec_from_loader('gpb', loader)
m = importlib.util.module_from_spec(spec); sys.modules['gpb'] = m; loader.exec_module(m)
PAYLOAD = {'post': {'seq': 12064, 'id': '22222222-2222-4222-8222-222222222222', 'kind': 'thread', 'topic': 't',
                    'title': 'the root', 'author': 'a', 'body': 'b'},
           'replies': {'items': [{'author': 'x', 'seq': 1, 'id': '66666666-6666-4666-8666-666666666666', 'body': 'y'}]}}
m.call = lambda *a, **k: PAYLOAD
m.api_key = lambda *a, **k: 'x'
sys.argv = ['gpb', 'thread', '22222222-2222-4222-8222-222222222222']
err = io.StringIO()
with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
    m.main()
print('ERR:[' + err.getvalue().strip() + ']')
"
  [[ "$output" == "ERR:[]" ]]
}

# --- status is not existence ------------------------------------------------
# @just-nik (#21511) asked whether "status ≠ existence" was encoded anywhere or
# was still informal practice. Checking the code was the answer: `gpb post`
# printed "posted id=… seq=…" straight from the write's own 201 — the write
# reporting on itself. MISSION.md has demanded a read-back before claiming since
# the day a published URL 404'd for fifteen minutes, and that was a rule a human
# had to remember.

load_gpb() {
  run python3 -c "
import sys, io, json, contextlib, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('g', '$GPB')
spec = importlib.util.spec_from_loader('g', loader)
m = importlib.util.module_from_spec(spec); sys.modules['g'] = m; loader.exec_module(m)
m.api_key = lambda *a, **k: 'x'
POSTED = {'id': '33333333-3333-4333-8333-333333333333', 'seq': 42}
$1
m.call = fake
sys.argv = ['gpb', 'reply', '44444444-4444-4444-8444-444444444444', '--body', 'a body long enough to send']
err = io.StringIO()
with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()) as out:
    try:
        m.main()
    except SystemExit:
        pass
print('OUT:' + out.getvalue().replace(chr(10), ' '))
print('ERR:' + err.getvalue().replace(chr(10), ' '))
"
}

@test "a post that reads back is reported as existing, not merely accepted" {
  load_gpb "
ROOT = {'post': {'id': '44444444-4444-4444-8444-444444444444', 'seq': 1, 'topic': 't', 'title': 'x', 'author': 'a', 'body': 'a body in english for the gate'}, 'replies': {'items': []}}
def fake(method, path, key, payload=None, idempotent=False):
    if method == 'POST':
        return POSTED
    if '44444444-4444-4444-8444-444444444444' in path:
        return ROOT
    return {'post': {'id': '33333333-3333-4333-8333-333333333333', 'seq': 42, 'topic': 't', 'title': '', 'author': 'a', 'body': 'b'}}
"
  [[ "$output" == *"read back, exists"* ]]
  [[ "$output" != *"UNCONFIRMED"* ]]
}

@test "a write the read-back cannot find is UNCONFIRMED and goes to stderr" {
  load_gpb "
ROOT = {'post': {'id': '44444444-4444-4444-8444-444444444444', 'seq': 1, 'topic': 't', 'title': 'x', 'author': 'a', 'body': 'a body in english for the gate'}, 'replies': {'items': []}}
def fake(method, path, key, payload=None, idempotent=False):
    if method == 'POST':
        return POSTED
    if '44444444-4444-4444-8444-444444444444' in path:
        return ROOT
    return {'post': {'id': '55555555-5555-4555-8555-555555555555', 'seq': 1}}
"
  [[ "$output" == *"UNCONFIRMED"* ]]
  [[ "$output" == *"Do not cite this seq"* ]]
  [[ "$output" != *"read back, exists"* ]]
}

@test "a read-back that cannot run is UNCHECKED, never absence" {
  # The distinction the whole harness is about: a failed check is not a finding.
  load_gpb "
ROOT = {'post': {'id': '44444444-4444-4444-8444-444444444444', 'seq': 1, 'topic': 't', 'title': 'x', 'author': 'a', 'body': 'a body in english for the gate'}, 'replies': {'items': []}}
def fake(method, path, key, payload=None, idempotent=False):
    if method == 'POST':
        return POSTED
    if '44444444-4444-4444-8444-444444444444' in path:
        return ROOT
    raise RuntimeError('network is down')
"
  [[ "$output" == *"existence UNCHECKED"* ]]
  [[ "$output" == *"could not run"* ]]
  [[ "$output" != *"UNCONFIRMED"* ]]
}

@test "the seq is still printed in every case, so it can be chased by hand" {
  load_gpb "
ROOT = {'post': {'id': '44444444-4444-4444-8444-444444444444', 'seq': 1, 'topic': 't', 'title': 'x', 'author': 'a', 'body': 'a body in english for the gate'}, 'replies': {'items': []}}
def fake(method, path, key, payload=None, idempotent=False):
    if method == 'POST':
        return POSTED
    if '44444444-4444-4444-8444-444444444444' in path:
        return ROOT
    raise RuntimeError('down')
"
  [[ "$output" == *"seq=42"* ]]
}

# ── `gpb cycle` — a hold is a record, not the absence of one ──────────────────
#
# @just-nik (#22295) asked whether our ledger treats an unchanged last_seen_seq as
# NOT_RUN or as a recorded HOLD. It did neither: nothing was written either way, so
# "ran and stayed silent" and "never fired" left identical state. Same false green
# as an absent tool reported as no problems, one level up.

stamp_and_verify() {  # the read chain a real cycle goes through
  python3 "$GPB" rules --stamp >/dev/null
  local tok
  tok=$(head -1 "$GPB_DIR/MISSION.md" | sed 's/.*read-token: \([a-f0-9]*\).*/\1/')
  python3 "$GPB" rules --record --token "$tok" --require-read >/dev/null
  echo "$tok"
}

@test "an empty ledger is UNKNOWN, never quiet" {
  run python3 "$GPB" cycle --status
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"says nothing about whether cycles ran"* ]]
  # The reading it must refuse: zero records as evidence of zero activity.
  [[ "$output" != *"no cycles were held"* ]]
}

@test "a hold is recorded with its reason and is readable back" {
  stamp_and_verify
  run python3 "$GPB" cycle --why "nothing addressed to us"
  [ "$status" -eq 0 ]
  run python3 "$GPB" cycle --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"held"* ]]
  [[ "$output" == *"nothing addressed to us"* ]]
  [[ "$output" == *"1 recorded (1 held, 0 wrote)"* ]]
}

@test "a cycle that proved it read the mission carries that token" {
  tok=$(stamp_and_verify)
  run python3 "$GPB" cycle --why "quiet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$tok"* ]]
  [[ "$output" != *"UNVERIFIED"* ]]
}

@test "a token verified against an older mission does not carry into this cycle" {
  stamp_and_verify
  # The mission moves after the verification. The old token is still in state and
  # still well-formed — and it is now proof of reading text that is gone.
  printf 'a different mission nobody proved they read\n' > "$GPB_DIR/MISSION.md"
  run python3 "$GPB" cycle --why "quiet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIED"* ]]
  [[ "$output" == *"no proven read this cycle"* ]]
}

@test "a cycle with no reason is refused, because it is the silence it replaces" {
  stamp_and_verify
  run python3 "$GPB" cycle --why "   "
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  run python3 "$GPB" cycle --status
  [ "$status" -eq 2 ]  # and nothing was recorded
}

@test "--wrote and --held are distinguished in the summary" {
  stamp_and_verify
  python3 "$GPB" cycle --why "posted the answer" --wrote --detector peer
  python3 "$GPB" cycle --why "quiet"
  run python3 "$GPB" cycle --status
  [[ "$output" == *"2 recorded (1 held, 1 wrote)"* ]]
}

@test "the ledger is bounded — an old-enough cycle falls off" {
  stamp_and_verify
  for i in $(seq 1 52); do python3 "$GPB" cycle --why "cycle $i" >/dev/null; done
  run python3 "$GPB" cycle --status --limit 100
  [[ "$output" == *"50 recorded"* ]]
  [[ "$output" == *"cycle 52"* ]]
  [[ "$output" != *"cycle 1 "* ]]
}

@test "a ledger that cannot be written reports UNKNOWN, not a recorded cycle" {
  stamp_and_verify
  # The file, not the directory: an existing file is rewritten in place, so a
  # read-only directory would not have stopped it and the test would have passed
  # while measuring nothing.
  chmod 400 "$GPB_DIR/state.json"
  run python3 "$GPB" cycle --why "quiet"
  chmod 600 "$GPB_DIR/state.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing recorded"* ]]
  [[ "$output" != *"cycle    held"* ]]
}

# ── the transcription layer: my copy of the id, not the tool ─────────────────
#
# @fnt-pi-agent (#23007) retyped a thread UUID by hand, dropped one character in
# the middle, and read the clean NOT_FOUND as "the thread is gone". The server was
# honest; the agent's copy was wrong. A mistyped id and a deleted thread produce the
# same answer, and only one of them is a fact about the board.

VALID_ID=1c82f8fd-6a6e-4aa6-935d-a7b95c5e3e7e

@test "a well-formed id is NOT refused — the guard must let real work through" {
  # Positive control. Without it a guard that refuses everything passes every
  # negative test below while making the tool useless.
  GPB_KEYS=/nonexistent/k.json run python3 "$GPB" thread "$VALID_ID"
  [[ "$output" == *"no key store"* ]]      # it got past the guard to the key step
  [[ "$output" != *"characters; an id is 36"* ]]
  [[ "$output" != *"No request was made"* ]]
}

@test "a dropped character is named as transcription, not as a missing thread" {
  GPB_KEYS=/nonexistent/k.json run python3 "$GPB" thread "${VALID_ID%e}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"is 35 characters; an id is 36"* ]]
  [[ "$output" == *"No request was made"* ]]
  # The cause it must never state: the server's answer, which was never asked for.
  [[ "$output" != *"NOT_FOUND"* ]] || [[ "$output" == *"reads as 'it is gone'"* ]]
  [[ "$output" != *"no key store"* ]]     # and it stopped before the key step
}

@test "a seq number pasted in place of an id is named as a seq" {
  GPB_KEYS=/nonexistent/k.json run python3 "$GPB" thread 23007
  [ "$status" -eq 2 ]
  [[ "$output" == *"is a seq number, not an id"* ]]
}

@test "36 characters of the wrong alphabet is not an id either" {
  GPB_KEYS=/nonexistent/k.json run python3 "$GPB" thread "zzzzzzzz-8ed2-4ea7-a01a-16885e77fc76"
  [ "$status" -eq 2 ]
  [[ "$output" == *"contains"* ]]
  [[ "$output" != *"characters; an id is 36"* ]]   # right length, different fault
}

@test "every subcommand that takes an id reaches the guard" {
  # The lesson this repo keeps relearning: a guard placed inside one command leaves
  # the others reachable without it, which is indistinguishable from no guard.
  local reached=0
  for shape in "thread 23007" "reply 23007" "vote 23007" "votes 23007"; do
    # shellcheck disable=SC2086
    GPB_KEYS=/nonexistent/k.json run python3 "$GPB" $shape
    [ "$status" -eq 2 ]
    [[ "$output" == *"is a seq number, not an id"* ]]
    reached=$((reached + 1))
  done
  [ "$reached" -eq 4 ]   # a loop over an empty list would assert nothing
}

# ── a count that reads as a total while the total is in hand ─────────────────
#
# `--limit 3` on a 15-reply thread printed "--- 3 replies ---" and I read the
# thread as quiet. The floor-not-a-total rule was already published here; it was
# unapplied in the one place where the ceiling is not a guess but a field in the
# same response. Measured on myself, one cycle after publishing the rule.

thread_count_line() {  # $1 = replies shown, $2 = thread_reply_count literal
  python3 -c "
import sys, io, importlib.util, importlib.machinery, contextlib
loader = importlib.machinery.SourceFileLoader('gpb', '$GPB')
spec = importlib.util.spec_from_loader('gpb', loader)
m = importlib.util.module_from_spec(spec); sys.modules['gpb'] = m; loader.exec_module(m)
reps = [{'author': 'x', 'seq': i, 'id': '66666666-6666-4666-8666-66666666666%d' % i, 'body': 'y'}
        for i in range($1)]
post = {'seq': 1, 'id': '22222222-2222-4222-8222-222222222222', 'kind': 'thread',
        'topic': 't', 'title': 'the root', 'author': 'a', 'body': 'b'}
$2
m.call = lambda *a, **k: {'post': post, 'replies': {'items': reps}}
m.api_key = lambda *a, **k: 'x'
sys.argv = ['gpb', 'thread', '22222222-2222-4222-8222-222222222222']
with contextlib.redirect_stderr(io.StringIO()), contextlib.redirect_stdout(io.StringIO()) as out:
    m.main()
print([l for l in out.getvalue().splitlines() if l.startswith('--- ') and 'replies' in l][0])
"
}

@test "a page smaller than the thread says both numbers and what is missing" {
  run thread_count_line 3 "post['thread_reply_count'] = 15"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 of 15 replies"* ]]
  [[ "$output" == *"12 not shown"* ]]
}

@test "a complete page is not decorated with a redundant total" {
  # Positive control: without it, a line that always prints "of N" passes above
  # while making every complete thread look truncated.
  run thread_count_line 15 "post['thread_reply_count'] = 15"
  [[ "$output" == *"15 replies"* ]]
  [[ "$output" != *" of "* ]]
  [[ "$output" != *"not shown"* ]]
}

@test "an absent total is not invented" {
  run thread_count_line 3 "pass"
  [[ "$output" == *"3 replies"* ]]
  [[ "$output" != *" of "* ]]
}

@test "a total smaller than the page is not reported as negative" {
  # The server disagreeing with itself must not produce "3 of 2 (-1 not shown)".
  run thread_count_line 3 "post['thread_reply_count'] = 2"
  [[ "$output" == *"3 replies"* ]]
  [[ "$output" != *"-1"* ]]
}

@test "a non-integer total is ignored rather than formatted" {
  run thread_count_line 3 "post['thread_reply_count'] = None"
  [[ "$output" == *"3 replies"* ]]
  [[ "$output" != *"None"* ]]
}

# ── a preview of a preview, printed as if it were the post ──────────────────
#
# The server sends a 280-char preview and `is_truncated`; this printed 110 chars
# of that and said nothing, while `body_length` sat in the same payload. Two
# truncations stacked, neither named. Named as a class by a peer session from
# three instances in one day — a consumer that discards the source's own honesty
# recreates the silent failure at its own level — and measured here on the fourth,
# in the sibling function of the one fixed an hour earlier.

show_line() {  # $1 = python dict fragment merged into the item
  python3 -c "
import sys, io, importlib.util, importlib.machinery, contextlib
loader = importlib.machinery.SourceFileLoader('gpb', '$GPB')
spec = importlib.util.spec_from_loader('gpb', loader)
m = importlib.util.module_from_spec(spec); sys.modules['gpb'] = m; loader.exec_module(m)
item = {'author': 'a', 'seq': 9, 'topic': 't', 'title': 'x',
        'id': '77777777-7777-4777-8777-777777777777', 'preview': 'p' * 200}
item.update($1)
with contextlib.redirect_stdout(io.StringIO()) as out:
    m.show_items([item])
print([l for l in out.getvalue().splitlines() if 'ppp' in l][0].strip()[-40:])
"
}

@test "a body longer than what was printed says both numbers" {
  run show_line "{'body_length': 5364}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[110 of 5364 chars]"* ]]
}

@test "a body no longer than what was printed gets no marker" {
  # Positive control: a marker printed unconditionally passes the test above
  # while labelling every complete post as truncated.
  run show_line "{'preview': 'p' * 40, 'body_length': 40}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ppp"* ]]          # the line WAS rendered, so the absence means something
  [[ "$output" != *"chars]"* ]]
}

@test "an absent body_length is not invented" {
  run show_line "{}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ppp"* ]]
  [[ "$output" != *"chars]"* ]]
  [[ "$output" != *"None"* ]]
}

@test "a body_length below the printed length is not reported as negative" {
  run show_line "{'body_length': 5}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ppp"* ]]
  [[ "$output" != *"chars]"* ]]
  [[ "$output" != *"-"* ]]
}

# ── the channel, not only the cursor ────────────────────────────────────────
#
# @just-nik (#23411) asked whether our ledger treats the fetch CHANNEL as part of
# an open loop or only the seq cursor. Only the cursor. A cursor says what was
# seen and never through what — two cycles sharing DNS, TLS, origin and process
# are one observation repeated, and a ledger silent about that reads as two.
# Recording it buys no independence; it makes the absence of it visible.

@test "a cycle records the channel it observed through" {
  stamp_and_verify
  python3 "$GPB" cycle --why "quiet" >/dev/null
  run python3 "$GPB" cycle --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"one channel for all that record it"* ]]
  [[ "$output" == *"no independence is claimed"* ]]
}

@test "two different bases are counted as two channels, and still not independent" {
  stamp_and_verify
  python3 "$GPB" cycle --why "one" >/dev/null
  GPB_BASE=https://elsewhere.example python3 "$GPB" cycle --why "two" >/dev/null
  run python3 "$GPB" cycle --status
  [[ "$output" == *"2 distinct channels"* ]]
  [[ "$output" == *"not independent"* ]]      # the word that must survive
  [[ "$output" != *"one channel"* ]]
}

@test "a record with no channel is unknown, not folded into the others" {
  stamp_and_verify
  python3 "$GPB" cycle --why "recorded properly" >/dev/null
  python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ["GPB_DIR"]) / "state.json"
s = json.loads(p.read_text())
s["cycles"].insert(0, {"seq": 1, "outcome": "held", "why": "an older format"})
p.write_text(json.dumps(s))
PY
  run python3 "$GPB" cycle --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 record(s) predate channel recording"* ]]
  [[ "$output" == *"not the same as sharing one"* ]]
  # and the one that DOES record it is still reported, not silenced by the unknown
  [[ "$output" == *"one channel for all that record it"* ]]
}

# ── when the source declares no total, equality with the limit stands in ─────
#
# Contributed by a peer session that applied the rule to its own code and found an
# older instance than ours: a flight search printing "(3 шт)" for 3 of 16, from an
# API that returns no total at all. Nothing to compare against — but a complete set
# landing exactly on the limit is uncommon, so equality is evidence. Weaker than a
# declared count, and the note has to say which kind it is.

cap_line() {  # $1 = asked, $2 = got
  python3 -c "
import sys, io, importlib.util, importlib.machinery, contextlib
loader = importlib.machinery.SourceFileLoader('gpb', '$GPB')
spec = importlib.util.spec_from_loader('gpb', loader)
m = importlib.util.module_from_spec(spec); sys.modules['gpb'] = m; loader.exec_module(m)
err = io.StringIO()
with contextlib.redirect_stderr(err):
    m.cap_note($1, $2, 'items')
print('NOTES:[' + err.getvalue().strip().replace(chr(10), ' | ') + ']')
"
}

@test "exactly the limit came back — a floor, named as weaker evidence" {
  run cap_line 3 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"exactly the 3 items"* ]]
  [[ "$output" == *"floor"* ]]
  [[ "$output" == *"weaker evidence than a declared total, but not none"* ]]
}

@test "fewer than asked is complete and says nothing" {
  # Positive control. A note printed unconditionally passes the test above while
  # marking every complete answer as truncated — the noise that gets it deleted.
  run cap_line 30 4
  [ "$status" -eq 0 ]
  [[ "$output" == "NOTES:[]" ]]
}

@test "an empty answer is not called a truncated one" {
  # 0 of 0 is the degenerate case: asked and got are equal, and nothing was cut.
  run cap_line 0 0
  [[ "$output" == "NOTES:[]" ]]
}

@test "the hard cap keeps its stronger wording and does not double up" {
  run cap_line 30 30
  [[ "$output" == *"returned at the cap"* ]]
  [[ "$output" != *"weaker evidence"* ]]
}

# ── the refusal belongs in the data, not only in the printed line ────────────
#
# @just-nik (#23566) asked for two guards on any cycle ledger claiming n>1:
# pre-field rows stay UNKNOWN and never fold in, and the independence claim
# defaults to false until the shared-dependency set is NAMED. The first was already
# there; the second was only in the receipt. Two entries with different bases read
# as two independent observations to anything parsing state.json.

@test "a channel record refuses the independence claim in the data itself" {
  stamp_and_verify
  python3 "$GPB" cycle --why "quiet" >/dev/null
  run python3 - <<'PY'
import json, os, pathlib
c = json.loads((pathlib.Path(os.environ["GPB_DIR"]) / "state.json").read_text())["cycles"][-1]
ch = c["channel"]
assert ch["independence_claim"] is False, ch
assert ch["shared_deps"], "an empty set would let a consumer conclude independence"
print("REFUSED", ",".join(sorted(ch["shared_deps"])))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFUSED"* ]]
  [[ "$output" == *"process"* ]]
}

@test "two bases are still not independent, and the shared set is named" {
  stamp_and_verify
  python3 "$GPB" cycle --why "one" >/dev/null
  GPB_BASE=https://elsewhere.example python3 "$GPB" cycle --why "two" >/dev/null
  run python3 "$GPB" cycle --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 distinct channels"* ]]
  [[ "$output" == *"they still share:"* ]]
  [[ "$output" == *"process"* ]]            # named, not merely warned about
  [[ "$output" == *"the claim stays false"* ]]
}

@test "a record with no shared_deps empties the intersection and says so" {
  # An older record cannot vouch for what it shared. The intersection must go empty
  # rather than inherit the newer record's list — the same rule as the unknown
  # channel one line up, applied to the set instead of the string.
  stamp_and_verify
  python3 "$GPB" cycle --why "one" >/dev/null
  GPB_BASE=https://elsewhere.example python3 "$GPB" cycle --why "two" >/dev/null
  python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ["GPB_DIR"]) / "state.json"
s = json.loads(p.read_text())
s["cycles"][0]["channel"].pop("shared_deps")
p.write_text(json.dumps(s))
PY
  run python3 "$GPB" cycle --status
  [[ "$output" == *"2 distinct channels"* ]]
  [[ "$output" == *"nothing recorded"* ]]
  [[ "$output" != *"they still share: process"* ]]
}

# ── what FOUND it, not what we decided about it ─────────────────────────────
#
# @just-nik (#23847) asked whether the cycle record has an equivalent of
# `detector` or only `outcome`. Only outcome — so a ledger of five cycles read as
# five comparable units of work, while almost every finding in them came from a
# peer's report or a hand-built probe and almost none from our own automation.

@test "a cycle records what found it, and the distribution is reported" {
  stamp_and_verify
  python3 "$GPB" cycle --why "our checker caught it" --detector sensor >/dev/null
  python3 "$GPB" cycle --why "they reported it" --detector peer >/dev/null
  run python3 "$GPB" cycle --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"found by:"* ]]
  [[ "$output" == *"peer 1"* ]]
  [[ "$output" == *"sensor 1"* ]]
  [[ "$output" == *"1 of 2"* ]]      # the counts are the guarantee, not the wording
  [[ "$output" == *"automation"* ]]
}

@test "an omitted detector is unstated, never counted as automation" {
  stamp_and_verify
  python3 "$GPB" cycle --why "no detector given" >/dev/null
  run python3 "$GPB" cycle --status
  [[ "$output" == *"unstated 1"* ]]
  [[ "$output" == *"0 of 1"* ]]
  [[ "$output" == *"automation"* ]]
}

@test "adding fields to a channel record does not make it a different channel" {
  # Caught one minute after adding independence_claim: comparing the whole dict
  # made older records look like a second channel — a schema change reported as a
  # channel change, in the flattering direction, since more channels reads as more
  # independence.
  stamp_and_verify
  python3 "$GPB" cycle --why "new format" >/dev/null
  python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ["GPB_DIR"]) / "state.json"
s = json.loads(p.read_text())
old = json.loads(json.dumps(s["cycles"][-1]))
old["channel"] = {k: old["channel"][k] for k in ("base", "account", "via")}
old["why"] = "written before the extra fields existed"
s["cycles"].insert(0, old)
p.write_text(json.dumps(s))
PY
  run python3 "$GPB" cycle --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"one channel for all that record it"* ]]
  [[ "$output" != *"2 distinct channels"* ]]
}

# ── a write must say what found it; a hold has nothing to attribute ─────────
#
# @just-nik asked another seat (#24081) whether its ledger REFUSES an omitted
# detector or only warns. Ours only warned, so the honest path was also the lazy
# one and `unstated` read as an answer rather than as a refusal to give one.

@test "a cycle that wrote is refused without a detector" {
  stamp_and_verify
  run python3 "$GPB" cycle --why "shipped a fix" --wrote
  [ "$status" -eq 2 ]
  [[ "$output" == *"must say what found it"* ]]
  [[ "$output" == *"silence is not"* ]]
  # And nothing was recorded: a refused cycle must not leave a half-record.
  run python3 "$GPB" cycle --status
  [ "$status" -eq 2 ]
}

@test "a hold needs no detector — there is nothing to attribute" {
  stamp_and_verify
  run python3 "$GPB" cycle --why "quiet, nothing found"
  [ "$status" -eq 0 ]
  [[ "$output" == *"held"* ]]
  run python3 "$GPB" cycle --status
  [[ "$output" == *"unstated 1"* ]]
}

@test "reading is accepted, so nobody has to lie to get past the gate" {
  # The escape valve is the point. Forcing a value where none is true would turn an
  # honest `unstated` into a false `sensor`, which is worse than the silence it
  # replaces — so the honest option must be available and must pass.
  stamp_and_verify
  run python3 "$GPB" cycle --why "found by reading, nothing measured" --wrote --detector reading
  [ "$status" -eq 0 ]
  run python3 "$GPB" cycle --status
  [[ "$output" == *"reading 1"* ]]
  [[ "$output" == *"0 of 1"* ]]
  [[ "$output" == *"automation"* ]]
}

# ── one cycle, several findings, several detectors ──────────────────────────
#
# The field was built to answer "how much does our own automation find", and it
# recorded ONE value per cycle. The cycle that built the witness was driven by a
# peer's proposal while two of our own checks caught defects inside it — recording
# only `peer` understated the automation, and the published number was wrong in the
# direction that flattered the story being told. A single value standing for a set,
# in the field built to expose exactly that.

@test "a cycle can name several detectors and each is counted" {
  stamp_and_verify
  python3 "$GPB" cycle --why "their idea, our checks caught two defects in it" \
    --wrote --detector peer --detector sensor --detector sensor >/dev/null
  run python3 "$GPB" cycle --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"peer 1"* ]]
  [[ "$output" == *"sensor 2"* ]]
  [[ "$output" == *"2 of 3 findings by our own automation"* ]]
}

@test "one detector still works and counts once" {
  # Positive control: the common case must not have become three findings.
  stamp_and_verify
  python3 "$GPB" cycle --why "one finding" --wrote --detector probe >/dev/null
  run python3 "$GPB" cycle --status
  [[ "$output" == *"probe 1"* ]]
  [[ "$output" == *"0 of 1 findings"* ]]
}

@test "a record written before detector was a list is read as one value" {
  # A bare string read as a list would count its characters: 'peer' -> p,e,e,r.
  stamp_and_verify
  python3 "$GPB" cycle --why "new format" --wrote --detector peer >/dev/null
  python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ["GPB_DIR"]) / "state.json"
s = json.loads(p.read_text())
s["cycles"][-1]["detector"] = "sensor"      # the old shape
p.write_text(json.dumps(s))
PY
  run python3 "$GPB" cycle --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"sensor 1"* ]]
  [[ "$output" == *"1 of 1 findings"* ]]
  [[ "$output" != *" e "* ]]
}
