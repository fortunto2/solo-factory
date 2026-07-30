#!/bin/bash
# Check that this machine actually serves skills/rules FROM this repo.
#
# The failure mode it exists for: the `solo` plugin installed as a *copy* of
# solo-factory, so edits here never reached sessions, and skills got copied into
# ~/.claude/skills/ as a workaround — two truths, silently drifting.
#
# Usage: make doctor   (or ./scripts/doctor.sh)

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_JSON="$REPO/.claude-plugin/plugin.json"
INSTALLED_JSON="$HOME/.claude/plugins/installed_plugins.json"
CACHE_BASE="$HOME/.claude/plugins/cache/solo/solo"
USER_SKILLS="$HOME/.claude/skills"
USER_RULES="$HOME/.claude/rules"

fails=0
pass() { printf 'OK    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
hint() { printf '      → %s\n' "$1"; }

echo "solo-factory doctor — $REPO"
echo

# 1. Plugin cache must be a symlink to THIS repo, at the version in plugin.json.
VERSION="$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON'))['version'])" 2>/dev/null)"
CACHE_DIR="$CACHE_BASE/$VERSION"
if [[ -L "$CACHE_DIR" && "$(readlink "$CACHE_DIR")" == "$REPO" ]]; then
  pass "plugin cache $VERSION → repo (edits are live next session)"
elif [[ -e "$CACHE_DIR" ]]; then
  fail "plugin cache $VERSION is a COPY, not a symlink to the repo"
  hint "make plugin-link"
else
  fail "plugin cache $VERSION missing"
  hint "claude plugin install solo@solo --scope user && make plugin-link"
fi

# 2. installed_plugins.json must agree about the version.
if [[ -f "$INSTALLED_JSON" ]]; then
  registered="$(python3 -c "
import json
d = json.load(open('$INSTALLED_JSON'))
e = d.get('plugins', {}).get('solo@solo') or [{}]
print(e[0].get('version', ''))
" 2>/dev/null)"
  if [[ "$registered" == "$VERSION" ]]; then
    pass "installed_plugins.json version $registered"
  else
    fail "installed_plugins.json says '$registered', plugin.json says '$VERSION'"
    hint "make plugin-link"
  fi
fi

# 3. No skill may exist in both places — a duplicate is a fork waiting to happen.
dupes=()
for dir in "$REPO"/skills/*/; do
  name="$(basename "$dir")"
  [[ -e "$USER_SKILLS/$name" ]] && dupes+=("$name")
done
if ((${#dupes[@]} == 0)); then
  pass "no duplicate skills in ~/.claude/skills/"
else
  fail "skills exist in BOTH repo and ~/.claude/skills/: ${dupes[*]}"
  hint "diff them, keep the repo one, then: rm -rf ${dupes[*]/#/$USER_SKILLS/}"
fi

# 4. Every rule in the repo must be linked into ~/.claude/rules (loads every session).
unlinked=()
for rule in "$REPO"/rules/*.md; do
  name="$(basename "$rule")"
  target="$USER_RULES/$name"
  [[ -L "$target" && "$(readlink "$target")" == "$rule" ]] || unlinked+=("$name")
done
if ((${#unlinked[@]} == 0)); then
  pass "all $(ls "$REPO"/rules/*.md | wc -l | tr -d ' ') rules linked into ~/.claude/rules/"
else
  fail "rules not linked: ${unlinked[*]}"
  hint "make plugin-link (step 6 links rules/*.md)"
fi

# 5. Repo-level skill validation (frontmatter, names, versions).
if python3 "$REPO/scripts/check_skills.py" > /tmp/solo-doctor-skills.$$ 2>&1; then
  pass "$(tail -1 /tmp/solo-doctor-skills.$$ | sed 's/^OK *//')"
else
  fail "skill frontmatter problems:"
  sed 's/^/      /' /tmp/solo-doctor-skills.$$
fi
rm -f /tmp/solo-doctor-skills.$$

echo
if ((fails == 0)); then
  echo "All good — this machine serves skills and rules from the repo."
else
  echo "$fails problem(s). Fix the ones above, then re-run: make doctor"
fi
exit $((fails > 0))
