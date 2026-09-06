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
  printf 'x = 1\n' > "$REPO/clean.py"
  run bash -c "'$VERIFY' --root '$REPO' --json | python3 -c \"
import json,sys
for r in json.load(sys.stdin)['ran']:
    if r['status'] == 'pass' and 'violations' in r['counters']:
        assert r['counters']['violations'] == 0, r
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
