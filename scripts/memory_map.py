#!/usr/bin/env python3
"""
Claude Code Memory Map — replicates Claude Code's memory loading algorithm.

Shows exactly which CLAUDE.md files, rules, auto-memory, and imports
are loaded for a given working directory.

Usage:
    python scripts/memory_map.py                    # from CWD
    python scripts/memory_map.py /path/to/project   # for specific dir
    python scripts/memory_map.py --all-projects     # scan all active projects
    python scripts/memory_map.py --json             # JSON output
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

# ── Constants ──────────────────────────────────────────────────────

MANAGED_POLICY = Path("/Library/Application Support/ClaudeCode/CLAUDE.md")
USER_CLAUDE = Path.home() / ".claude" / "CLAUDE.md"
USER_RULES = Path.home() / ".claude" / "rules"
AUTO_MEMORY_BASE = Path.home() / ".claude" / "projects"
AUTO_MEMORY_LIMIT = 200  # lines loaded at startup


# ── Data ───────────────────────────────────────────────────────────


@dataclass
class MemoryFile:
    path: Path
    kind: str  # managed | user | user_rule | auto_memory | project | project_rule | local | child | import
    priority: int
    lines: int = 0
    loaded_lines: int = 0  # for auto-memory (capped at 200)
    conditional: bool = False  # path-scoped rules
    paths_filter: list[str] = field(default_factory=list)
    imported_by: str | None = None
    exists: bool = True

    @property
    def size_display(self) -> str:
        if self.loaded_lines and self.loaded_lines != self.lines:
            return f"{self.loaded_lines}/{self.lines} lines"
        return f"{self.lines} lines"

    def to_dict(self) -> dict:
        d = {
            "path": str(self.path),
            "kind": self.kind,
            "priority": self.priority,
            "lines": self.lines,
            "exists": self.exists,
        }
        if self.loaded_lines and self.loaded_lines != self.lines:
            d["loaded_lines"] = self.loaded_lines
        if self.conditional:
            d["conditional"] = True
            d["paths_filter"] = self.paths_filter
        if self.imported_by:
            d["imported_by"] = self.imported_by
        return d


# ── Helpers ────────────────────────────────────────────────────────


def count_lines(path: Path) -> int:
    try:
        return len(path.read_text().splitlines())
    except Exception:
        return 0


def find_git_root(path: Path) -> Path | None:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return Path(result.stdout.strip())
    except Exception:
        pass
    return None


def get_project_key(cwd: Path) -> str:
    """Derive auto-memory project key from CWD (matches Claude Code format)."""
    git_root = find_git_root(cwd)
    base = git_root if git_root else cwd
    # Claude Code format: absolute path with / replaced by -
    return str(base).replace("/", "-")


def parse_rule_frontmatter(path: Path) -> list[str]:
    """Extract paths: field from YAML frontmatter in .claude/rules/*.md."""
    try:
        text = path.read_text()
    except Exception:
        return []
    if not text.startswith("---"):
        return []
    end = text.find("---", 3)
    if end == -1:
        return []
    frontmatter = text[3:end]
    paths = []
    in_paths = False
    for line in frontmatter.splitlines():
        stripped = line.strip()
        if stripped.startswith("paths:"):
            in_paths = True
            continue
        if in_paths:
            if stripped.startswith("- "):
                val = stripped[2:].strip().strip("\"'")
                paths.append(val)
            elif stripped and not stripped.startswith("#"):
                break
    return paths


def find_imports(
    path: Path, depth: int = 0, seen: set | None = None
) -> list[MemoryFile]:
    """Find @-imports in a memory file (max depth 5)."""
    if depth >= 5:
        return []
    if seen is None:
        seen = set()
    canonical = path.resolve()
    if canonical in seen:
        return []
    seen.add(canonical)

    try:
        text = path.read_text()
    except Exception:
        return []

    imports = []
    # Match @path references NOT inside code blocks or code spans
    in_code_block = False
    for line in text.splitlines():
        if line.strip().startswith("```"):
            in_code_block = not in_code_block
            continue
        if in_code_block:
            continue
        # Skip code spans
        line_no_spans = re.sub(r"`[^`]+`", "", line)
        for match in re.finditer(
            r"@(~?[\w./_-]+\.(?:md|txt|json|yaml|yml))", line_no_spans
        ):
            ref = match.group(1)
            # Resolve path
            if ref.startswith("~"):
                target = Path(ref).expanduser()
            else:
                target = path.parent / ref
            target = target.resolve()
            if target.exists() and target not in seen:
                mf = MemoryFile(
                    path=target,
                    kind="import",
                    priority=50,
                    lines=count_lines(target),
                    loaded_lines=count_lines(target),
                    imported_by=str(path),
                )
                imports.append(mf)
                imports.extend(find_imports(target, depth + 1, seen))
    return imports


# ── Main loader ────────────────────────────────────────────────────


def load_memory_map(cwd: Path) -> list[MemoryFile]:
    """Replicate Claude Code's memory loading algorithm."""
    memories: list[MemoryFile] = []
    priority = 0

    def add(path: Path, kind: str, **kwargs) -> MemoryFile | None:
        nonlocal priority
        priority += 1
        resolved = path.resolve() if path.exists() else path
        if not resolved.exists():
            return None
        lines = count_lines(resolved)
        mf = MemoryFile(
            path=resolved,
            kind=kind,
            priority=priority,
            lines=lines,
            loaded_lines=kwargs.get("loaded_lines", lines),
            conditional=kwargs.get("conditional", False),
            paths_filter=kwargs.get("paths_filter", []),
        )
        memories.append(mf)
        # Check for imports
        memories.extend(find_imports(resolved))
        return mf

    # 1. Managed policy
    if MANAGED_POLICY.exists():
        add(MANAGED_POLICY, "managed")

    # 2. User memory
    add(USER_CLAUDE, "user")

    # 3. User rules
    if USER_RULES.exists():
        for rule in sorted(USER_RULES.rglob("*.md")):
            paths_filter = parse_rule_frontmatter(rule)
            add(
                rule,
                "user_rule",
                conditional=bool(paths_filter),
                paths_filter=paths_filter,
            )

    # 4. Auto-memory
    project_key = get_project_key(cwd)
    auto_memory = AUTO_MEMORY_BASE / project_key / "memory" / "MEMORY.md"
    if auto_memory.exists():
        total = count_lines(auto_memory)
        priority += 1
        memories.append(
            MemoryFile(
                path=auto_memory.resolve(),
                kind="auto_memory",
                priority=priority,
                lines=total,
                loaded_lines=min(total, AUTO_MEMORY_LIMIT),
            )
        )
        # Check for topic files
        memory_dir = auto_memory.parent
        for topic in sorted(memory_dir.glob("*.md")):
            if topic.name != "MEMORY.md":
                priority += 1
                memories.append(
                    MemoryFile(
                        path=topic.resolve(),
                        kind="auto_memory_topic",
                        priority=priority,
                        lines=count_lines(topic),
                        loaded_lines=0,  # on-demand only
                    )
                )

    # 5. Directory hierarchy (root → CWD)
    hierarchy = []
    current = cwd.resolve()
    while current != current.parent:  # stop before /
        hierarchy.append(current)
        current = current.parent

    # Walk from top (closest to /) down to CWD
    for level in reversed(hierarchy):
        # CLAUDE.md
        add(level / "CLAUDE.md", "project")
        # .claude/CLAUDE.md
        add(level / ".claude" / "CLAUDE.md", "project")
        # .claude/rules/*.md
        rules_dir = level / ".claude" / "rules"
        if rules_dir.exists():
            for rule in sorted(rules_dir.rglob("*.md")):
                paths_filter = parse_rule_frontmatter(rule)
                add(
                    rule,
                    "project_rule",
                    conditional=bool(paths_filter),
                    paths_filter=paths_filter,
                )

    # 6. CLAUDE.local.md (CWD only)
    add(cwd / "CLAUDE.local.md", "local")

    # Deduplicate by resolved path (keep first occurrence = higher priority)
    seen_paths: set[Path] = set()
    deduped: list[MemoryFile] = []
    for m in memories:
        canonical = m.path.resolve()
        if canonical in seen_paths:
            continue
        seen_paths.add(canonical)
        deduped.append(m)
    memories = deduped

    # 7. Child directories (just detect, not loaded at startup)
    for child_claude in sorted(cwd.rglob("*/CLAUDE.md")):
        if child_claude.parent == cwd:
            continue  # skip CWD's own CLAUDE.md
        priority += 1
        memories.append(
            MemoryFile(
                path=child_claude.resolve(),
                kind="child",
                priority=priority,
                lines=count_lines(child_claude),
                loaded_lines=0,  # on-demand
            )
        )

    return memories


