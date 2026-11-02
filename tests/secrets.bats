#!/usr/bin/env bats
# skills/secrets/scripts/secret — scan, registry due dates, keystore round trip.
# Fake values are built at runtime so this file holds no string that looks like a key
# (the scanner would otherwise flag its own tests).

S="${BATS_TEST_DIRNAME}/../skills/secrets/scripts/secret"
G="${BATS_TEST_DIRNAME}/../hooks/secret_guard.py"

setup() {
  # A git hook runs this suite with GIT_DIR/GIT_INDEX_FILE set to the real repository:
  # left in place, `git init` below reinitialises THAT repo (it once set core.bare=true).
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_OBJECT_DIRECTORY
  export SECRETS_REGISTRY="$BATS_TEST_TMPDIR/registry.json"
  export SECRETS_BACKEND=file
  export SECRETS_FILE_STORE="$BATS_TEST_TMPDIR/store"
  export SECRETS_TODAY=2026-06-01
  GHT="ghp_$(printf 'Zq7%.0s' {1..12})"                 # 36 chars after the prefix
  CFT="cfut_$(printf 'Kp4x%.0s' {1..10})"               # 40 chars after the prefix
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R"
  git -C "$R" init -q
  printf '.env\n' > "$R/.gitignore"
}

@test "a planted token is found, masked to 4 chars + length, and its value never printed" {
  printf 'GITHUB_TOKEN=%s\n' "$GHT" > "$R/notes.sh"
  run "$S" scan "$R"
  [ "$status" -eq 1 ]
  [[ "$output" != *"$GHT"* ]]
  [[ "$output" == *"github-token"* ]]
  [[ "$output" == *"ghp_…(40)"* ]]
  [[ "$output" == *"HIGH     untracked"* ]]
}

@test "tracked in git is critical, gitignored is medium" {
  printf 'token: %s\n' "$CFT" > "$R/config.yaml"
  printf 'API_KEY=%s\n' "$CFT" > "$R/.env"
  git -C "$R" add config.yaml && git -C "$R" -c user.email=t@example.com -c user.name=t commit -qm x
  "$S" scan "$R" --json > "$BATS_TEST_TMPDIR/out.json" 2>/dev/null || true
  python3 - "$BATS_TEST_TMPDIR/out.json" <<'EOF'
import json, sys
hits = json.load(open(sys.argv[1]))
by = {h["file"].rsplit("/", 1)[1]: h for h in hits}
assert by["config.yaml"]["severity"] == "critical" and by["config.yaml"]["where"] == "tracked", by
assert by[".env"]["severity"] == "medium" and by[".env"]["where"] == "ignored", by
assert by["config.yaml"]["rule"] == "cloudflare-token", by
EOF
}

@test "hashes, UUIDs, references and placeholders are not flagged" {
  sha=$(printf 'x' | shasum | cut -c1-40)
  cat > "$R/settings.yaml" <<EOF
commit: $sha
request_id: 123e4567-e89b-12d3-a456-426614174000
checksum_sha256: $(printf 'x' | shasum -a 256 | cut -c1-64)
api_key: \${API_KEY}
password: your-password-here
token_url: https://example.com/oauth/token
max_tokens: 4096
client_secret: CLIENT_SECRET_FROM_ENV
auth_token: config.authToken
EOF
  printf 'password = request.form["pw"]\napi_key = os.environ["API_KEY"]\n' > "$R/app.py"
  run "$S" scan "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scan: 0 findings"* ]]
}

@test "an assigned high-entropy value in a config file is flagged by name, a short sample in a test is not" {
  rnd=$(python3 -c 'import random; r = random.Random(7); print("".join(r.choice("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(32)))')
  printf 'STRIPE_SECRET=%s\n' "$rnd" > "$R/deploy.env"
  mkdir -p "$R/tests"
  printf 'const token = "test-token-1";\n' > "$R/tests/auth.test.ts"
  run "$S" scan "$R"
  [[ "$output" == *"deploy.env:1  assigned-secret  STRIPE_SECRET"* ]]
  [[ "$output" != *"auth.test.ts"* ]]
}

@test "a Supabase anon JWT is low (public by design); key files are found by name" {
  b64() { printf '%s' "$1" | base64 | tr -d '=\n' | tr '/+' '_-'; }
  jwt="$(b64 '{"alg":"HS256","typ":"JWT"}').$(b64 '{"iss":"supabase","role":"anon","exp":1999999999}').$(printf 'Sg9%.0s' {1..10})"
  printf 'SUPABASE_ANON_KEY=%s\n' "$jwt" > "$R/.env"
  printf 'k' > "$R/AuthKey_TEST000001.p8"
  run "$S" scan "$R"
  [[ "$output" == *"LOW      ignored"*"jwt"*"role=anon"* ]]
  [[ "$output" == *"AuthKey_TEST000001.p8  apple-api-key"* ]]
}

