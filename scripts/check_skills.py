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

import os
import re
import sys
from pathlib import Path

import yaml

# Anchored to this repository, which is right for a repo-only check — and it left
# the script unexercisable: a test had to plant a broken skill in the real skills/
# directory and remove it, and a test that fails midway would leave one behind. This
# repo's own rule is that a test must not be able to damage the thing it tests, so
# the seam is here rather than in an argument about how careful the test will be.
SKILLS_DIR = Path(
    os.environ.get("SOLO_SKILLS_DIR", Path(__file__).resolve().parent.parent / "skills")
)
MIN_DESCRIPTION_LEN = 40
# True only when reading this repository's own skills/. The count check compares prose
# in THIS repo against what is on disk; pointed at a scratch directory it would report
# the absence of our README as a defect in someone's fixture. Found the hard way: the
# check was written and exercised only through `make doctor`, the convenient call, and
# went red in four tests that pass SOLO_SKILLS_DIR — the guard-reach mistake this repo
# has a rule about.
OWN_SKILLS = SKILLS_DIR == Path(__file__).resolve().parent.parent / "skills"


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


def check_counts(n: int) -> list[str]:
    """Every prose claim about how many skills there are must match the disk.

    Measured 2026-09-12: four files claimed 39, 44, 46 and 46 at once, and
    README's own section totals summed to 45 with `board` in none of them. A
    number in a document is read by the next agent as a fact, and none of the
    four could be told from the truth by reading it. Scoped to files this repo
    owns; a claim it cannot see is not one it can promise about.
    """
    root = SKILLS_DIR.parent
    problems: list[str] = []
    checked = 0
    for rel, pattern in (
        (".claude-plugin/plugin.json", r"(\d+) skills"),
        ("CLAUDE.md", r"# (\d+) skills"),
        ("README.md", r"^### .*?\((\d+) skills?\)"),
    ):
        path = root / rel
        if not path.is_file():
            problems.append(
                f"{rel} is missing — the skill count cannot be checked against it"
            )
            continue
        text = path.read_text(encoding="utf-8")
        found = re.findall(pattern, text, re.M)
        if not found:
            problems.append(
                f"{rel} states no skill count — this check has nothing to compare"
            )
            continue
        checked += 1
        claimed = sum(int(x) for x in found) if rel == "README.md" else int(found[0])
        if claimed != n:
            where = "section totals sum to" if rel == "README.md" else "says"
            problems.append(f"{rel} {where} {claimed} skills, {n} are on disk")
    # Zero scope is never a pass: three files were named, three must be read.
    if checked == 0:
        problems.append("no file carried a skill count — nothing was compared")
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

    # Only meaningful over the whole set, and only for this repo's own skills —
    # a filtered run knows nothing about the total, and a scratch directory has no
    # documents of ours to disagree with.
    if not wanted and OWN_SKILLS:
        drift = check_counts(len(dirs))
        for problem in drift:
            print(f"FAIL  {problem}")
        if drift:
            print(f"\n{len(drift)} skill-count claim(s) disagree with the disk.")
            return 1

    counts = (
        "frontmatter valid, counts in docs agree" if OWN_SKILLS else "frontmatter valid"
    )
    print(f"OK    {len(dirs)} skills — {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
