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
    python scripts/memory_map.py --audit            # show optimization hints
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

# ── Rich (optional, fallback to plain text) ───────────────────────

try:
    from rich.console import Console
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text
    from rich.tree import Tree

    HAS_RICH = True
except ImportError:
    HAS_RICH = False

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
    kind: str  # managed | user | user_rule | auto_memory | project | project_rule | local | child | import | skill
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

    @property
    def chars(self) -> int:
        """Approximate char count."""
        try:
            return len(self.path.read_text())
        except Exception:
            return 0

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
        # Match @path — any path-like string; file existence check filters false positives
        for match in re.finditer(r"@(~?[\w./_-]+)", line_no_spans):
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


def short_path(p: Path) -> str:
    """Shorten path for display."""
    return str(p).replace(str(Path.home()), "~")


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
        # CLAUDE.local.md (at every level, not just CWD)
        add(level / "CLAUDE.local.md", "local")
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

    # 8. Skills (detect .claude/skills/ and .agents/skills/)
    for skills_dir in [cwd / ".claude" / "skills", cwd / ".agents" / "skills"]:
        if skills_dir.exists():
            for skill_file in sorted(skills_dir.rglob("*.md")):
                # Count SKILL.md as the skill entry, bare .md as legacy
                priority += 1
                memories.append(
                    MemoryFile(
                        path=skill_file.resolve(),
                        kind="skill",
                        priority=priority,
                        lines=count_lines(skill_file),
                        loaded_lines=0,  # on-demand (invoked by user)
                    )
                )

    return memories


# ── Audit ─────────────────────────────────────────────────────────