@test "set reads the value from stdin, get returns it, exec injects it into one command" {
  printf '%s' "$GHT" | "$S" set example-api-token --class api-scoped --used-in demo
  [ "$("$S" get example-api-token)" = "$GHT" ]
  run "$S" exec example-api-token=DEMO_TOKEN -- sh -c 'test "$DEMO_TOKEN" = "'"$GHT"'" && echo injected'
  [ "$output" = "injected" ]
  run "$S" list --no-check
  [[ "$output" == *"example-api-token"* ]]
  [[ "$output" != *"$GHT"* ]]
  ! grep -q "$GHT" "$SECRETS_REGISTRY"
}

@test "due dates: class period from last rotation, leaked is due now, overdue exits 1" {
  cat > "$SECRETS_REGISTRY" <<'EOF'
{"version": 1, "secrets": {
  "old-admin":  {"service": "a", "account": "u", "class": "prod-admin",   "last_rotated": "2026-01-01"},
  "fresh-api":  {"service": "b", "account": "u", "class": "api-scoped",   "last_rotated": "2026-05-01"},
  "low-year":   {"service": "c", "account": "u", "class": "personal-low", "created": "2025-06-15"},
  "custom":     {"service": "d", "account": "u", "class": "api-scoped",   "rotate_days": 10, "last_rotated": "2026-05-25"}
}}
EOF
  run "$S" due
  [ "$status" -eq 1 ]
  [[ "$output" == *"OVERDUE  old-admin  (61 days overdue)"* ]]   # 2026-01-01 + 90 = 2026-04-01
  [[ "$output" == *"due      low-year  in 14 days (2026-06-15)"* ]]
  [[ "$output" == *"due      custom  in 3 days (2026-06-04)"* ]]
  [[ "$output" != *"fresh-api"* ]]                                # due 2026-10-28, outside 30 days
  "$S" leak fresh-api --where "pasted in a chat"
  run "$S" due
  [[ "$output" == *"OVERDUE  fresh-api  (leaked: pasted in a chat)"* ]]
  [[ "$output" == *"rotation: 2 overdue of 4 registered"* ]]
  printf 'new-value-Q1w2e3r4' | "$S" rotate fresh-api 2>/dev/null
  run "$S" due
  [[ "$output" == *"rotation: 1 overdue of 4 registered"* ]]
  python3 -c 'import json,sys; e=json.load(open(sys.argv[1]))["secrets"]["fresh-api"]; assert e["class"]=="api-scoped" and e["last_rotated"]=="2026-06-01" and "leaked" not in e, e' "$SECRETS_REGISTRY"
}

@test "migrate moves a nested YAML value into the store and --remove blanks it" {
  printf 'cloud:\n  api_token: "%s"\n  account_id: "abc"\nother:\n  api_token: "keep"\n' "$CFT" > "$R/conf.yaml"
  run "$S" migrate "$R/conf.yaml" cloud.api_token example-cloud-token --remove
  [ "$status" -eq 0 ]
  [[ "$output" != *"$CFT"* ]]
  [ "$("$S" get example-cloud-token)" = "$CFT" ]
  grep -q '^  api_token: ""' "$R/conf.yaml"
  grep -q 'keep' "$R/conf.yaml"
  ! grep -q "$CFT" "$R/conf.yaml"
}

@test "check prints one counted line for a health check" {
  printf 'GITHUB_TOKEN=%s\n' "$GHT" > "$R/run.sh"
  run "$S" check "$R"
  [ "$status" -eq 1 ]
  [[ "${lines[-1]}" == "secrets: 0 critical, 1 high, 0 medium plaintext findings; 0 of 0 registered overdue for rotation" ]]
}

@test "the scanner knows every token rule the prompt guard knows" {
  run python3 - "$S" "$G" <<'EOF'
import importlib.machinery, importlib.util, sys
def load(p, n):
    spec = importlib.util.spec_from_loader(n, importlib.machinery.SourceFileLoader(n, p))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
scan, guard = load(sys.argv[1], "scan"), load(sys.argv[2], "guard")
missing = {r for r, _ in guard.TOKEN_RULES} - {r for r, _ in scan.TOKEN_RULES}
assert not missing, missing
print(f"{len(guard.TOKEN_RULES)} guard rules covered")
EOF
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\ guard\ rules\ covered$ ]]
}
