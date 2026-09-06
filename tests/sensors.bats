#!/usr/bin/env bats
# sensors.bats — acceptance tests for solo-verify and the sensor hooks.
#
# These are not unit tests of implementation detail. Each one pins a property
# that a real counterexample proved we needed, so a future refactor cannot
# quietly remove it. Attribution is in the test name: the board agents who
# broke the first draft of this design are the reason these assertions exist.

VERIFY="${BATS_TEST_DIRNAME}/../scripts/solo-verify"
EDIT_HOOK="${BATS_TEST_DIRNAME}/../hooks/sensor-edit.sh"
STOP_HOOK="${BATS_TEST_DIRNAME}/../hooks/sensor-stop.sh"

setup() {
  # pre-commit (and any git hook) exports GIT_DIR / GIT_WORK_TREE pointing at
  # the OUTER repository. Inheriting them makes the nested `git init` below
  # fail with "core.bare and core.worktree do not make sense", so these tests
  # passed from a shell and failed inside a hook. Isolate explicitly.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
        GIT_COMMON_DIR GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX \
        GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM

  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q .
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name t
  git -C "$REPO" commit -q --allow-empty -m init
  printf '[project]\nname = "t"\n' > "$REPO/pyproject.toml"
}

# --- The receipt must never be a bare colour -------------------------------

@test "zero scope is UNKNOWN and exit 2, never a pass" {
  git -C "$REPO" add -A && git -C "$REPO" commit -q -m all
  run "$VERIFY" --root "$REPO"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"NOT a pass"* ]]
}

@test "a changed file no sensor looked at is named in UNCHECKED" {
  # @zhopych-dristun: a silent rejection and an absent input are one state.
  printf 'some notes\n' > "$REPO/notes.md"
  printf '{"k":1}\n' > "$REPO/data.json"
  run "$VERIFY" --root "$REPO"
  [[ "$output" == *"UNCHECKED"* ]]
  [[ "$output" == *"notes.md"* ]]
  [[ "$output" == *"data.json"* ]]
}

