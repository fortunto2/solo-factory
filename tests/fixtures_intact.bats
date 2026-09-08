#!/usr/bin/env bats
# The published fixtures are broken on purpose, and must stay broken.
#
# fixtures/classification/ exists so an outside agent can check the
# classification contract on their own tree. Every file carries a defect
# deliberately, and the pack is worthless the moment one is repaired — which this
# repository's own pre-commit ruff did on the first commit that added it,
# removing the unused import that was the entire point of case 1.

C="${BATS_TEST_DIRNAME}/../scripts/check-fixtures"

@test "the pack is intact and says how many cases it checked" {
  run python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ([0-9]+)\ fixture\ case ]]
  [ "${BASH_REMATCH[1]}" -ge 3 ]
  [[ "$output" == *"0 repaired"* ]]
}

@test "a repaired case is caught and named" {
  run python3 -c "
import sys, pathlib, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('c', '$C')
spec = importlib.util.spec_from_loader('c', loader)
m = importlib.util.module_from_spec(spec); sys.modules['c'] = m; loader.exec_module(m)
import tempfile, json, shutil, os
d = pathlib.Path(tempfile.mkdtemp())
shutil.copytree(m.PACK, d / 'p')
# Repair case 1 the way ruff --fix would.
f = d / 'p' / '01_true_finding.py'
f.write_text(f.read_text().replace('import os\n', ''))
m.PACK = d / 'p'
sys.exit(m.main())
"
  [ "$status" -eq 1 ]
  [[ "$output" == *"01_true_finding.py"* ]]
  [[ "$output" == *"repaired and useless"* ]]
}

@test "a missing pack is UNKNOWN, never a clean bill" {
  run python3 -c "
import sys, pathlib, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('c', '$C')
spec = importlib.util.spec_from_loader('c', loader)
m = importlib.util.module_from_spec(spec); sys.modules['c'] = m; loader.exec_module(m)
m.PACK = pathlib.Path('/nonexistent/pack')
sys.exit(m.main())
"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing was checked"* ]]
}

@test "the linter leaves the fixtures alone" {
  # force-exclude, not exclude: pre-commit passes filenames explicitly and plain
  # `exclude` is ignored then. Without it the hook repaired the file anyway and
  # the exclusion looked like it was working.
  run uvx ruff check --no-fix "${BATS_TEST_DIRNAME}/../fixtures/classification/01_true_finding.py"
  [ "$status" -eq 0 ]
  [[ "$output" != *"F401"* ]]
}

@test "every expected bucket is one the derivation rules define" {
  # @huddora-ambassador-1857: a bucket name nobody can independently recompute
  # just moves the reproduction-comparison from our output string to our
  # vocabulary. A case expecting a bucket the rules never define is exactly that,
  # and a reader trusting the file would never see it.
  run python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 repaired"* ]]
}

@test "a bucket the rules do not define is caught" {
  run python3 -c "
import sys, json, shutil, tempfile, pathlib, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('c', '$C')
spec = importlib.util.spec_from_loader('c', loader)
m = importlib.util.module_from_spec(spec); sys.modules['c'] = m; loader.exec_module(m)
d = pathlib.Path(tempfile.mkdtemp()) / 'p'
shutil.copytree(m.PACK, d)
e = d / 'expected.json'
j = json.loads(e.read_text())
j['cases'][0]['expect'] = ['a_bucket_nobody_defined']
e.write_text(json.dumps(j))
m.PACK = d
sys.exit(m.main())
"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a_bucket_nobody_defined"* ]]
  [[ "$output" == *"cannot recompute"* ]]
}

@test "the derivation rules are stated in observable terms, not our wording" {
  F="${BATS_TEST_DIRNAME}/../fixtures/classification/expected.json"
  run python3 -c "
import json
d = json.load(open('$F'))
h = d['how_to_derive_the_bucket']
print(' '.join(x.split(':')[0] for x in h['observe']))
print('|'.join(h['buckets'].values()))
"
  # Both observables must be things any tool exposes: an exit status and whether
  # it pointed at the file.
  [[ "${lines[0]}" == *"exit"* ]]
  [[ "${lines[0]}" == *"named"* ]]
  # And the rules must be written in those terms, not in ours.
  [[ "${lines[1]}" == *"exit"* ]]
  [[ "${lines[1]}" == *"named"* ]]
}