def audit_memory(memories: list[MemoryFile], cwd: Path | None = None) -> list[str]:
    """Analyze memory map and return optimization hints."""
    hints: list[str] = []
    startup = [
        m for m in memories if m.kind not in ("child", "auto_memory_topic", "skill")
    ]
    always = [m for m in startup if not m.conditional]
    conditional = [m for m in startup if m.conditional]
    base_chars = sum(m.chars for m in always)
    max_chars = sum(m.chars for m in startup)

    # Broken symlinks
    for m in memories:
        if m.path.is_symlink():
            target = m.path.resolve()
            if not target.exists():
                hints.append(
                    f"BROKEN SYMLINK: {short_path(m.path)} → {short_path(target)} (target missing)"
                )

    # Context budget (base = always loaded, max = all rules active)
    budget = 40000
    base_pct = int(base_chars / budget * 100) if budget else 0
    max_pct = int(max_chars / budget * 100) if budget else 0
    if conditional:
        hints.append(
            f"BUDGET: base {base_chars:,}c ({base_pct}%) / max {max_chars:,}c ({max_pct}%) of {budget // 1000}k"
        )
    else:
        hints.append(f"BUDGET: {base_chars:,}c ({base_pct}%) of {budget // 1000}k")

    if base_chars > budget:
        hints.append(
            f"OVER BUDGET: base context {base_chars - budget:,} chars over limit."
        )
    elif max_chars > budget:
        hints.append(
            f"MAX OVER BUDGET: worst-case {max_chars - budget:,} chars over limit (when all rules active)."
        )

    # Large files (by lines or chars)
    for m in startup:
        mc = m.chars
        if m.lines > 300 or mc > 10000:
            pct_file = int(mc / budget * 100) if budget else 0
            hints.append(
                f"LARGE: {short_path(m.path)} ({m.lines}L / {mc:,}c = {pct_file}% of budget) — consider splitting"
            )

    # Rules without paths: (always loaded)
    for m in startup:
        if m.kind == "project_rule" and not m.conditional and m.lines > 30:
            hints.append(
                f"UNCONDITIONAL: {short_path(m.path)} ({m.lines} lines) — add paths: frontmatter to make conditional"
            )

    # Dead conditional rules — paths: globs that match nothing
    if cwd:
        for m in startup:
            if m.conditional and m.paths_filter:
                has_match = False
                for pattern in m.paths_filter:
                    if list(cwd.glob(pattern)):
                        has_match = True
                        break
                if not has_match:
                    hints.append(
                        f"DEAD RULE: {short_path(m.path)} — paths: {m.paths_filter} match no files in {short_path(cwd)}"
                    )

    # Inheritance chain — check for gaps in project hierarchy
    if cwd:
        project_files = [m for m in startup if m.kind == "project"]
        if project_files:
            deepest = cwd.resolve()
            git_root = find_git_root(cwd)
            chain_root = git_root if git_root else deepest
            # Walk from chain_root up — check each parent for CLAUDE.md
            current = deepest.parent
            while current != current.parent and current != chain_root.parent:
                expected = current / "CLAUDE.md"
                if (
                    current.name
                    and not current.name.startswith(".")
                    and any(
                        d.is_dir() and (d / "CLAUDE.md").exists()
                        for d in current.iterdir()
                    )
                    and not expected.exists()
                ):
                    hints.append(
                        f"CHAIN GAP: {short_path(current)} has child projects but no CLAUDE.md"
                    )
                current = current.parent

    # Essential sections in CWD CLAUDE.md
    if cwd:
        cwd_claude = cwd / "CLAUDE.md"
        if cwd_claude.exists():
            try:
                text = cwd_claude.read_text().lower()
                headers = {
                    line.strip().lstrip("#").strip()
                    for line in text.splitlines()
                    if line.startswith("## ")
                }
                missing = []
                # Check for common essential headers (flexible matching)
                has_structure = any(
                    h
                    for h in headers
                    if "structure" in h or "directory" in h or "layout" in h
                )
                has_commands = any(
                    h for h in headers if "command" in h or "usage" in h or "make" in h
                )
                if not has_structure:
                    missing.append("project structure")
                if not has_commands:
                    missing.append("commands/usage")
                if missing:
                    hints.append(
                        f"INCOMPLETE: {short_path(cwd_claude)} missing sections: {', '.join(missing)}"
                    )
            except Exception:
                pass

    # Duplicate content detection (same section headers)
    sections_by_file: dict[str, list[str]] = {}
    for m in startup:
        try:
            text = m.path.read_text()
        except Exception:
            continue
        headers = [
            line.strip().lstrip("#").strip().lower()
            for line in text.splitlines()
            if line.startswith("## ")
        ]
        sections_by_file[short_path(m.path)] = headers

    all_headers: dict[str, list[str]] = {}
    for fpath, headers in sections_by_file.items():
        for h in headers:
            all_headers.setdefault(h, []).append(fpath)
    for header, files in all_headers.items():
        if len(files) > 1:
            hints.append(f"DUPLICATE: section '{header}' appears in {', '.join(files)}")

    # ── Memory best practices (per code.claude.com/docs/en/memory) ──

    # CLAUDE.local.md should be in .gitignore
    if cwd:
        local_md = cwd / "CLAUDE.local.md"
        if local_md.exists():
            gitignore = cwd / ".gitignore"
            is_ignored = False
            if gitignore.exists():
                try:
                    gi_text = gitignore.read_text()
                    is_ignored = "CLAUDE.local.md" in gi_text
                except Exception:
                    pass
            if not is_ignored:
                hints.append(
                    f"LOCAL NOT IGNORED: {short_path(local_md)} exists but not in .gitignore"
                )

    # Auto-memory MEMORY.md > 200 lines (only first 200 loaded)
    for m in memories:
        if m.kind == "auto_memory" and m.lines > 200:
            hints.append(
                f"AUTO-MEMORY LONG: {short_path(m.path)} ({m.lines}L) — only first 200 loaded. Move details to topic files"
            )

    # Rules with generic names (should be descriptive per official docs)
    generic_names = {"rules.md", "misc.md", "other.md", "notes.md", "extra.md"}
    for m in memories:
        if m.kind in ("project_rule", "user_rule"):
            if m.path.name.lower() in generic_names:
                hints.append(
                    f"GENERIC RULE NAME: {short_path(m.path)} — use descriptive name (e.g., testing.md, api-design.md)"
                )

    # ── Skills best practices ──
    skills = [m for m in memories if m.kind == "skill"]
    if skills:
        # Group by parent folder to distinguish references from legacy
        skill_folders: dict[Path, list[MemoryFile]] = {}
        for s in skills:
            skill_folders.setdefault(s.path.parent, []).append(s)

        legacy_count = 0
        for folder, files in skill_folders.items():
            has_skill_md = any(f.path.name == "SKILL.md" for f in files)
            if not has_skill_md:
                # All .md files in this folder are legacy (no SKILL.md)
                for f in files:
                    legacy_count += 1
                    hints.append(
                        f"LEGACY SKILL: {short_path(f.path)} — migrate to {folder.name}/SKILL.md"
                    )

        # Check SKILL.md frontmatter quality
        for s in skills:
            if s.path.name != "SKILL.md":
                continue
            try:
                text = s.path.read_text()
            except Exception:
                continue
            # Check for frontmatter
            if not text.startswith("---"):
                hints.append(
                    f"SKILL NO FRONTMATTER: {short_path(s.path)} — add name: and description:"
                )
                continue
            end = text.find("---", 3)
            if end == -1:
                continue
            fm = text[3:end]
            has_name = any(line.strip().startswith("name:") for line in fm.splitlines())
            has_desc = any(
                line.strip().startswith("description:") for line in fm.splitlines()
            )
            if not has_name:
                hints.append(f"SKILL NO NAME: {short_path(s.path)} — add name: field")
            if not has_desc:
                hints.append(
                    f"SKILL NO DESC: {short_path(s.path)} — add description: with trigger phrases"
                )
            # Large skill
            if s.lines > 200:
                hints.append(
                    f"SKILL LARGE: {short_path(s.path)} ({s.lines}L) — move details to references/"
                )

        # Too many skills
        proper_count = sum(1 for s in skills if s.path.name == "SKILL.md")
        if proper_count > 20:
            hints.append(
                f"SKILL OVERLOAD: {proper_count} skills — consider selective enablement or skill packs"
            )

    # No auto-memory
    if not any(m.kind == "auto_memory" for m in memories):
        hints.append("NO AUTO-MEMORY: consider enabling for cross-session learning")

    if not hints:
        hints.append("All good — no issues found.")

    return hints


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
    "skill": "Skill",
}