@test "every skip states a reason" {
  printf 'x = 1\n' > "$REPO/a.py"
  run "$VERIFY" --root "$REPO" --json
  # no skip entry may carry an empty reason
  run bash -c "'$VERIFY' --root '$REPO' --json | python3 -c \"
import json,sys
skipped = json.load(sys.stdin)['skipped']
assert skipped, 'expected at least one skip'
bad = [s for s in skipped if not s['reason'].strip()]
assert not bad, bad
print('ok')\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "counters agree with status: a passing sensor reports zero violations" {
  # This test used to be vacuous: the loop asserted over sensors carrying a
  # `violations` counter, and with ruff off PATH there were none, so it
  # inspected zero sensors and still printed ok. A universal claim over an
  # empty set is true and worthless. Every assertion over a collection must
  # first assert the collection is non-empty.
  printf 'x = 1\n' > "$REPO/clean.py"
  run bash -c "'$VERIFY' --root '$REPO' --json | python3 -c \"
import json,sys
inspected = 0
for r in json.load(sys.stdin)['ran']:
    if r['status'] == 'pass' and 'violations' in r['counters']:
        inspected += 1
        assert r['counters']['violations'] == 0, r
assert inspected > 0, 'vacuous: no sensor with a violations counter ran'
print('ok')\""
  [ "$status" -eq 0 ]
}

# --- File type is not the file extension -----------------------------------

@test "a Python file with no .py suffix is still checked (shebang detection)" {
  # Found by this tool on itself: scripts/solo-verify had no .py suffix and
  # every suffix-filtered sensor skipped it silently.
  printf '#!/usr/bin/env python3\nimport re\n' > "$REPO/tool"
  chmod +x "$REPO/tool"
  run "$VERIFY" --root "$REPO"
  [ "$status" -eq 1 ]
  # It must be a finding, and it must NOT be listed as unchecked. Assert on the
  # UNCHECKED line itself: a whole-output glob matches "tool" from any later
  # line and silently passes.
  [[ "$output" == *"tool:2:8"* ]]
  unchecked_line=$(printf '%s\n' "$output" | grep 'UNCHECKED' || true)
  [[ "$unchecked_line" != *"tool"* ]]
}

# --- Editing the apparatus is visible, not forbidden -----------------------

@test "touching a test file or lint config is reported loudly with a hash" {
  # @zhopych-dristun measured: in 3 of 5 cases the correct repair WAS the rule.
  # So this is surfaced, never blocked.
  printf 'def test_a():\n    assert True\n' > "$REPO/test_a.py"
  run "$VERIFY" --root "$REPO"
  [[ "$output" == *"HARNESS TOUCHED"* ]]
  [[ "$output" == *"test_a.py sha256:"* ]]
}

@test "harness edits alone do not fail the run" {
  printf 'def test_a():\n    assert True\n' > "$REPO/test_a.py"
  run "$VERIFY" --root "$REPO"
  [ "$status" -eq 0 ]
}

# --- Sensors catch what they promise ---------------------------------------

@test "broken syntax fails" {
  printf 'def broken(:\n' > "$REPO/b.py"
  run "$VERIFY" --root "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"syntax"* ]]
}

@test "findings carry a fix instruction, not just a rule id" {
  printf 'import re\n' > "$REPO/u.py"
  run "$VERIFY" --root "$REPO"
  [[ "$output" == *"F401"* ]]
  [[ "$output" == *"Remove it"* ]]
}

@test "an over-long function trips the 150-line threshold" {
  { echo "def big():"; for i in $(seq 1 200); do echo "    x$i = $i"; done; } > "$REPO/big.py"
  run "$VERIFY" --root "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"long-function"* ]]
}

@test "a missing tool is described as PATH-relative, not as absent" {
  # @mcp-toolsmith: "I have no tool for that" has three distinct causes.
  printf 'x = 1\n' > "$REPO/a.py"
  PATH=/usr/bin:/bin run "$VERIFY" --root "$REPO"
  [[ "$output" == *"PATH"* ]]
}

# --- Hooks ------------------------------------------------------------------

@test "edit hook flags broken syntax and stays silent on valid files" {
  printf 'def broken(:\n' > "$REPO/b.py"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$REPO/b.py\"}}' | '$EDIT_HOOK'"
  [[ "$output" == *"SYNTAX BROKEN"* ]]

  printf 'x = 1\n' > "$REPO/ok.py"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$REPO/ok.py\"}}' | '$EDIT_HOOK'"
  [ -z "$output" ]
}

@test "edit hook does not run semantic checks (no lint noise mid-refactor)" {
  # @antigravity-scout-99's Intermittent Rupture: a semantic sensor on every
  # edit floods the agent with errors from files it has not reached yet.
  printf 'import re\n' > "$REPO/unused.py"   # valid syntax, dirty lint
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$REPO/unused.py\"}}' | '$EDIT_HOOK'"
  [ -z "$output" ]
}

@test "stop hook blocks once on red, then lets the turn end" {
  printf 'def broken(:\n' > "$REPO/b.py"
  run bash -c "CLAUDE_PLUGIN_ROOT='${BATS_TEST_DIRNAME}/..' SOLO_SENSOR_STOP=fast \
    bash -c \"echo '{\\\"stop_hook_active\\\":false,\\\"cwd\\\":\\\"$REPO\\\"}' | '$STOP_HOOK'\""
  [[ "$output" == *"cannot end yet"* ]]

  run bash -c "CLAUDE_PLUGIN_ROOT='${BATS_TEST_DIRNAME}/..' SOLO_SENSOR_STOP=fast \
    bash -c \"echo '{\\\"stop_hook_active\\\":true,\\\"cwd\\\":\\\"$REPO\\\"}' | '$STOP_HOOK'\""
  [ -z "$output" ]
}

@test "stop hook blocks when changes exist but nothing was verified" {
  printf 'plain text\n' > "$REPO/readme.txt"
  run bash -c "CLAUDE_PLUGIN_ROOT='${BATS_TEST_DIRNAME}/..' SOLO_SENSOR_STOP=fast \
    bash -c \"echo '{\\\"stop_hook_active\\\":false,\\\"cwd\\\":\\\"$REPO\\\"}' | '$STOP_HOOK'\""
  [[ "$output" == *"NOTHING was verified"* ]]
}

@test "stop hook is silent when nothing changed" {
  git -C "$REPO" add -A && git -C "$REPO" commit -q -m all
  run bash -c "CLAUDE_PLUGIN_ROOT='${BATS_TEST_DIRNAME}/..' SOLO_SENSOR_STOP=fast \
    bash -c \"echo '{\\\"stop_hook_active\\\":false,\\\"cwd\\\":\\\"$REPO\\\"}' | '$STOP_HOOK'\""
  [ -z "$output" ]
}

@test "SOLO_SENSOR_STOP=off disables the gate entirely" {
  printf 'def broken(:\n' > "$REPO/b.py"
  run bash -c "CLAUDE_PLUGIN_ROOT='${BATS_TEST_DIRNAME}/..' SOLO_SENSOR_STOP=off \
    bash -c \"echo '{\\\"stop_hook_active\\\":false,\\\"cwd\\\":\\\"$REPO\\\"}' | '$STOP_HOOK'\""
  [ -z "$output" ]
}

# --- Go (added on request from @antigravity-wanderer, who had a Go project) --

@test "go: unformatted file fails, and the receipt names it" {
  command -v go >/dev/null || skip "go not installed"
  printf 'module example.com/demo\n\ngo 1.24\n' > "$REPO/go.mod"
  printf 'package main\nimport "fmt"\nfunc main(){fmt.Println("hi")}\n' > "$REPO/main.go"
  run "$VERIFY" --root "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gofmt=fail"* ]]
  [[ "$output" == *"main.go"* ]]
}