@test "silence is its own bucket, not clean" {
  # @just-nik: silence-as-clean is the softest stranger fixture and the easiest
  # false green when a tool skips quietly. The first rules read `clean` as
  # "exit 0, not named, and nothing says it went unexamined" — mapping SILENCE
  # onto a positive claim of having looked.
  F="${BATS_TEST_DIRNAME}/../fixtures/classification/expected.json"
  run python3 -c "
import json
h = json.load(open('$F'))['how_to_derive_the_bucket']
print('unknown' in h['buckets'])
print(h['buckets']['clean'])
print(' '.join(o.split(':')[0] for o in h['observe']))
"
  [[ "${lines[0]}" == "True" ]]
  # clean must require a POSITIVE statement, never the absence of a negative one.
  [[ "${lines[1]}" == *"states it DID examine"* ]]
  [[ "${lines[1]}" != *"nothing says"* ]]
  # and the third observable must exist for that to be derivable at all
  [[ "${lines[2]}" == *"examined"* ]]
}

@test "our own verifier can be classified under the four-state rules" {
  # If solo-verify itself landed in `unknown`, the pack would be asking strangers
  # for a statement our own tool never makes. $REPO belongs to sensors.bats;
  # this file needs its own, which is what the first version got wrong.
  R="$BATS_TEST_TMPDIR/r"
  mkdir -p "$R"
  cp "${BATS_TEST_DIRNAME}/../fixtures/classification"/* "$R/"
  run bash -c "cd '$R' && python3 '${BATS_TEST_DIRNAME}/../scripts/solo-verify' \
       --root . --files 01_true_finding.py 2>&1"
  # The examined bit: a covered count or a per-sensor pass tally.
  [[ "$output" =~ [0-9]+\ covered ]] || [[ "$output" == *"=pass {"* ]]
  # And it must still name the defect, so the case is `finding` and not `clean`.
  [[ "$output" == *"01_true_finding.py:"* ]]
}

# ── the last hop: what a stranger actually fetches ─────────────────────────
#
# check-fixtures verifies the working tree. The invitation on the board points at
# raw.githubusercontent — so local -> committed -> pushed -> served is a chain whose
# last link nobody watched. An unpushed commit, or a push that failed, leaves the
# two saying different things while every local check stays green.

@test "the published pack is compared, and a local-only edit is caught" {
  F="$BATS_TEST_DIRNAME/../fixtures/classification/expected.json"
  cp "$F" "$BATS_TEST_TMPDIR/keep"
  printf '\n' >> "$F"
  run python3 "$BATS_TEST_DIRNAME/../scripts/check-fixtures" --published
  cp "$BATS_TEST_TMPDIR/keep" "$F"
  if [[ "$output" == *"UNCHECKED"* ]]; then
    skip "no network here — the comparison could not run, which the tool says itself"
  fi
  [ "$status" -eq 1 ]
  [[ "$output" == *"DIFFERS"* ]]
  [[ "$output" == *"expected.json"* ]]
  [[ "$output" == *"says nothing about what is served"* ]]
}

@test "a fetch that could not happen is UNCHECKED, never 'same'" {
  # An empty body and an identical body both compare equal to nothing, so offline
  # has to be its own answer. Forced with a proxy pointing at a closed port.
  run env http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 \
      python3 "$BATS_TEST_DIRNAME/../scripts/check-fixtures" --published
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNCHECKED"* ]]
  [[ "$output" == *"Offline is not agreement"* ]]
}

@test "without --published it still checks the working tree only" {
  # Positive control: the network check must not have replaced the local one, and
  # the local one must stay runnable with no network at all.
  run env http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 \
      python3 "$BATS_TEST_DIRNAME/../scripts/check-fixtures"
  [ "$status" -eq 0 ]
  [[ "$output" != *"raw.githubusercontent"* ]]
}

@test "a 200 with an empty body is UNCHECKED, not a match" {
  # An empty body and an identical body both compare equal to nothing. Against
  # GitHub there is no way to produce a 200 with no body, so the branch killed 0
  # tests until the URL became overridable — a guard nobody has seen fire.
  run python3 - <<'PY'
import http.server, socketserver, subprocess, sys, threading, os
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()
    def log_message(self, *a): pass
srv = socketserver.TCPServer(("127.0.0.1", 0), H)
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
root = os.path.dirname(os.path.dirname(os.path.abspath("tests/.")))
r = subprocess.run([sys.executable, "scripts/check-fixtures", "--published"],
                   env=dict(os.environ, SOLO_FIXTURE_RAW=f"http://127.0.0.1:{port}"),
                   capture_output=True, text=True, timeout=120)
srv.shutdown()
print(r.returncode)
print(r.stdout + r.stderr)
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"the fetch returned nothing"* ]]
  [[ "$output" == *"Offline is not agreement"* ]]
  [[ "$output" != *"match what"* ]]
}
