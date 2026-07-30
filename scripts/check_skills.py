#!/usr/bin/env python3
"""
Skill frontmatter validation (repo-only — safe in CI and pre-commit).

Checks every skills/*/SKILL.md for the things an agent gets wrong when it
hand-creates a skill instead of running `make new-skill`:

  - SKILL.md exists and has YAML frontmatter
  - `name` is `solo-<directory>` — the convention across every skill here and
    the ClawHub slug; anything else claims a name nothing resolves
  - `description` exists and is non-trivial
  - `metadata.version` exists (ClawHub publishing reads it)

Machine-level checks (plugin symlink, duplicate skills in ~/.claude/skills)
live in scripts/doctor.sh — they depend on the host, not the repo.

Usage:
    python3 scripts/check_skills.py            # all skills
    python3 scripts/check_skills.py research   # one skill
"""

import re
import sys
from pathlib import Path

import yaml

SKILLS_DIR = Path(__file__).resolve().parent.parent / "skills"
MIN_DESCRIPTION_LEN = 40


def frontmatter(skill_md: Path) -> dict | None:
    match = re.match(r"^---\n(.*?)\n---", skill_md.read_text(), re.DOTALL)
    if not match:
        return None
    try:
        data = yaml.safe_load(match.group(1))
    except yaml.YAMLError as exc:
        print(f"  invalid YAML frontmatter: {exc}")
        return None
    return data if isinstance(data, dict) else None


def check(skill_dir: Path) -> list[str]:
    """Return a list of problems for one skill directory."""
    problems = []
    skill_md = skill_dir / "SKILL.md"

    if not skill_md.exists():
        return [f"{skill_dir.name}: no SKILL.md"]

    fm = frontmatter(skill_md)
    if fm is None:
        return [f"{skill_dir.name}: missing or invalid YAML frontmatter"]

    name = fm.get("name")
    if not name:
        problems.append(f"{skill_dir.name}: frontmatter has no `name`")
    elif name != f"solo-{skill_dir.name}":
        problems.append(
            f"{skill_dir.name}: `name: {name}` — every skill here is named "
            f"`solo-<directory>`, so this must be `solo-{skill_dir.name}` "
            f"(it is also the ClawHub slug)"
        )

    description = (fm.get("description") or "").strip()
    if not description:
        problems.append(f"{skill_dir.name}: frontmatter has no `description`")
    elif len(description) < MIN_DESCRIPTION_LEN:
        problems.append(
            f"{skill_dir.name}: description is {len(description)} chars — too short to "
            f"trigger reliably (aim for what the user would actually say)"
        )

    version = (fm.get("metadata") or {}).get("version")
    if not version:
        problems.append(f"{skill_dir.name}: no `metadata.version` (needed to publish)")

    return problems


def main() -> int:
    wanted = sys.argv[1:]
    dirs = sorted(d for d in SKILLS_DIR.iterdir() if d.is_dir())
    if wanted:
        dirs = [d for d in dirs if d.name in wanted]
        missing = set(wanted) - {d.name for d in dirs}
        for name in sorted(missing):
            print(f"FAIL  no such skill: {name}")
        if missing:
            return 1

    problems = [p for d in dirs for p in check(d)]

    for problem in problems:
        print(f"FAIL  {problem}")

    if problems:
        print(f"\n{len(problems)} problem(s) in {len(dirs)} skill(s).")
        return 1

    print(f"OK    {len(dirs)} skills — frontmatter valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
