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
# The profile under examination. Claude Code reads CLAUDE_CONFIG_DIR when it is set, so a
# second profile has its own plugin cache, skills and rules. These four paths were hardcoded
# to ~/.claude, which made this check blind to every profile but the default: a work profile
# sat 35 versions behind the source, `make plugin-link` could not reach it, and doctor kept
# reporting the default profile as though it were the only one. Named in the header below, so
# a green report cannot be read as being about a profile it never looked at.
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
INSTALLED_JSON="$CLAUDE_HOME/plugins/installed_plugins.json"
CACHE_BASE="$CLAUDE_HOME/plugins/cache/solo/solo"
USER_SKILLS="$CLAUDE_HOME/skills"
USER_RULES="$CLAUDE_HOME/rules"

fails=0
pass() { printf 'OK    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
warn() { printf 'WARN  %s\n' "$1"; }
hint() { printf '      → %s\n' "$1"; }

echo "solo-factory doctor — $REPO"
echo "profile: $CLAUDE_HOME${CLAUDE_CONFIG_DIR:+  (from CLAUDE_CONFIG_DIR)}"
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

# 3. No repo skill may be reachable from $USER_SKILLS. The plugin already serves
#    every one of them as solo:<name>, so a second entry there is either a COPY
#    (forks, then drifts) or a symlink (registers one skill twice and spends
#    context on two descriptions of the same thing).
#    Both spellings are checked, and that is the hole this check had: the repo
#    directory is `plan`, the published skill name is `solo-plan`, and comparing
#    only the first made the real shape of the duplicate invisible. Measured
#    2026-09-12: 28 skills present under both routes, all 28 files different, the
#    copies six months old, and sessions had taken the stale route 7 times —
#    with this check printing OK throughout.
scanned=0
dupes=()
for dir in "$REPO"/skills/*/; do
  [[ -d "$dir" ]] || continue
  name="$(basename "$dir")"
  scanned=$((scanned + 1))
  for cand in "$name" "solo-$name"; do
    [[ -e "$USER_SKILLS/$cand" || -L "$USER_SKILLS/$cand" ]] && dupes+=("$cand")
  done
done
# Zero scope is never a pass: a repo with no skills/ would otherwise report
# "no duplicates" while having checked nothing.
if ((scanned == 0)); then
  fail "no skills in $REPO/skills — nothing was checked for duplicates"
elif ((${#dupes[@]} == 0)); then
  pass "no duplicate skills in $USER_SKILLS ($scanned skills, both spellings)"
else
  fail "reachable from BOTH the plugin and $USER_SKILLS: ${dupes[*]}"
  hint "the plugin serves these as solo:<name> — rm ${dupes[*]/#/$USER_SKILLS/}"
fi

# 3b. Other agents (codex, cursor, opencode) read a shared skills store instead of
#     this plugin, so a solo skill there is legitimate — as a SYMLINK into this
#     repo. A real directory is a snapshot, and a snapshot ages in silence: the one
#     found on this machine arrived via `npx skills add`, sat untouched for six
#     months, and Claude Code reached it through ~/.claude/skills the whole time.
#     The guard above could not see it, because it only ever looked in one store.
AGENT_SKILLS="${SOLO_AGENT_SKILLS:-$HOME/.agents/skills}"
if [[ ! -d "$AGENT_SKILLS" ]]; then
  pass "no $AGENT_SKILLS on this machine, so no shared store to check"
else
  REPO_REAL="$(cd "$REPO" && pwd -P)"
  forks=()
  for dir in "$REPO"/skills/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    for cand in "$name" "solo-$name"; do
      target="$AGENT_SKILLS/$cand"
      [[ -e "$target" || -L "$target" ]] || continue
      if [[ ! -L "$target" ]]; then
        forks+=("$cand=copy")
      elif ! resolved="$(cd "$target" 2>/dev/null && pwd -P)"; then
        forks+=("$cand=broken-link")
      elif [[ "$resolved" != "$REPO_REAL"/* ]]; then
        forks+=("$cand=points-outside-repo")
      fi
    done
  done
  if ((${#forks[@]} == 0)); then
    pass "solo skills in $AGENT_SKILLS point into the repo"
  else
    fail "stale solo skills in $AGENT_SKILLS: ${forks[*]}"
    hint "rm -rf the copy, then: ln -s $REPO/skills/<name> $AGENT_SKILLS/solo-<name>"
  fi
fi

# 3c. A project can register skills too (<project>/.claude/skills), and when this repo
#      is a submodule its parent is exactly such a project. Same defect as 3, one
#      directory over: 27 links there served `build` beside the plugin's `solo:build`,
#      two descriptions of one skill in every session opened in that tree. Checked for
#      the parent project only — doctor examines this machine's wiring, not every
#      checkout on the disk.
PROJECT_SKILLS="${SOLO_PROJECT_SKILLS:-$(dirname "$REPO")/.claude/skills}"
if [[ ! -d "$PROJECT_SKILLS" ]]; then
  pass "no $PROJECT_SKILLS, so the parent project registers no skills"
else
  shadowed=()
  for dir in "$REPO"/skills/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    for cand in "$name" "solo-$name"; do
      [[ -e "$PROJECT_SKILLS/$cand" || -L "$PROJECT_SKILLS/$cand" ]] && shadowed+=("$cand")
    done
  done
  if ((${#shadowed[@]} == 0)); then
    pass "parent project adds no copy of a plugin skill ($PROJECT_SKILLS)"
  else
    fail "plugin skills registered a second time in $PROJECT_SKILLS: ${shadowed[*]}"
    hint "the plugin serves these everywhere as solo:<name> — rm ${shadowed[*]/#/$PROJECT_SKILLS/}"
  fi
fi

# 4. Every rule in the repo must be linked into ~/.claude/rules (loads every session).
unlinked=()
for rule in "$REPO"/rules/*.md; do
  name="$(basename "$rule")"
  target="$USER_RULES/$name"
  [[ -L "$target" && "$(readlink "$target")" == "$rule" ]] || unlinked+=("$name")
done
# A profile with no rules directory keeps no rules, on purpose, and link-plugin.sh skips
# them there rather than handing a work profile five always-loaded files. Calling that a
# failure here made the two halves of this tool contradict each other.
if [[ ! -d "$USER_RULES" ]]; then
  pass "no rules directory in this profile, so none are expected"
elif ((${#unlinked[@]} == 0)); then
  pass "all $(ls "$REPO"/rules/*.md | wc -l | tr -d ' ') rules linked into $USER_RULES"
else
  fail "rules not linked: ${unlinked[*]}"
  hint "make plugin-link (step 6 links rules/*.md)"
fi

# 5. User CLAUDE.md ideally lives in a repo too (advisory — a plain file is valid,
#    it just isn't backed up or reviewable). Keep it in a PRIVATE repo: personal
#    preferences don't belong in this public one.
if [[ -L "$CLAUDE_HOME/CLAUDE.md" ]]; then
  pass "user CLAUDE.md → $(readlink "$CLAUDE_HOME/CLAUDE.md" | sed "s|$HOME|~|")"
elif [[ -f "$CLAUDE_HOME/CLAUDE.md" ]]; then
  warn "user CLAUDE.md is a plain file — not in any repo"
  hint "move it into a private repo and symlink it back to ~/.claude/CLAUDE.md"
fi

# 6. Repo-level skill validation (frontmatter, names, versions).
if python3 "$REPO/scripts/check_skills.py" > /tmp/solo-doctor-skills.$$ 2>&1; then
  pass "$(tail -1 /tmp/solo-doctor-skills.$$ | sed 's/^OK *//')"
else
  fail "skill frontmatter problems:"
  sed 's/^/      /' /tmp/solo-doctor-skills.$$
fi
rm -f /tmp/solo-doctor-skills.$$

# Committed and shipped are different things: this plugin is distributed by
# version string, so pushed work that nobody bumped the version for reaches no
# user while looking delivered. Reported here rather than as a pre-commit gate —
# a hook that fails every commit until you release teaches people to pass
# --no-verify, and a habitually bypassed gate is worse than none.
echo
if ! python3 "$(dirname "$0")/check-shippable"; then
  fails=$((fails + 1))
fi

echo
if ((fails == 0)); then
  echo "All good — this machine serves skills and rules from the repo."
else
  echo "$fails problem(s). Fix the ones above, then re-run: make doctor"
fi
exit $((fails > 0))
