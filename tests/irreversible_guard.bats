#!/usr/bin/env bats
# irreversible_guard.py — an irreversible or outward command needs a human, decided from
# the command itself, never from state the agent can change.

G="${BATS_TEST_DIRNAME}/../hooks/irreversible_guard.py"

setup() {
  export SOLO_GUARD_LOG="$BATS_TEST_TMPDIR/guard.log"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/proj"; mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
  unset SOLO_ALLOW_DESTRUCTIVE
}

run_guard() {  # command, [mode] -> decision word or "none"
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","permission_mode":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "${2:-default}" \
    | python3 "$G" | python3 -c 'import json,sys; d=sys.stdin.read().strip(); print(json.loads(d)["hookSpecificOutput"]["permissionDecision"] if d else "none")'
}

@test "the table: dangerous commands are asked about, ordinary ones pass silently" {
  while IFS='|' read -r cmd want; do
    got=$(run_guard "$cmd")
    [ "$got" = "$want" ] || { echo "'$cmd': want $want, got $got"; return 1; }
  done <<'TABLE'
git push --force origin main|ask
git push -f|ask
git push --force-with-lease origin feat|ask
git push origin +main|ask
git -C repo push --delete origin old-branch|ask
git push origin :old-branch|ask
cd repo && git push origin --delete a b|ask
rm -rf /srv/data/project|ask
rm -r src|ask
gh repo delete owner/name --yes|ask
gh release delete v1.0|ask
git push|none
git push origin main|none
git push -u origin feature|none
git branch -d local-branch|none
git push --dry-run origin main|none
rm -rf /tmp/build-123|none
rm -rf $TMPDIR/x|none
rm -rf node_modules target dist|none
rm file.txt|none
rm -f a.log|none
echo "git push --force is dangerous"|none
TABLE
}

@test "bypassPermissions and dontAsk get a deny with a reason, because no prompt is guaranteed there" {
  [ "$(run_guard 'git push --force' bypassPermissions)" = deny ]
  [ "$(run_guard 'git push --force' dontAsk)" = deny ]
  [ "$(run_guard 'git push --force' auto)" = ask ]
}

@test "an inline VAR=1 prefix does not reach the guard; only the session environment does" {
  [ "$(run_guard 'SOLO_ALLOW_DESTRUCTIVE=1 git push --force' bypassPermissions)" = deny ]
  out=$(SOLO_ALLOW_DESTRUCTIVE=1 run_guard 'git push --force' bypassPermissions)
  [ "$out" = none ]
}

@test "a project pattern file adds project-specific deletes" {
  printf '# videos\nyt_upload\\.py\\s+delete\n' > "$CLAUDE_PROJECT_DIR/.claude/irreversible-commands.txt"
  [ "$(run_guard 'uv run scripts/yt_upload.py delete ABC --yes')" = ask ]
  [ "$(run_guard 'uv run scripts/yt_upload.py list')" = none ]
}

@test "every match is logged once as a JSON line; a pass is not logged" {
  run_guard 'git push --force' >/dev/null
  run_guard 'git push' >/dev/null
  [ "$(wc -l < "$SOLO_GUARD_LOG" | tr -d ' ')" = 1 ]
  python3 -c 'import json,sys; e=json.loads(open(sys.argv[1]).readline()); assert e["rule"]=="force-push" and e["decision"]=="ask"' "$SOLO_GUARD_LOG"
}

@test "other tools and broken input produce no output" {
  out=$(printf '{"tool_name":"Edit","tool_input":{"command":"git push --force"}}' | python3 "$G"); [ -z "$out" ]
  out=$(printf 'not json' | python3 "$G"); [ -z "$out" ]
}