# ── Display ────────────────────────────────────────────────────────

KIND_LABELS = {
    "managed": "Managed Policy",
    "user": "User Memory",
    "user_rule": "User Rule",
    "auto_memory": "Auto Memory",
    "auto_memory_topic": "Auto Topic (on-demand)",
    "project": "Project",
    "project_rule": "Project Rule",
    "local": "Local",
    "child": "Child (on-demand)",
    "import": "Import (@)",
}

KIND_MARKERS = {
    "managed": "!!",
    "user": "~~",
    "user_rule": "~r",
    "auto_memory": "am",
    "auto_memory_topic": "at",
    "project": ">>",
    "project_rule": "pr",
    "local": "**",
    "child": "..",
    "import": "@@",
}


def display_tree(cwd: Path, memories: list[MemoryFile]) -> None:
    """Pretty-print memory map as a tree."""
    total_startup = sum(
        m.loaded_lines for m in memories if m.kind not in ("child", "auto_memory_topic")
    )
    total_files = sum(
        1 for m in memories if m.kind not in ("child", "auto_memory_topic")
    )
    on_demand = sum(1 for m in memories if m.kind in ("child", "auto_memory_topic"))

    print(f"\n{'=' * 60}")
    print("  Claude Code Memory Map")
    print(f"  CWD: {cwd}")
    git_root = find_git_root(cwd)
    if git_root:
        print(f"  Git: {git_root}")
    print(f"  Project key: {get_project_key(cwd)}")
    print(f"{'=' * 60}\n")

    # Group by kind for cleaner display
    sections = [
        (
            "Startup (loaded immediately)",
            lambda m: m.kind not in ("child", "auto_memory_topic"),
        ),
        (
            "On-demand (loaded when needed)",
            lambda m: m.kind in ("child", "auto_memory_topic"),
        ),
    ]

    for title, filter_fn in sections:
        filtered = [m for m in memories if filter_fn(m)]
        if not filtered:
            continue
        print(f"  {title}:")
        print(f"  {'─' * 50}")
        for m in filtered:
            marker = KIND_MARKERS.get(m.kind, "  ")
            label = KIND_LABELS.get(m.kind, m.kind)
            # Shorten home dir
            display_path = str(m.path).replace(str(Path.home()), "~")
            size = m.size_display
            cond = " [conditional]" if m.conditional else ""
            imp = (
                f" (from {m.imported_by.replace(str(Path.home()), '~')})"
                if m.imported_by
                else ""
            )
            print(f"  [{marker}] {display_path}")
            print(f"       {label} | {size}{cond}{imp}")
        print()

    print(f"  {'─' * 50}")
    print(f"  Startup: {total_files} files, ~{total_startup} lines loaded")
    if on_demand:
        print(f"  On-demand: {on_demand} files (loaded when Claude reads those dirs)")
    print()