KIND_COLORS = {
    "managed": "red",
    "user": "cyan",
    "user_rule": "cyan",
    "auto_memory": "magenta",
    "auto_memory_topic": "dim magenta",
    "project": "green",
    "project_rule": "yellow",
    "local": "blue",
    "child": "dim",
    "import": "dim cyan",
    "skill": "bright_blue",
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
    "skill": "sk",
}


def display_rich(
    cwd: Path, memories: list[MemoryFile], show_audit: bool = False
) -> None:
    """Rich tree display."""
    console = Console()
    git_root = find_git_root(cwd)

    startup = [
        m for m in memories if m.kind not in ("child", "auto_memory_topic", "skill")
    ]
    on_demand = [m for m in memories if m.kind in ("child", "auto_memory_topic")]
    skills = [m for m in memories if m.kind == "skill"]
    always = [m for m in startup if not m.conditional]
    conditional = [m for m in startup if m.conditional]
    base_chars = sum(m.chars for m in always)
    max_chars = sum(m.chars for m in startup)

    # Header
    header = Text()
    header.append(f"CWD: {cwd}\n", style="bold")
    if git_root:
        header.append(f"Git: {git_root}\n", style="dim")
    header.append(f"Key: {get_project_key(cwd)}", style="dim")

    tree = Tree(
        Panel(header, title="Claude Code Memory Map", border_style="blue"),
        guide_style="dim",
    )

    # Budget line
    budget = 40000
    base_pct = int(base_chars / budget * 100)
    max_pct = int(max_chars / budget * 100)
    budget_style = "green" if base_pct < 50 else ("yellow" if base_pct < 75 else "red")
    tree.add(
        f"[{budget_style}]Budget: {base_chars:,}c base ({base_pct}%)"
        + (f" / {max_chars:,}c max ({max_pct}%)" if conditional else "")
        + f" of {budget // 1000}k[/]"
    )

    # Always-loaded branch
    always_branch = tree.add(
        f"[bold green]Always loaded[/] ({len(always)} files, {base_chars:,}c)"
    )
    for m in always:
        color = KIND_COLORS.get(m.kind, "white")
        label = KIND_LABELS.get(m.kind, m.kind)
        name = m.path.name
        size = (
            f"{m.loaded_lines}L / {m.chars:,}c" if m.chars > 0 else f"{m.loaded_lines}L"
        )
        entry = f"[{color}]{name}[/] [dim]{label} | {size}[/]"
        if m.imported_by:
            entry += f" [dim italic](from {Path(m.imported_by).name})[/]"
        always_branch.add(entry)

    # Conditional rules branch
    if conditional:
        cond_chars = sum(m.chars for m in conditional)
        cond_branch = tree.add(
            f"[bold yellow]Conditional rules[/] ({len(conditional)} files, {cond_chars:,}c — loaded by paths:)"
        )
        for m in conditional:
            name = m.path.name
            size = (
                f"{m.loaded_lines}L / {m.chars:,}c"
                if m.chars > 0
                else f"{m.loaded_lines}L"
            )
            paths_str = ", ".join(m.paths_filter[:2])
            if len(m.paths_filter) > 2:
                paths_str += f" +{len(m.paths_filter) - 2}"
            entry = f"[yellow]{name}[/] [dim]{size} → {paths_str}[/]"
            cond_branch.add(entry)

    # On-demand branch
    if on_demand:
        od_branch = tree.add(f"[dim]On-demand[/] ({len(on_demand)} files)")
        for m in on_demand:
            od_branch.add(f"[dim]{short_path(m.path)} ({m.lines} lines)[/]")

    # Skills branch
    if skills:
        # Group by folder to distinguish references from true legacy
        sk_folders: dict[Path, list[MemoryFile]] = {}
        for s in skills:
            sk_folders.setdefault(s.path.parent, []).append(s)

        proper = [s for s in skills if s.path.name == "SKILL.md"]
        true_legacy = [
            s
            for s in skills
            if s.path.name != "SKILL.md"
            and not any(f.path.name == "SKILL.md" for f in sk_folders[s.path.parent])
        ]
        refs = [
            s
            for s in skills
            if s.path.name != "SKILL.md"
            and any(f.path.name == "SKILL.md" for f in sk_folders[s.path.parent])
        ]

        skills_label = f"[bold bright_blue]Skills[/] ({len(proper)}"
        if true_legacy:
            skills_label += f", {len(true_legacy)} legacy"
        skills_label += ")"
        sk_branch = tree.add(skills_label)
        for s in proper:
            folder = s.path.parent.name
            ref_count = sum(1 for r in refs if r.path.parent == s.path.parent)
            ref_note = f" +{ref_count} refs" if ref_count else ""
            sk_branch.add(f"[bright_blue]{folder}/[/] [dim]{s.lines}L{ref_note}[/]")
        for s in true_legacy:
            sk_branch.add(f"[dim yellow]{s.path.name}[/] [dim]{s.lines}L (legacy)[/]")

    console.print(tree)

    # Audit
    if show_audit:
        hints = audit_memory(memories, cwd)
        if hints:
            console.print()
            table = Table(title="Audit Hints", border_style="yellow", show_lines=True)
            table.add_column("Type", style="bold", width=15)
            table.add_column("Details")
            for h in hints:
                parts = h.split(": ", 1)
                if len(parts) == 2:
                    table.add_row(parts[0], parts[1])
                else:
                    table.add_row("INFO", h)
            console.print(table)


