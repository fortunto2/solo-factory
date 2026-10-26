#!/usr/bin/env bats
# secret_guard.py — credentials stay out of the conversation.
# Test values are built at runtime so this file holds no string that looks like a key.

G="${BATS_TEST_DIRNAME}/../hooks/secret_guard.py"

setup() {
  export SECRET_GUARD_DIR="$BATS_TEST_TMPDIR/secrets"
  OAI="sk-proj-$(printf 'Ab3%.0s' {1..12})"          # 36 chars after the prefix
  AWS="AKIA$(printf 'Q7%.0s' {1..8})"
}

post() {  # tool_response JSON -> hook output
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_response":json.loads(sys.argv[1])}))' "$1" \
    | python3 "$G" post
}

@test "a key in tool output is masked and the output keeps its structure" {
  out=$(post "{\"stdout\":\"OPENAI_API_KEY=$OAI\\nok\",\"stderr\":\"\",\"interrupted\":false}")
  [[ "$out" != *"$OAI"* ]]
  [[ "$out" == *"[REDACTED:"* ]]
  python3 -c 'import json,sys; o=json.loads(sys.argv[1])["hookSpecificOutput"]["updatedToolOutput"]; assert set(o)=={"stdout","stderr","interrupted"}; assert "OPENAI_API_KEY=" in o["stdout"]' "$out"
}

@test "nested output (Read's file.content) is masked too" {
  out=$(post "{\"type\":\"text\",\"file\":{\"filePath\":\".env\",\"content\":\"AWS=$AWS\"}}")
  [[ "$out" != *"$AWS"* ]]
  [[ "$out" == *"aws-access-key"* ]]
}

@test "clean output produces no hook output at all" {
  out=$(post '{"stdout":"hello world","stderr":""}')
  [ -z "$out" ]
}

@test "placeholders and code references are not secrets" {
  for v in 'API_KEY=your-api-key-here' 'TOKEN=${GITHUB_TOKEN}' 'SECRET=xxxxxxxxxxxxxxxx' \
           'API_KEY=os.environ.get("API_KEY")' 'AKIAIOSFODNN7EXAMPLE' 'password = request.form["pw"]'; do
    out=$(post "$(python3 -c 'import json,sys; print(json.dumps({"stdout":sys.argv[1]}))' "$v")")
    [ -z "$out" ] || { echo "false positive on: $v"; return 1; }
  done
}

@test "the same secret always gets the same id, different secrets different ids" {
  a=$(post "{\"stdout\":\"$OAI\"}" | grep -o 'id=[0-9a-f]*' | head -1)
  b=$(post "{\"stdout\":\"x $OAI y\"}" | grep -o 'id=[0-9a-f]*' | head -1)
  c=$(post "{\"stdout\":\"${OAI}Z\"}" | grep -o 'id=[0-9a-f]*' | head -1)
  [ "$a" = "$b" ]
  [ "$a" != "$c" ]
}

@test "writing a redaction marker into a file is refused" {
  out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"x.env","content":"K=[REDACTED:openai-key len=51 id=1234abcd]"}}' \
    | python3 "$G" pre)
  [[ "$out" == *'"deny"'* ]]
  out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"x.py","content":"print(1)"}}' | python3 "$G" pre)
  [ -z "$out" ]
}

@test "a pasted key blocks the prompt and lands in a 0600 file under its name" {
  out=$(python3 -c 'import json,sys; print(json.dumps({"prompt":"use this OPENAI_API_KEY="+sys.argv[1]+" please","cwd":"/tmp/myproj"}))' "$OAI" \
    | python3 "$G" prompt)
  [[ "$out" == *'"block"'* ]]
  [[ "$out" != *"$OAI"* ]]
  f="$SECRET_GUARD_DIR/myproj.env"
  grep -q "^OPENAI_API_KEY='$OAI'$" "$f"
  [ "$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")" = "600" ]
}

@test "pasting the same key twice does not duplicate it" {
  for _ in 1 2; do
    python3 -c 'import json,sys; print(json.dumps({"prompt":sys.argv[1],"cwd":"/tmp/p2"}))' "$AWS" | python3 "$G" prompt >/dev/null
  done
  [ "$(grep -c "$AWS" "$SECRET_GUARD_DIR/p2.env")" = "1" ]
}

@test "SECRET_GUARD=off disables masking" {
  out=$(SECRET_GUARD=off post "{\"stdout\":\"$OAI\"}")
  [ -z "$out" ]
}

@test "audit reports secrets in transcripts without printing their values" {
  mkdir -p "$BATS_TEST_TMPDIR/projects/-Users-x-proj"
  printf '{"message":"OPENAI_API_KEY=%s"}\n' "$OAI" > "$BATS_TEST_TMPDIR/projects/-Users-x-proj/s1.jsonl"
  run python3 "$G" audit "$BATS_TEST_TMPDIR/projects"
  [[ "$output" == *"1 distinct secrets"* ]]
  [[ "$output" != *"$OAI"* ]]
}

@test "scrub replaces values in old transcripts and leaves live ones alone" {
  d="$BATS_TEST_TMPDIR/tr"; mkdir -p "$d"
  printf '{"content":"Original prompt: key %s"}\n' "$OAI" > "$d/old.jsonl"
  printf '{"content":"key %s"}\n' "$OAI" > "$d/live.jsonl"
  touch -t 202601010000 "$d/old.jsonl"
  run python3 "$G" scrub "$d"
  run grep -q "$OAI" "$d/old.jsonl"; [ "$status" -ne 0 ]
  grep -q "REDACTED:openai-key" "$d/old.jsonl"
  grep -q "$OAI" "$d/live.jsonl"
  python3 -c 'import json,sys; json.loads(open(sys.argv[1]).readline())' "$d/old.jsonl"   # still valid JSON
}