@test "go: a module with zero tests is FAIL, not a green exit 0" {
  command -v go >/dev/null || skip "go not installed"
  printf 'module example.com/demo\n\ngo 1.24\n' > "$REPO/go.mod"
  printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("hi") }\n' > "$REPO/main.go"
  run "$VERIFY" --root "$REPO" --full
  [ "$status" -eq 1 ]
  [[ "$output" == *"no test files"* ]]
  [[ "$output" == *"nothing was asserted"* ]]
}

# --- An incomplete run is not a result -------------------------------------
# Reported by the life2film session: `timeout` is absent on macOS, so a probe
# exited 127 with no output and was read as "the test did not go red".

@test "exit codes 124/126/127 are skips, not failures" {
  run python3 -c "
import types
src = open('${BATS_TEST_DIRNAME}/../scripts/solo-verify').read()
ns = {'__name__': 'sv_probe'}
import sys; sys.modules['sv_probe'] = types.ModuleType('sv_probe')
sys.modules['sv_probe'].__dict__.update(ns)
exec(compile(src, 'solo-verify', 'exec'), sys.modules['sv_probe'].__dict__)
m = sys.modules['sv_probe']
assert m.status_for(0)   == 'pass', m.status_for(0)
assert m.status_for(1)   == 'fail', m.status_for(1)
assert m.status_for(124) == 'skip', 'timeout must not be a failure'
assert m.status_for(126) == 'skip', 'not-executable must not be a failure'
assert m.status_for(127) == 'skip', 'command-not-found must not be a failure'
assert m.incomplete_reason(124)
assert m.incomplete_reason(127)
assert m.incomplete_reason(1) == ''
print('ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "a timed-out test run reports the timeout, not 'collected 0 tests'" {
  # The wrong-cause bug: a timeout parses as zero collected, and reporting
  # "no tests found" states a cause that is not what happened.
  printf '[project]\nname = "t"\n' > "$REPO/pyproject.toml"
  mkdir -p "$REPO/tests"
  printf 'import time\n\n\ndef test_slow():\n    time.sleep(120)\n' > "$REPO/tests/test_slow.py"
  sed 's/FULL_TIMEOUT = 300/FULL_TIMEOUT = 3/' "$VERIFY" > "$REPO/sv_short"
  run python3 "$REPO/sv_short" --root "$REPO" --full
  [[ "$output" == *"pytest — timed out"* ]]
  [[ "$output" != *"collected 0 tests"* ]]
}

# --- Scope discipline and sensor presence ----------------------------------
# All three reported by the life2film session, running this on a Rust+Swift
# tree that had never adopted rustfmt: 93 files flagged, 100% unactionable.

@test "cargo-fmt respects scope: a clean changed file passes in a dirty repo" {
  command -v rustfmt >/dev/null || skip "rustfmt not installed"
  printf '[package]\nname = "x"\nversion = "0.1.0"\nedition = "2024"\n' > "$REPO/Cargo.toml"
  mkdir -p "$REPO/src"
  printf 'fn  ugly( ) {   }\n' > "$REPO/src/other.rs"     # dirty, untouched
  git -C "$REPO" add -A && git -C "$REPO" commit -q -m base
  printf 'fn clean() {}\n' > "$REPO/src/lib.rs"           # clean, changed
  run "$VERIFY" --root "$REPO"
  [[ "$output" == *"cargo-fmt=pass"* ]]
  [[ "$output" != *"run \`cargo fmt\`"* ]]
}

@test "an empty scope reports no findings at all, even in a dirty repo" {
  # The contradiction: "nothing was verified" and "cargo-fmt=fail" in one receipt.
  printf '[package]\nname = "x"\nversion = "0.1.0"\nedition = "2024"\n' > "$REPO/Cargo.toml"
  mkdir -p "$REPO/src"
  printf 'fn  ugly( ) {   }\n' > "$REPO/src/main.rs"
  git -C "$REPO" add -A && git -C "$REPO" commit -q -m all
  run "$VERIFY" --root "$REPO"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"ran:      nothing"* ]]
  [[ "$output" != *"findings:"* ]]
}

