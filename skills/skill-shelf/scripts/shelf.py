#!/usr/bin/env python3
"""shelf — keep rarely used skills out of the session, one command away.

Every skill visible to Claude Code costs its description in every session. The
shelf is a directory outside every skill path; a skill moved there is not
loaded, and `restore` puts it back where it came from.

  shelf stats [--days N]                 usage from session transcripts
  shelf list [query]                     what is on the shelf
  shelf shelve NAME... [--from DIR] [--reason TEXT]
  shelf restore NAME [--to DIR]

Env: CLAUDE_CONFIG_DIR (default ~/.claude), SKILL_SHELF_DIR (default
$CLAUDE_CONFIG_DIR/skills-archive). Stdlib only.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import re
import shutil
import sys
import time
from pathlib import Path

CMD_RE = re.compile(r"<command-name>/?([^<]+)</command-name>")
INDEX = ".shelf.json"


def config_dir() -> Path:
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")


def shelf_dir() -> Path:
    return Path(os.environ.get("SKILL_SHELF_DIR") or config_dir() / "skills-archive")


def skills_dir() -> Path:
    return config_dir() / "skills"


def norm(name: str) -> str:
    # solo:solo-plan and solo:plan are one skill; bare names stay as they are
    name = name.strip()
    if ":" in name:
        plugin, _, rest = name.partition(":")
        if rest.startswith(plugin + "-"):
            rest = rest[len(plugin) + 1 :]
        return f"{plugin}:{rest}"
    return name


def description(skill: Path) -> str:
    try:
        text = (skill / "SKILL.md").read_text(errors="ignore")
    except OSError:
        return "(no SKILL.md)"
    m = re.search(r"^description:\s*(.+)$", text, re.M)
    return m.group(1).strip().strip("\"'")[:140] if m else ""


def load_index() -> dict:
    p = shelf_dir() / INDEX
    return json.loads(p.read_text()) if p.exists() else {}


def save_index(idx: dict) -> None:
    shelf_dir().mkdir(parents=True, exist_ok=True)
    (shelf_dir() / INDEX).write_text(
        json.dumps(idx, indent=2, ensure_ascii=False) + "\n"
    )


def scan_usage(days: int) -> tuple[collections.Counter, dict, int]:
    cutoff = time.time() - days * 86400
    uses: collections.Counter = collections.Counter()
    last: dict = {}
    files = 0
    root = config_dir() / "projects"
    for f in root.glob("*/*.jsonl") if root.is_dir() else []:
        if f.stat().st_mtime < cutoff:
            continue
        files += 1
        with f.open(errors="ignore") as fh:
            for line in fh:
                if '"Skill"' not in line and "command-name" not in line:
                    continue
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                content = (o.get("message") or {}).get("content")
                names: list[str] = []
                if isinstance(content, str):
                    names = CMD_RE.findall(content)
                elif isinstance(content, list):
                    for b in content:
                        if not isinstance(b, dict):
                            continue
                        if b.get("type") == "tool_use" and b.get("name") == "Skill":
                            names.append((b.get("input") or {}).get("skill", "?"))
                        elif b.get("type") == "text":
                            names += CMD_RE.findall(b.get("text", ""))
                for n in names:
                    n = norm(n)
                    uses[n] += 1
                    last[n] = max(last.get(n, ""), o.get("timestamp", "")[:10])
    return uses, last, files


def cmd_stats(a) -> int:
    uses, last, files = scan_usage(a.days)
    if files == 0:
        print(
            f"UNKNOWN: no transcripts newer than {a.days} days under {config_dir() / 'projects'}"
        )
        print("Nothing was read, so nothing can be called unused.")
        return 2
    print(f"{files} transcripts, last {a.days} days\n")
    for n, c in uses.most_common():
        print(f"{c:5}  {n:40} {last.get(n, '')}")
    local = (
        sorted(p.name for p in skills_dir().iterdir()) if skills_dir().is_dir() else []
    )
    unused = [s for s in local if s not in uses]
    print(
        f"\nunused in ~/.claude/skills ({len(unused)}/{len(local)}): {' '.join(unused)}"
    )
    print(
        "Counts miss skills read by path instead of invoked; treat 0 as a candidate, not a verdict."
    )
    return 0


def cmd_list(a) -> int:
    idx = load_index()
    root = shelf_dir()
    items = (
        sorted(p for p in root.iterdir() if not p.name.startswith("."))
        if root.is_dir()
        else []
    )
    q = (a.query or "").lower()
    for p in items:
        d = description(p)
        if q and q not in p.name.lower() and q not in d.lower():
            continue
        meta = idx.get(p.name, {})
        print(f"{p.name:28} {d}")
        if meta:
            print(
                f"{'':28} from {meta.get('from')} on {meta.get('date')}: {meta.get('reason', '')}"
            )
    return 0


def cmd_shelve(a) -> int:
    src_root = Path(a.src).expanduser() if a.src else skills_dir()
    idx = load_index()
    rc = 0
    for name in a.names:
        src, dst = src_root / name, shelf_dir() / name
        if not (src.is_symlink() or src.exists()):
            print(f"no skill {name} in {src_root}", file=sys.stderr)
            rc = 1
            continue
        if dst.is_symlink() or dst.exists():
            print(f"{dst} already exists; restore or remove it first", file=sys.stderr)
            rc = 1
            continue
        shelf_dir().mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dst))  # a symlink moves as the link
        idx[name] = {
            "from": str(src_root),
            "date": dt.date.today().isoformat(),
            "reason": a.reason or "",
        }
        print(f"shelved {name}  ({src_root} → {shelf_dir()})")
    save_index(idx)
    return rc


def cmd_restore(a) -> int:
    idx = load_index()
    src = shelf_dir() / a.name
    if not (src.is_symlink() or src.exists()):
        print(
            f"{a.name} is not on the shelf; `shelf list` shows what is", file=sys.stderr
        )
        return 1
    dst_root = (
        Path(a.to).expanduser()
        if a.to
        else Path(idx.get(a.name, {}).get("from") or skills_dir())
    )
    dst = dst_root / a.name
    if dst.is_symlink() or dst.exists():
        print(f"{dst} already exists", file=sys.stderr)
        return 1
    dst_root.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(dst))
    idx.pop(a.name, None)
    save_index(idx)
    print(f"restored {a.name} → {dst_root} (visible from the next session)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="shelf", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("stats")
    s.add_argument("--days", type=int, default=56)
    s.set_defaults(fn=cmd_stats)
    s = sub.add_parser("list")
    s.add_argument("query", nargs="?")
    s.set_defaults(fn=cmd_list)
    s = sub.add_parser("shelve")
    s.add_argument("names", nargs="+")
    s.add_argument("--from", dest="src")
    s.add_argument("--reason")
    s.set_defaults(fn=cmd_shelve)
    s = sub.add_parser("restore")
    s.add_argument("name")
    s.add_argument("--to")
    s.set_defaults(fn=cmd_restore)
    a = ap.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
