#!/usr/bin/env python3
"""
Skill trigger validation framework.

Tests that skill descriptions correctly trigger (or don't trigger)
for given user prompts. Based on Anthropic's "Complete Guide to
Building Skills for Claude" — Ch.3 Testing.

Usage:
    python scripts/validate_triggers.py                    # Run all tests
    python scripts/validate_triggers.py --skill research   # One skill
    python scripts/validate_triggers.py --verbose          # Show all matches

Test format: each skill can have a `tests/triggers.yaml` file:
    should_trigger:
      - "research this idea"
      - "find competitors for my app"
    should_not_trigger:
      - "build the feature"
      - "write a landing page"

If no triggers.yaml exists, the script extracts test cases from
the skill description's trigger phrases and negative triggers.
"""

import re
import sys
from pathlib import Path

import yaml


def load_skill_description(skill_dir: Path) -> str | None:
    """Read description from SKILL.md frontmatter."""
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        return None

    content = skill_md.read_text()
    # Extract YAML frontmatter
    match = re.match(r"^---\n(.*?)\n---", content, re.DOTALL)
    if not match:
        return None

    try:
        fm = yaml.safe_load(match.group(1))
        return fm.get("description", "")
    except yaml.YAMLError:
        return None


def extract_trigger_phrases(description: str) -> list[str]:
    """Extract 'Use when user says ...' phrases from description."""
    # Match: Use when user says "X", "Y", "Z"
    match = re.search(r'Use when user says\s+"([^"]+)"', description)
    if not match:
        return []

    # Find all quoted phrases after "Use when user says"
    use_when_part = description[description.index("Use when"):]
    phrases = re.findall(r'"([^"]+)"', use_when_part)

    # Stop at "Do NOT" boundary
    result = []
    for p in phrases:
        if "Do NOT" in p or "do not" in p.lower():
            break
        result.append(p)
    return result


def extract_negative_triggers(description: str) -> list[str]:
    """Extract 'Do NOT use for ...' phrases from description."""
    match = re.search(r"Do NOT use for (.+?)(?:\.|$)", description)
    if not match:
        return []

    neg_text = match.group(1)
    # Split by (use /skill-name) — skill names can contain hyphens
    parts = re.split(r"\s*\(use /[\w-]+\)\s*", neg_text)
    return [p.strip().rstrip(",").rstrip(" or") for p in parts if p.strip()]


def load_trigger_tests(skill_dir: Path, description: str) -> dict:
    """Load test cases from triggers.yaml or generate from description."""
    tests_file = skill_dir / "tests" / "triggers.yaml"

    if tests_file.exists():
        with open(tests_file) as f:
            return yaml.safe_load(f)

    # Auto-generate from description
    should = extract_trigger_phrases(description)
    should_not = extract_negative_triggers(description)

    return {
        "should_trigger": should,
        "should_not_trigger": should_not,
        "auto_generated": True,
    }


def keyword_match(prompt: str, description: str) -> bool:
    """Simple keyword overlap check between prompt and description triggers.

    This is a heuristic — real triggering depends on the LLM.
    We check if the prompt's key terms appear in the description's
    trigger phrases.
    """
    prompt_lower = prompt.lower()
    desc_lower = description.lower()

    # Extract trigger phrases from description
    triggers = extract_trigger_phrases(description)

    for trigger in triggers:
        trigger_words = set(trigger.lower().split())
        prompt_words = set(prompt_lower.split())
        # Require >60% overlap AND at least 2 matching words (or all if trigger is 1-2 words)
        overlap = trigger_words & prompt_words
        min_overlap = max(2, len(trigger_words) * 0.6) if len(trigger_words) > 2 else len(trigger_words)
        if len(overlap) >= min_overlap:
            return True

    return False


def run_tests(skills_dir: Path, target_skill: str | None = None, verbose: bool = False) -> bool:
    """Run trigger tests for all skills. Returns True if all pass."""
    all_passed = True
    total_tests = 0
    passed_tests = 0

    skill_dirs = sorted(skills_dir.iterdir())
    if target_skill:
        skill_dirs = [d for d in skill_dirs if d.name == target_skill]

    for skill_dir in skill_dirs:
        if not skill_dir.is_dir():
            continue

        description = load_skill_description(skill_dir)
        if not description:
            continue

        tests = load_trigger_tests(skill_dir, description)
        skill_name = skill_dir.name
        auto = tests.get("auto_generated", False)

        should = tests.get("should_trigger", [])
        should_not = tests.get("should_not_trigger", [])

        if not should and not should_not:
            if verbose:
                print(f"  SKIP  {skill_name} — no test cases")
            continue

        skill_passed = True

        # Test positive triggers
        for prompt in should:
            total_tests += 1
            matched = keyword_match(prompt, description)
            if matched:
                passed_tests += 1
                if verbose:
                    print(f"  PASS  {skill_name} ← \"{prompt}\"")
            else:
                skill_passed = False
                all_passed = False
                print(f"  FAIL  {skill_name} should trigger for \"{prompt}\"")

        # Test negative triggers (these should NOT match)
        for prompt in should_not:
            total_tests += 1
            matched = keyword_match(prompt, description)
            if not matched:
                passed_tests += 1
                if verbose:
                    print(f"  PASS  {skill_name} correctly ignores \"{prompt}\"")
            else:
                skill_passed = False
                all_passed = False
                print(f"  FAIL  {skill_name} should NOT trigger for \"{prompt}\"")

        if skill_passed and not verbose:
            tag = "(auto)" if auto else ""
            print(f"  OK    {skill_name} — {len(should)}+ / {len(should_not)}- {tag}")

    print(f"\n{'PASS' if all_passed else 'FAIL'} — {passed_tests}/{total_tests} tests passed")
    return all_passed


def main():
    verbose = "--verbose" in sys.argv or "-v" in sys.argv

    target_skill = None
    for i, arg in enumerate(sys.argv[1:], 1):
        if arg == "--skill" and i < len(sys.argv) - 1:
            target_skill = sys.argv[i + 1]

    # Find skills directory
    script_dir = Path(__file__).parent.parent
    skills_dir = script_dir / "skills"

    if not skills_dir.exists():
        print(f"Skills directory not found: {skills_dir}")
        sys.exit(1)

    print(f"Testing skill triggers in {skills_dir}\n")

    passed = run_tests(skills_dir, target_skill, verbose)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