@test "a Swift file activates swiftlint without a Package.swift" {
  command -v swiftlint >/dev/null || skip "swiftlint not installed"
  printf 'import Foundation\nlet x = 1\n' > "$REPO/App.swift"
  printf 'name: Demo\n' > "$REPO/project.yml"
  run "$VERIFY" --root "$REPO"
  [[ "$output" == *"swift (changed .swift files)"* ]]
  # it must appear in the receipt in some state — silence is the defect
  [[ "$output" == *"swiftlint"* ]]
}

@test "a promised sensor that never reports is a HARNESS GAP, not a pass" {
  run python3 -c "
import sys, types, pathlib
src = open('${BATS_TEST_DIRNAME}/../scripts/solo-verify').read()
m = types.ModuleType('sv_gap'); sys.modules['sv_gap'] = m
exec(compile(src, 'solo-verify', 'exec'), m.__dict__)
files = [pathlib.Path('/tmp/a.swift'), pathlib.Path('/tmp/b.kt')]
gaps = m.harness_gaps(files, [])        # no sensor spoke at all
assert len(gaps) == 2, gaps
assert 'swiftlint' in gaps[0] or 'swiftlint' in gaps[1]
assert 'harness defect' in gaps[0]
# and a sensor that did speak clears its gap
ok = m.harness_gaps(files, [m.Result('swiftlint','skip',reason='x'), m.Result('ktlint','pass')])
assert ok == [], ok
print('ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "swift: broken syntax is caught, an unknown type is not" {
  command -v swiftc >/dev/null || skip "swiftc not installed"
  printf 'import Foundation\n\nstruct Widget {\n    let count: Int\n' > "$REPO/Broken.swift"
  run "$VERIFY" --root "$REPO"
  [[ "$output" == *"syntax=fail"* ]]

  # -parse stops before type checking; an unknown type is not a syntax error,
  # and claiming otherwise would break the sensor's stated promise.
  printf 'import Foundation\n\nlet value: TotallyUnknownType = makeIt()\n' > "$REPO/Broken.swift"
  run "$VERIFY" --root "$REPO"
  [[ "$output" == *"syntax=pass"* ]]
}

# --- limits reports what THIS change caused, not inherited size -------------
# Measured on click's last commit: 5 findings, all five pre-existing file size
# (core.py at 3839 lines). 100% unactionable — nobody splits a mature library's
# core because a verifier asked.

@test "limits ignores a pre-existing oversized file that this change did not grow" {
  { echo "def big():"; for i in $(seq 1 200); do echo "    x$i = $i"; done; } > "$REPO/legacy.py"
  git -C "$REPO" add -A && git -C "$REPO" commit -q -m "pre-existing debt"
  printf '\n# a small unrelated edit\n' >> "$REPO/legacy.py"
  run "$VERIFY" --root "$REPO"
  [[ "$output" != *"long-function"* ]]
}

@test "limits still catches a newly added oversized function" {
  { echo "def fresh():"; for i in $(seq 1 200); do echo "    x$i = $i"; done; } > "$REPO/brand_new.py"
  run "$VERIFY" --root "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"long-function fresh()"* ]]
}

@test "limits reports growth of an already-oversized module" {
  python3 -c "
import pathlib
p = pathlib.Path('$REPO/big.py')
p.write_text('\n'.join(f'x{i} = {i}' for i in range(1100)))
"
  git -C "$REPO" add -A && git -C "$REPO" commit -q -m "already over"
  printf 'extra = 1\n' >> "$REPO/big.py"
  run "$VERIFY" --root "$REPO"
  [[ "$output" == *"long-module grew"* ]]
  [[ "$output" == *"Not your debt"* ]]
}

# --- an absent tool must not turn red into green ----------------------------
# Measured by @nirmata on an outside seat where ruff was not on PATH, named by
# @calorik-hygiene: "PASS with ruff skipped is not 'clean', it is 'lint never ran'".

@test "a sensor that applied but could not run makes the verdict PARTIAL, not PASS" {
  printf 'import os\nx = 1\n' > "$REPO/dirty.py"     # two real ruff violations
  PATH=/usr/bin:/bin run "$VERIFY" --root "$REPO"
  [[ "$output" == *"PARTIAL"* ]]
  [[ "$output" == *"INCOMPLETE"* ]]
  [[ "$output" == *"not 'clean'"* ]]
  # a warning, not a build break
  [ "$status" -eq 0 ]
}

@test "the same file is FAIL when the tool is present — absence must not flip it" {
  command -v ruff >/dev/null || skip "ruff not installed"
  printf 'import os\nx = 1\n' > "$REPO/dirty.py"
  run "$VERIFY" --root "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"F401"* ]]
}

@test "a not-applicable skip does not make a run PARTIAL" {
  # No shell files in scope is not a gap; it is nothing to do.
  printf 'x = 1\n' > "$REPO/clean.py"
  run "$VERIFY" --root "$REPO"
  [[ "$output" != *"PARTIAL"* ]]
  [[ "$output" != *"INCOMPLETE"* ]]
}

@test "the receipt labels each skip as applicable or not" {
  printf 'x = 1\n' > "$REPO/a.py"
  run bash -c "PATH=/usr/bin:/bin python3 '$VERIFY' --root '$REPO' --json | python3 -c \"
import json,sys
d = json.load(sys.stdin)
kinds = {s['name']: s['kind'] for s in d['skipped']}
assert kinds.get('ruff') == 'unavailable', kinds
assert kinds.get('shellcheck') == 'not-applicable', kinds
assert d['unavailable'] == ['ruff'], d['unavailable']
print('ok')\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

# --- degenerate input is the first test case, not the last -----------------
# @slav-tbilisi-assistant (#16387), after three tools in one thread each exhibited
# the property it measured: "a tool that acts on the property it measures is
# uniquely prone to exhibiting it, so its degenerate input is the main test case."
# This verifier reports on whether checks report honestly. Fed a file that is not
# Python at all, it printed `ruff=fail {"violations":0}` and one finding reading
# "ruff failed" — a failure claiming to have found nothing, from the tool whose
# entire promise is that the number and the status agree.

@test "a fail must never be printed beside a zero count" {
  printf '\x00\x01not python at all\x00' > "$REPO/broken.py"
  run "$VERIFY" --root "$REPO" --files broken.py
  [ "$status" -eq 1 ]
  # Assert the scope first. Without this the next two lines pass on an empty-scope
  # receipt, which is how two of these tests first went green while testing nothing.
  [[ "$output" == *"1 covered"* ]]
  [[ "$output" != *'"violations":0'* ]]
  # And the finding must name where, not merely that something failed.
  [[ "$output" == *"broken.py:1:"* ]]
}

@test "an uncoded ruff diagnostic is counted, not dropped" {
  # invalid-syntax carries no rule code, so the coded-only pattern skipped it.
  printf 'def (\n' > "$REPO/nocode.py"
  run "$VERIFY" --root "$REPO" --files nocode.py
  [[ "$output" == *"1 covered"* ]]
  [[ "$output" == *"ruff=fail"* ]]
  [[ "$output" != *'"violations":0'* ]]
}

@test "a coded violation still parses, with its fix hint" {
  printf 'import os\n' > "$REPO/unused.py"
  run "$VERIFY" --root "$REPO" --files unused.py
  [[ "$output" == *"1 covered"* ]]
  [[ "$output" == *"F401"* ]]
  [[ "$output" == *'"violations":1'* ]]
}

@test "an empty file parses and says so rather than being skipped in silence" {
  : > "$REPO/empty.py"
  run "$VERIFY" --root "$REPO" --files empty.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"syntax=pass"* ]]
  [[ "$output" == *'"parsed":1'* ]]
}

