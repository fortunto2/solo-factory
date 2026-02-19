#!/usr/bin/env python3
"""Add openclaw metadata to all solo-factory SKILL.md files.

Makes skills dual-compatible: Claude Code + OpenClaw ClawHub.
Idempotent — skips skills that already have openclaw metadata.
"""

import re
from pathlib import Path

SKILLS_DIR = Path(__file__).parent.parent / "skills"

# Emoji mapping per skill
EMOJIS = {
    "research": "🔍",
    "validate": "✅",
    "stream": "🌊",
    "plan": "📋",
    "build": "🔨",
    "deploy": "🚀",
    "review": "🔎",
    "scaffold": "🏗️",
    "setup": "⚙️",
    "swarm": "🐝",
    "pipeline": "🔄",
    "audit": "🩺",
    "init": "🎬",
    "retro": "🔮",
    "content-gen": "📝",
    "landing-gen": "🛬",
    "seo-audit": "📊",
    "community-outreach": "💬",
    "video-promo": "🎥",
    "metrics-track": "📈",
    "humanize": "✍️",
    "index-youtube": "🎞️",
    "you2idea-extract": "💡",
    "factory": "🏭",
}


def add_openclaw_meta(skill_md: Path) -> bool:
    """Add openclaw metadata block to SKILL.md frontmatter. Returns True if modified."""
    text = skill_md.read_text()

    # Already has openclaw metadata?
    if "openclaw:" in text:
        return False

    # Find metadata block in frontmatter
    # Pattern: metadata:\n  key: value\n  key: value
    if "metadata:" not in text:
        # No metadata block — add one before closing ---
        skill_name = skill_md.parent.name
        emoji = EMOJIS.get(skill_name, "🧩")
        # Find second --- (end of frontmatter)
        parts = text.split("---", 2)
        if len(parts) < 3:
            return False
        frontmatter = parts[1]
        frontmatter += f'metadata:\n  openclaw:\n    emoji: "{emoji}"\n'
        text = f"---{frontmatter}---{parts[2]}"
    else:
        # Has metadata block — add openclaw key after existing metadata entries
        skill_name = skill_md.parent.name
        emoji = EMOJIS.get(skill_name, "🧩")

        # Find the metadata block and add openclaw after last metadata entry
        # Look for "metadata:\n  key: val" pattern and append openclaw
        lines = text.split("\n")
        new_lines = []
        in_frontmatter = False
        frontmatter_count = 0
        in_metadata = False
        metadata_indent = 0
        inserted = False

        for i, line in enumerate(lines):
            if line.strip() == "---":
                frontmatter_count += 1
                if frontmatter_count == 1:
                    in_frontmatter = True
                elif frontmatter_count == 2:
                    in_frontmatter = False
                    # If we were in metadata but haven't inserted yet
                    if in_metadata and not inserted:
                        new_lines.append(f'{" " * metadata_indent}openclaw:')
                        new_lines.append(f'{" " * metadata_indent}  emoji: "{emoji}"')
                        inserted = True
                new_lines.append(line)
                continue

            if in_frontmatter:
                if line.startswith("metadata:"):
                    in_metadata = True
                    new_lines.append(line)
                    continue

                if in_metadata:
                    # Check if this line is still part of metadata (indented)
                    stripped = line.lstrip()
                    indent = len(line) - len(stripped)
                    if indent > 0 and stripped:
                        metadata_indent = indent
                        new_lines.append(line)
                        # Peek ahead — if next line is not indented or is a new key, insert after this
                        next_line = lines[i + 1] if i + 1 < len(lines) else "---"
                        next_stripped = next_line.lstrip()
                        next_indent = len(next_line) - len(next_stripped)
                        if next_indent == 0 or next_line.strip() == "---":
                            if not inserted:
                                new_lines.append(f'{" " * metadata_indent}openclaw:')
                                new_lines.append(f'{" " * metadata_indent}  emoji: "{emoji}"')
                                inserted = True
                                in_metadata = False
                        continue
                    else:
                        in_metadata = False
                        if not inserted:
                            new_lines.append(f'{" " * max(metadata_indent, 2)}openclaw:')
                            new_lines.append(f'{" " * max(metadata_indent, 2)}  emoji: "{emoji}"')
                            inserted = True

            new_lines.append(line)

        text = "\n".join(new_lines)

    skill_md.write_text(text)
    return True


def main():
    modified = 0
    skipped = 0
    for skill_dir in sorted(SKILLS_DIR.iterdir()):
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.exists():
            continue
        if add_openclaw_meta(skill_md):
            print(f"  + {skill_dir.name}")
            modified += 1
        else:
            print(f"  = {skill_dir.name} (already has openclaw)")
            skipped += 1

    print(f"\nDone: {modified} modified, {skipped} skipped")


if __name__ == "__main__":
    main()