def display_json(memories: list[MemoryFile]) -> None:
    print(json.dumps([m.to_dict() for m in memories], indent=2, default=str))


# ── CLI ────────────────────────────────────────────────────────────


def main():
    args = sys.argv[1:]

    output_json = "--json" in args
    args = [a for a in args if a != "--json"]

    all_projects = "--all-projects" in args
    args = [a for a in args if a != "--all-projects"]

    if all_projects:
        # Scan CWD (or parent) for subdirectories with CLAUDE.md
        scan_root = Path.cwd()
        dirs = sorted(
            [
                d
                for d in scan_root.iterdir()
                if d.is_dir() and (d / "CLAUDE.md").exists()
            ]
        )

        all_maps = {}
        for d in dirs:
            memories = load_memory_map(d)
            if output_json:
                all_maps[str(d)] = [m.to_dict() for m in memories]
            else:
                display_tree(d, memories)

        if output_json:
            print(json.dumps(all_maps, indent=2, default=str))
        return

    cwd = Path(args[0]).resolve() if args else Path.cwd()
    if not cwd.exists():
        print(f"Error: {cwd} does not exist", file=sys.stderr)
        sys.exit(1)

    memories = load_memory_map(cwd)

    if output_json:
        display_json(memories)
    else:
        display_tree(cwd, memories)


if __name__ == "__main__":
    main()