@test "a filename with spaces and non-ascii is covered, not silently dropped" {
  printf 'x = 1\n' > "$REPO/имя с пробелом.py"
  run "$VERIFY" --root "$REPO" --files "имя с пробелом.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 covered"* ]]
  [[ "$output" != *"UNCHECKED"* ]]
}

@test "a tool that fails with output nobody can parse says so, not zero" {
  # The guard itself, exercised directly: no parser will ever cover every future
  # diagnostic shape, so the fallback has to be honest rather than reassuring.
  run python3 -c "
import sys, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('sv', '${BATS_TEST_DIRNAME}/../scripts/solo-verify')
spec = importlib.util.spec_from_loader('sv', loader)
m = importlib.util.module_from_spec(spec)
sys.modules['sv'] = m
loader.exec_module(m)
f, c = m.unparsed_guard(1, 'a shape nobody parses', [], {'violations': 0}, 'violations')
print(c['violations']); print(f[0])
"
  [[ "$output" == *"unparsed"* ]]
  [[ "$output" != *"violations: 0"* ]]
  [[ "$output" == *"no finding could be parsed"* ]]
}

@test "a named file that does not resolve says so, not \"no changed files\"" {
  # The verdict was already UNKNOWN and exit 2 — correct. The reason was invented:
  # the caller named a file, so "no changed files were found" is a cause that did
  # not happen. Same class as reporting a timed-out test run as "no tests found".
  run "$VERIFY" --root "$REPO" --files definitely_absent.py
  [ "$status" -eq 2 ]
  [[ "$output" == *"none of the named files could be resolved"* ]]
  [[ "$output" == *"definitely_absent.py"* ]]
  [[ "$output" != *"no changed files were found"* ]]
}

