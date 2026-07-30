#!/bin/bash
# Scaffold a new skill in the ONE place skills belong: solo-factory/skills/.
#
# Exists so an agent never has to decide where a skill goes — the decision that
# previously ended with a copy in ~/.claude/skills/ drifting away from git.
#
# Usage: make new-skill S=my-skill

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"

if [[ -z "$NAME" ]]; then
  echo "Usage: make new-skill S=<name>    (kebab-case, e.g. S=play-billing)" >&2
  exit 1
fi
if [[ ! "$NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "Name must be kebab-case, lowercase: '$NAME' is not." >&2
  exit 1
fi

SKILL_DIR="$REPO/skills/$NAME"
if [[ -e "$SKILL_DIR" ]]; then
  echo "Already exists: skills/$NAME — edit skills/$NAME/SKILL.md instead." >&2
  exit 1
fi
if [[ -e "$HOME/.claude/skills/$NAME" ]]; then
  echo "A personal skill with this name already lives in ~/.claude/skills/$NAME." >&2
  echo "Two skills with one name = the drift this script prevents. Rename, or move that one here." >&2
  exit 1
fi

mkdir -p "$SKILL_DIR"
cat > "$SKILL_DIR/SKILL.md" <<EOF
---
name: solo-$NAME
description: <what it does, in one line>. Use when user says "<phrase they'd actually type>", "<another>", or <situation that should trigger this>. Do NOT use for <the neighbouring skill's job> (use /<that-skill>).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🤖"
---

# $NAME — <one-line purpose>

<When to reach for this, in a sentence. What the user gets.>

## Workflow

1. <first concrete step — a command, not a concept>
2. <second>
3. <verification: how you know it worked>

## Gotchas

- <the thing that wasted an hour, and the fix>

## Don't

- <the plausible-looking wrong move>
EOF

echo "Created skills/$NAME/SKILL.md"
echo
echo "Next:"
echo "  1. Write the description first — it is what makes the skill trigger."
echo "  2. python3 scripts/check_skills.py $NAME"
echo "  3. python3 scripts/validate_triggers.py --skill $NAME"
echo "  4. git add skills/$NAME && git commit"
echo
echo "It will be available as solo:$NAME in the next session (plugin cache is symlinked to this repo)."