def display_plain(
    cwd: Path, memories: list[MemoryFile], show_audit: bool = False
) -> None:
    """Plain text fallback display."""
    startup = [
        m for m in memories if m.kind not in ("child", "auto_memory_topic", "skill")
    ]
    always = [m for m in startup if not m.conditional]
    conditional = [m for m in startup if m.conditional]
    base_chars = sum(m.chars for m in always)
    max_chars = sum(m.chars for m in startup)
    on_demand_list = [m for m in memories if m.kind in ("child", "auto_memory_topic")]
    skills_list = [m for m in memories if m.kind == "skill"]

    print(f"\n{'=' * 60}")
    print("  Claude Code Memory Map")
    print(f"  CWD: {cwd}")
    git_root = find_git_root(cwd)
    if git_root:
        print(f"  Git: {git_root}")
    print(f"  Project key: {get_project_key(cwd)}")
    budget = 40000
    base_pct = int(base_chars / budget * 100)
    max_pct = int(max_chars / budget * 100)
    budget_line = f"  Budget: {base_chars:,}c base ({base_pct}%)"
    if conditional:
        budget_line += f" / {max_chars:,}c max ({max_pct}%)"
    budget_line += f" of {budget // 1000}k"
    print(budget_line)
    print(f"{'=' * 60}\n")

    # Always loaded
    print(f"  Always loaded ({len(always)} files, {base_chars:,}c):")
    print(f"  {'─' * 50}")
    for m in always:
        marker = KIND_MARKERS.get(m.kind, "  ")
        label = KIND_LABELS.get(m.kind, m.kind)
        display_path = short_path(m.path)
        size = m.size_display
        imp = (
            f" (from {m.imported_by.replace(str(Path.home()), '~')})"
            if m.imported_by
            else ""
        )
        print(f"  [{marker}] {display_path}")
        print(f"       {label} | {size}{imp}")
    print()

    # Conditional rules
    if conditional:
        cond_chars = sum(m.chars for m in conditional)
        print(f"  Conditional rules ({len(conditional)} files, {cond_chars:,}c):")
        print(f"  {'─' * 50}")
        for m in conditional:
            marker = KIND_MARKERS.get(m.kind, "  ")
            display_path = short_path(m.path)
            size = m.size_display
            paths_str = ", ".join(m.paths_filter[:2])
            if len(m.paths_filter) > 2:
                paths_str += f" +{len(m.paths_filter) - 2}"
            print(f"  [{marker}] {display_path}")
            print(f"       {size} → {paths_str}")
        print()

    # On-demand
    if on_demand_list:
        print(f"  On-demand ({len(on_demand_list)} files):")
        print(f"  {'─' * 50}")
        for m in on_demand_list:
            marker = KIND_MARKERS.get(m.kind, "  ")
            label = KIND_LABELS.get(m.kind, m.kind)
            display_path = short_path(m.path)
            size = m.size_display
            imp = (
                f" (from {m.imported_by.replace(str(Path.home()), '~')})"
                if m.imported_by
                else ""
            )
            print(f"  [{marker}] {display_path}")
            print(f"       {label} | {size}{imp}")
        print()

    # Skills
    if skills_list:
        sk_folders: dict[Path, list[MemoryFile]] = {}
        for s in skills_list:
            sk_folders.setdefault(s.path.parent, []).append(s)
        proper = [s for s in skills_list if s.path.name == "SKILL.md"]
        true_legacy = [
            s
            for s in skills_list
            if s.path.name != "SKILL.md"
            and not any(f.path.name == "SKILL.md" for f in sk_folders[s.path.parent])
        ]
        refs = [
            s
            for s in skills_list
            if s.path.name != "SKILL.md"
            and any(f.path.name == "SKILL.md" for f in sk_folders[s.path.parent])
        ]
        label = f"  Skills ({len(proper)}"
        if true_legacy:
            label += f", {len(true_legacy)} legacy"
        label += "):"
        print(label)
        print(f"  {'─' * 50}")
        for s in proper:
            folder = s.path.parent.name
            ref_count = sum(1 for r in refs if r.path.parent == s.path.parent)
            ref_note = f" +{ref_count} refs" if ref_count else ""
            print(f"  [sk] {folder}/ ({s.lines}L{ref_note})")
        for s in true_legacy:
            print(f"  [sk] {s.path.name} ({s.lines}L) — legacy")
        print()

    if show_audit:
        hints = audit_memory(memories, cwd)
        print(f"  {'─' * 50}")
        print("  Audit:")
        for h in hints:
            print(f"    {h}")
        print()


def display_json(memories: list[MemoryFile]) -> None:
    print(json.dumps([m.to_dict() for m in memories], indent=2, default=str))


# ── CLI ────────────────────────────────────────────────────────────


def main():
    args = sys.argv[1:]

    output_json = "--json" in args
    args = [a for a in args if a != "--json"]

    show_audit = "--audit" in args
    args = [a for a in args if a != "--audit"]

    all_projects = "--all-projects" in args
    args = [a for a in args if a != "--all-projects"]

    plain = "--plain" in args
    args = [a for a in args if a != "--plain"]

    use_rich = HAS_RICH and not plain and not output_json

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
            elif use_rich:
                display_rich(d, memories, show_audit)
            else:
                display_plain(d, memories, show_audit)

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
    elif use_rich:
        display_rich(cwd, memories, show_audit)
    else:
        display_plain(cwd, memories, show_audit)


if __name__ == "__main__":
    main()