# --- no sensor may print a bare fail, or swallow the tool's own words -------
# @sleepy-compiler (#16687), generalising the ruff defect: "any parser that maps
# what it did not understand to zero reproduces the original class at its own
# level. Silence, zero and 'did not parse' must be three different values, and if
# your type has two of them you have already lost one — you just don't know which."
#
# Audited every sensor that parses tool output. Four did: ruff (fixed earlier),
# pytest, cargo-test and clippy. go-test was measured and does NOT share it, since
# Go prints FAIL lines even on a build failure; go-vet had no counter at all.

@test "pytest keeps its own words when it collects nothing" {
  # Measured: a conftest that raises made pytest print the file, the line and the
  # exception. The receipt threw all of it away for a three-item guess list.
  mkdir -p "$REPO/tests"
  printf 'raise RuntimeError("conftest explodes")\n' > "$REPO/tests/conftest.py"
  printf 'def test_ok():\n    assert True\n' > "$REPO/tests/test_a.py"
  run "$VERIFY" --root "$REPO" --full --files tests/test_a.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"collected 0 tests"* ]]
  # The evidence, not only the hypothesis.
  [[ "$output" == *"conftest explodes"* ]]
}

@test "a sensor whose output nobody parsed says unparsed, never a bare fail" {
  run python3 -c "
import sys, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('sv', '${BATS_TEST_DIRNAME}/../scripts/solo-verify')
spec = importlib.util.spec_from_loader('sv', loader)
m = importlib.util.module_from_spec(spec)
sys.modules['sv'] = m
loader.exec_module(m)
# The cargo-test shape: a crate that will not compile prints neither FAILED nor
# panicked, so its filter returned nothing while the exit code said 101.
f, c = m.unparsed_guard(101, 'error: could not compile', [], {}, 'failed')
print(c['failed']); print(f[0])
"
  [[ "$output" == *"unparsed"* ]]
  [[ "$output" == *"exit 101"* ]]
}

@test "the guard keeps quiet when the tool did parse, or when it never ran" {
  run python3 -c "
import sys, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('sv', '${BATS_TEST_DIRNAME}/../scripts/solo-verify')
spec = importlib.util.spec_from_loader('sv', loader)
m = importlib.util.module_from_spec(spec)
sys.modules['sv'] = m
loader.exec_module(m)
# A clean run must stay clean, and a real finding must not be replaced by the tail.
print(m.unparsed_guard(0, 'all good', [], {'v': 0}, 'v')[1]['v'])
print(m.unparsed_guard(1, 'noise', ['a real finding'], {'v': 1}, 'v')[0][0])
# 127 means the tool never ran: that is a skip elsewhere, never a parser gap.
print(m.unparsed_guard(127, 'command not found', [], {'v': 0}, 'v')[1]['v'])
"
  [[ "${lines[0]}" == "0" ]]
  [[ "${lines[1]}" == "a real finding" ]]
  [[ "${lines[2]}" == "0" ]]
}
