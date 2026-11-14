#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["pyyaml"]
# ///
"""mirror_collect: the numbers behind a weekly reflection. Read-only; the model only interprets.

    mirror_collect.py collect --config mirror.yaml [--days 14] [--end 2026-11-14] [--json]
    mirror_collect.py ledger-append --config mirror.yaml --file entries.json
    mirror_collect.py lint REPORT.md [--max-chars 1800]

`collect` answers three questions from files, git and past session prompts (user turns only):
  a. said vs did: share of sessions and commits per project and per goal against the stated focus
  b. what repeats: patterns that qualify only with >= min_occurrences dated occurrences and a number
  c. the verdict on last week's experiment, computed from the same numbers
and prepares the load reduction: a cut list and a ranked candidate list for "this week only".

It never writes anything except through `ledger-append`, which the caller runs after accepting a report.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import yaml

DEFAULTS = {
    "min_occurrences": 3,
    "stale_draft_days": 7,
    "quiet_topic_days": 14,
    "silent_days": 14,
    "reschedule_prefixes": ["due_reason"],
    "sessions": {
        "dir": "~/.claude/projects",
        "exclude_dir_substrings": [],
        "automation_regex": "",
    },
    "correction_regex": r"^(нет|не |стоп|stop|no[,. ]|don't|do not|я же|опять|снова|again)",
    "focus": {"projects": [], "goals": [], "top": [], "defocus": []},
    "next_keys": ["plan", "steps", "next", "then", "first_step"],
    "ball_names": ["rustam"],
    "project_goal": {},
    "goal_priority": [],
    # items with these words carry a consequence (compliance, verification, legal, tax, penalty): never on the cut list
    "protected_regex": r"(?i)compliance|verif|legal|\btax|visa|penalt|\bfine\b|\birs\b|kyc|налог|верифик|штраф|виза|юрид",
    "pending_regex": r"(?i)decision pending|undecided|to be decided|is a decision for|решение не принято",
    "answered_regex": r"(?i)\b(replied|answered|responded)\b|ответил",
}

_DDMM = re.compile(r"^\s*(\d{1,2})\.(\d{1,2})(?!\d)")
_LONGNUM = re.compile(r"\d{7,}")
_WORD = re.compile(r"[a-zа-яё0-9]{4,}", re.IGNORECASE)


# ---------------------------------------------------------------- config


def load_config(path: Path) -> dict:
    raw = yaml.safe_load(path.read_text()) or {}
    cfg = {**DEFAULTS, **raw}
    for k in ("sessions", "focus"):
        cfg[k] = {**DEFAULTS[k], **(raw.get(k) or {})}
    root = Path(os.path.expanduser(raw.get("root", ".")))
    cfg["_root"] = (
        root if root.is_absolute() else path.parent / root
    ).resolve()  # relative root: against the config file
    return cfg


def p(cfg: dict, rel: str) -> Path:
    return (
        Path(os.path.expanduser(rel))
        if rel.startswith(("~", "/"))
        else cfg["_root"] / rel
    )


# ---------------------------------------------------------------- dates


def iso_week(d: date) -> str:
    y, w, _ = d.isocalendar()
    return f"{y}-W{w:02d}"


def parse_ddmm(text: str, today: date) -> date | None:
    """A note that opens with «14.11» is dated; the year is the latest one not after today + 7 days."""
    m = _DDMM.match(str(text))
    if not m:
        return None
    day, month = int(m[1]), int(m[2])
    for year in (today.year, today.year - 1):
        try:
            d = date(year, month, day)
        except ValueError:
            return None
        if d <= today + timedelta(days=7):
            return d
    return None


def reschedule_dates(item: dict, prefixes: list[str], today: date) -> list[date]:
    """Dated due-date moves of one todo item: every key that starts with a prefix and whose value opens with D.MM."""
    out = set()
    for k, v in item.items():
        if any(str(k).startswith(pre) for pre in prefixes):
            d = parse_ddmm(str(v), today)
            if d:
                out.add(d)
    return sorted(out)


# ---------------------------------------------------------------- the >=3 rule


@dataclass
class Pattern:
    id: str
    kind: str
    dates: list[date]
    number: str  # the count in words the report can quote, e.g. "5 переносов"
    refs: list[str] = field(default_factory=list)
    bucket: str = ""  # "finish": a complete artefact not sent; "middle": work stopped partway; "": not decidable from the data

    def __post_init__(self) -> None:
        self.bucket = {"stale-drafts": "finish", "quiet-topics": "middle"}.get(
            self.id, self.bucket
        )

    @property
    def count(self) -> int:
        return len(self.dates)


def qualifies(pat: Pattern, minimum: int) -> bool:
    """A pattern is reported only with >= minimum dated occurrences and a number to quote."""
    return pat.count >= minimum and bool(pat.number)


# ---------------------------------------------------------------- inputs


def _latest_note(notes: list[tuple[str, str]], today: date) -> str:
    """The note with the latest leading D.MM date (dict order is not time order); else the last one."""
    dated = [(parse_ddmm(v, today), v) for _, v in notes]
    dated = [x for x in dated if x[0]]
    return (
        max(dated, key=lambda x: x[0])[1] if dated else (notes[-1][1] if notes else "")
    )[:200]


def todo_items(cfg: dict, today: date) -> list[dict]:
    out = []
    for rel in cfg.get("todo_lists", []):
        path = p(cfg, rel)
        if not path.exists():
            continue
        data = yaml.safe_load(path.read_text()) or {}
        lst = path.parent.name
        for items in data.values():
            if not isinstance(items, list):
                continue
            for it in items:
                if not isinstance(it, dict) or it.get("status", "todo") not in (
                    "todo",
                    "doing",
                    "blocked",
                    "waiting",
                ):
                    continue
                notes = [
                    (k, str(v))
                    for k, v in it.items()
                    if str(k).startswith(("note", "next", "waiting", "due_reason"))
                ]
                effort = str(it.get("time") or "")
                if not effort:  # minutes only, quoted from the item's own notes; never an estimate of ours
                    for _, v in notes:
                        m = re.search(r"\b\d+\s?(?:min|мин)\b", v)
                        if m:
                            effort = m[0]
                            break
                slug, _, text = str(it.get("purpose") or "").partition(": ")
                due = it.get("due")
                out.append(
                    {
                        "ref": f"{lst}/{it.get('id', '?')}",
                        "effort": effort or "объём неизвестен",
                        "kind": str(it.get("kind") or ""),
                        "last_note": _latest_note(notes, today),
                        "protected": bool(
                            re.search(
                                cfg["protected_regex"],
                                f"{it.get('task', '')} {it.get('purpose', '')} {it.get('id', '')}",
                            )
                        ),
                        "title": str(it.get("task", ""))[:120],
                        "status": it.get("status", "todo"),
                        "due": str(due)[:10] if due else "",
                        "has_next": any(
                            str(k).startswith(tuple(cfg["next_keys"])) and it[k]
                            for k in it
                        ),
                        "goal": slug if text else "",
                        "purpose": text or str(it.get("purpose") or ""),
                        "reschedules": reschedule_dates(
                            it, cfg["reschedule_prefixes"], today
                        ),
                    }
                )
    return out


def registry_topics(cfg: dict, today: date) -> list[dict]:
    base = p(cfg, cfg.get("registry_dir", "tasks")) / "open"
    topics = []
    for f in sorted(base.glob("*.json")) if base.exists() else []:
        d = json.loads(f.read_text())
        upd = (d.get("updated") or d.get("created") or "")[:10]
        cre = (d.get("created") or "")[:10]
        topics.append(
            {
                "ref": d["id"],
                "title": d.get("title", "")[:120],
                "status": d.get("status", ""),
                "ball": d.get("ball", ""),
                "parents": d.get("parents", []),
                "due": d.get("due", ""),
                "has_next": any(
                    i.get("next")
                    for i in d.get("items", [])
                    if i.get("status") not in ("done", "dropped")
                ),
                "updated": upd,
                "created": cre,
                "item_titles": [str(i.get("title", "")) for i in d.get("items", [])],
                "items_open": sum(
                    1
                    for i in d.get("items", [])
                    if i.get("status") not in ("done", "dropped")
                ),
                "quiet_days": (today - date.fromisoformat(upd)).days if upd else 0,
                "age_days": (today - date.fromisoformat(cre)).days if cre else 0,
            }
        )
    return topics


def goal_roots(topics: list[dict]) -> dict[str, set[str]]:
    """topic -> the root goals above it (topics with no parents are roots, and root of themselves)."""
    by_id = {t["ref"]: t for t in topics}
    memo: dict[str, set[str]] = {}

    def roots(tid: str, path: tuple = ()) -> set[str]:
        if tid in memo:
            return memo[tid]
        t = by_id.get(tid)
        if t is None or not t["parents"] or tid in path:
            return {tid}
        out: set[str] = set()
        for par in t["parents"]:
            out |= roots(par, (*path, tid))
        memo[tid] = out
        return out

    return {tid: roots(tid) for tid in by_id}


def done_log(cfg: dict, start: date, end: date, drafts: list[dict]) -> list[dict]:
    """What he closed, sent, published or pressed in the window: closed registry topics, todo items with done_on,
    and drafts-adapter rows carrying sent_at. The unit is the act, never the response to it."""
    out = []
    for f in sorted(
        (p(cfg, cfg.get("registry_dir", "tasks")) / "done").glob("*/*.json")
    ):
        d = json.loads(f.read_text())
        c = (d.get("closed") or "")[:10]
        if c and start <= date.fromisoformat(c) <= end and d.get("status") == "done":
            out.append(
                {
                    "kind": "topic closed",
                    "ref": d["id"],
                    "title": d.get("title", "")[:100],
                    "date": c,
                }
            )
    for rel in cfg.get("todo_lists", []):
        path = p(cfg, rel)
        groups = (
            (yaml.safe_load(path.read_text()) or {}).values() if path.exists() else []
        )
        for items in groups:
            for it in items if isinstance(items, list) else []:
                done = (
                    it.get("done_on")
                    if isinstance(it, dict) and it.get("status") == "done"
                    else None
                )
                if done and start <= date.fromisoformat(str(done)[:10]) <= end:
                    out.append(
                        {
                            "kind": "todo done",
                            "ref": f"{path.parent.name}/{it['id']}",
                            "title": str(it.get("task", ""))[:100],
                            "date": str(done)[:10],
                        }
                    )
    for dr in drafts:
        sent = dr.get("sent_at", "")[:10]
        if sent and start <= date.fromisoformat(sent) <= end:
            out.append(
                {
                    "kind": "sent",
                    "ref": dr["ref"],
                    "title": dr.get("title", "")[:100],
                    "date": sent,
                }
            )
    return sorted(out, key=lambda x: x["date"])


def stale_waits(topics: list[dict], answered_regex: str) -> list[dict]:
    """Topics waiting on someone (ball elsewhere) while one of their own items records that this someone already answered."""
    rx = re.compile(answered_regex)
    out = []
    for t in topics:
        if t["ball"] not in ("me", ""):
            hit = next((x for x in t["item_titles"] if rx.search(x)), None)
            if hit:
                out.append({"ref": t["ref"], "ball": t["ball"], "evidence": hit[:140]})
    return out


def goal_conflicts(cfg: dict) -> list[dict]:
    """Lines in the goals files that say a decision is pending: the report asks which goal is current before measuring."""
    rx = re.compile(cfg["pending_regex"])
    out = []
    for g in cfg.get("goals_files", []):
        path = p(cfg, g)
        for n, line in enumerate(
            path.read_text().splitlines() if path.exists() else [], 1
        ):
            if rx.search(line):
                out.append({"file": str(path), "line": n, "text": line.strip()[:160]})
    return out


def project_paths(cfg: dict) -> dict[str, str]:
    path = p(cfg, cfg["projects_registry"])
    data = yaml.safe_load(path.read_text()) or {}
    out = {
        x["name"]: str(Path(os.path.expanduser(x["path"])))
        for x in data.get("projects", [])
        if x.get("path")
    }
    for name, path in (
        cfg.get("extra_projects") or {}
    ).items():  # paths the registry lacks (a monorepo root, a submodule)
        out[name] = str(Path(os.path.expanduser(path)))
    return out


def project_of(cwd: str, projects: dict[str, str]) -> str:
    """Longest registered path that contains cwd; the empty string when none does."""
    best = ""
    for name, path in projects.items():
        if (cwd == path or cwd.startswith(path + "/")) and (
            not best or len(path) > len(projects[best])
        ):
            best = name
    return best


def _prompt_text(msg: dict) -> str:
    c = msg.get("message", {}).get("content")
    if isinstance(c, str):
        return c
    if isinstance(
        c, list
    ):  # tool results are lists of non-text parts; a typed message has a text part
        return " ".join(
            x.get("text", "")
            for x in c
            if isinstance(x, dict) and x.get("type") == "text"
        )
    return ""


def redact(text: str) -> str:
    return _LONGNUM.sub("#", text)


def read_sessions(
    cfg: dict, projects: dict[str, str], start: date, end: date
) -> list[dict]:
    """One row per session with a typed user turn in the window. User turns only, never assistant output.
    Directories matching exclude_dir_substrings are not opened; sessions of automation (a headless job's
    prompt matches automation_regex) are dropped, because they are not his attention."""
    cfgs = cfg["sessions"]
    root = Path(os.path.expanduser(cfgs["dir"]))
    excl = [s for s in cfgs["exclude_dir_substrings"] if s]
    auto = re.compile(cfgs["automation_regex"]) if cfgs["automation_regex"] else None
    out = []
    for d in sorted(root.glob("*")) if root.exists() else []:
        if not d.is_dir() or any(s in d.name for s in excl):
            continue
        for f in d.glob("*.jsonl"):
            if datetime.fromtimestamp(f.stat().st_mtime).date() < start:
                continue
            prompts, cwd, first = [], "", None
            for line in f.open(encoding="utf-8", errors="replace"):
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if (
                    rec.get("type") != "user"
                    or rec.get("isSidechain")
                    or rec.get("isMeta")
                ):
                    continue
                text = _prompt_text(rec).strip()
                if not text or text.startswith("<") or "tool_use_id" in line[:200]:
                    continue
                ts = (rec.get("timestamp") or "")[:10]
                if not ts:
                    continue
                cwd = cwd or rec.get("cwd", "")
                prompts.append((ts, redact(text)[:300]))
                first = first or text
            inwin = [
                (t, x) for t, x in prompts if start <= date.fromisoformat(t) <= end
            ]
            if not inwin or (auto and first and auto.search(first[:400])):
                continue
            out.append(
                {
                    "id": f.stem,
                    "project": project_of(cwd, projects) or "(none)",
                    "cwd": cwd,
                    "dates": sorted({t for t, _ in inwin}),
                    "n_prompts": len(inwin),
                    "prompts": inwin,
                }
            )
    return out


def _git_env() -> dict[str, str]:
    """git reads these before `-C`; a caller that exports them would make every project report one repository's log."""
    return {
        k: v
        for k, v in os.environ.items()
        if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")
    }


def git_commits(path: str, start: date, end: date, author: str = "") -> list[date]:
    if not Path(path, ".git").exists():
        return []
    cmd = [
        "git",
        "-C",
        path,
        "log",
        f"--since={start}T00:00:00",
        f"--until={end}T23:59:59",
        "--format=%cs",
    ]
    if author:
        cmd.append(f"--author={author}")
    r = subprocess.run(cmd, capture_output=True, text=True, check=False, env=_git_env())
    return [date.fromisoformat(x) for x in r.stdout.split() if x]


def first_commit_date(path: str) -> date | None:
    if not Path(path, ".git").exists():
        return None
    r = subprocess.run(
        ["git", "-C", path, "log", "--reverse", "--format=%cs"],
        capture_output=True,
        text=True,
        check=False,
    )
    first = r.stdout.split()[:1]
    return date.fromisoformat(first[0]) if first else None


def release_rows(cfg: dict, start: date, end: date) -> dict:
    """Releases shipped in the window, from a command in the config that prints JSON: [{ref, title, version, date}].
    The adapter reads whatever records store releases (notes, a digest); this script never calls a store API.
    `known` is False when no command is configured or it failed, so a report says "no data" instead of "zero"."""
    cmd = cfg.get("releases_cmd")
    if not cmd:
        return {"known": False, "rows": []}
    try:
        r = subprocess.run(
            shlex.split(cmd),
            capture_output=True,
            text=True,
            cwd=cfg["_root"],
            check=False,
            timeout=60,
        )
        rows = json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        rows = None
    if rows is None:
        return {"known": False, "rows": []}
    return {
        "known": True,
        "measured": date.today().isoformat(),
        "rows": [x for x in rows if start.isoformat() <= x["date"] <= end.isoformat()],
    }


def draft_rows(cfg: dict) -> list[dict]:
    """Drafts come from a command in the config that prints JSON: [{ref, title, drafted_at, reschedule_dates[]}].
    Whatever holds the drafts (a post queue, a mail folder) is the caller's adapter, not this script's business."""
    cmd = cfg.get("drafts_cmd")
    if not cmd:
        return []
    r = subprocess.run(
        shlex.split(cmd),
        capture_output=True,
        text=True,
        cwd=cfg["_root"],
        check=False,
        timeout=60,
    )
    return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else []


# ---------------------------------------------------------------- (a) said vs did


def shares(sessions: list[dict], commits: dict[str, list[date]], cfg: dict) -> dict:
    n_s, n_c = defaultdict(int), defaultdict(int)
    for s in sessions:
        n_s[s["project"]] += 1
    for proj, ds in commits.items():
        n_c[proj] += len(ds)
    tot_s, tot_c = sum(n_s.values()), sum(n_c.values())
    pg = cfg["project_goal"]
    rows = {}
    for proj in sorted(set(n_s) | set(n_c)):
        rows[proj] = {
            "sessions": n_s[proj],
            "commits": n_c[proj],
            "share_sessions": round(n_s[proj] / tot_s, 3) if tot_s else 0.0,
            "share_commits": round(n_c[proj] / tot_c, 3) if tot_c else 0.0,
            "goal": pg.get(proj, ""),
        }
    per_goal: dict[str, dict] = defaultdict(lambda: {"sessions": 0, "commits": 0})
    for r in rows.values():
        g = r["goal"] or "(no goal)"
        per_goal[g]["sessions"] += r["sessions"]
        per_goal[g]["commits"] += r["commits"]
    for r in per_goal.values():
        r["share_sessions"] = round(r["sessions"] / tot_s, 3) if tot_s else 0.0
        r["share_commits"] = round(r["commits"] / tot_c, 3) if tot_c else 0.0
    fp = set(cfg["focus"]["projects"]) | {
        pr for pr, g in pg.items() if g in set(cfg["focus"]["goals"])
    }
    focus_s = sum(n_s[x] for x in fp)
    focus_c = sum(n_c[x] for x in fp)
    return {
        "total_sessions": tot_s,
        "total_commits": tot_c,
        "per_project": rows,
        "per_goal": dict(per_goal),
        "focus_projects": sorted(fp),
        "share_focus_sessions": round(focus_s / tot_s, 3) if tot_s else 0.0,
        "share_focus_commits": round(focus_c / tot_c, 3) if tot_c else 0.0,
        **portfolio_numbers(cfg, n_s, n_c, tot_s, tot_c, fp),
    }


def portfolio_numbers(cfg, n_s, n_c, tot_s, tot_c, fp) -> dict:
    """Two numbers for a portfolio goal: the share of attention on the whole earning portfolio (`focus.projects`), the
    concentration inside it (`focus.top` over the portfolio), and the plain share on things that are neither an
    earning app nor the visa (`focus.defocus`). Sessions are the attention measure; commits are reported beside them."""
    top = set(cfg["focus"].get("top") or [])
    dfc = set(cfg["focus"].get("defocus") or [])

    def share(num: int, den: int) -> float:
        return round(num / den, 3) if den else 0.0

    ps, pc = sum(n_s[x] for x in fp), sum(n_c[x] for x in fp)
    ts, tc = sum(n_s[x] for x in top), sum(n_c[x] for x in top)
    return {
        "top_projects": sorted(top),
        "concentration_sessions": share(ts, ps),
        "concentration_commits": share(tc, pc),
        "defocus_projects": sorted(dfc),
        "share_defocus_sessions": share(sum(n_s[x] for x in dfc), tot_s),
        "share_defocus_commits": share(sum(n_c[x] for x in dfc), tot_c),
    }


# ---------------------------------------------------------------- (b) patterns


def _tokens(text: str) -> frozenset:
    return frozenset(w.lower() for w in _WORD.findall(text))


def correction_clusters(
    sessions: list[dict], regex: str, min_sim: float = 0.4
) -> list[dict]:
    """Short corrective prompts grouped by shared words. Greedy, deterministic; a cluster is the same correction
    given in different sessions, counted per distinct session."""
    rx = re.compile(regex, re.IGNORECASE)
    cands = []
    for s in sessions:
        for ts, text in s["prompts"]:
            if len(text) <= 220 and rx.search(text.strip()):
                toks = _tokens(text)
                if len(toks) >= 2:
                    cands.append((ts, s["id"], text, toks))
    clusters: list[dict] = []
    for ts, sid, text, toks in sorted(cands):
        for c in clusters:
            inter, union = len(toks & c["tokens"]), len(toks | c["tokens"])
            if union and inter / union >= min_sim:
                c["items"].append((ts, sid, text))
                c["tokens"] = c["tokens"] | toks
                break
        else:
            clusters.append({"tokens": toks, "items": [(ts, sid, text)]})
    return [
        {
            "sessions": len({i[1] for i in c["items"]}),
            "dates": sorted({i[0] for i in c["items"]}),
            "occ_dates": sorted(i[0] for i in c["items"]),
            "example": c["items"][0][2][:160],
            "session_ids": sorted({i[1] for i in c["items"]}),
        }
        for c in clusters
    ]


def find_patterns(
    cfg: dict,
    today: date,
    start: date,
    todos: list[dict],
    topics: list[dict],
    drafts: list[dict],
    sessions: list[dict],
    new_projects: list[tuple[str, date]],
    focus_active: bool,
) -> list[Pattern]:
    out: list[Pattern] = []
    # items rescheduled N times inside the window
    for t in todos:
        ds = [d for d in t["reschedules"] if start <= d <= today]
        if ds:
            out.append(
                Pattern(
                    f"reschedule:{t['ref']}",
                    "reschedule",
                    ds,
                    f"{len(ds)} переносов срока: {t['ref']}",
                    [t["ref"]],
                )
            )
    for dr in drafts:
        ds = [
            date.fromisoformat(x)
            for x in dr.get("reschedule_dates", [])
            if start <= date.fromisoformat(x) <= today
        ]
        if ds:
            out.append(
                Pattern(
                    f"reschedule:{dr['ref']}",
                    "reschedule",
                    ds,
                    f"{len(ds)} переносов даты: {dr['ref']}",
                    [dr["ref"]],
                )
            )
    # drafts written and not sent for more than N days
    stale = [
        dr
        for dr in drafts
        if dr.get("drafted_at")
        and (today - date.fromisoformat(dr["drafted_at"][:10])).days
        > cfg["stale_draft_days"]
    ]
    if stale:
        oldest = max(
            (today - date.fromisoformat(d["drafted_at"][:10])).days for d in stale
        )
        out.append(
            Pattern(
                "stale-drafts",
                "drafts",
                [date.fromisoformat(d["drafted_at"][:10]) for d in stale],
                f"{len(stale)} черновиков старше {cfg['stale_draft_days']} дн., старейший {oldest} дн.",
                [d["ref"] for d in stale],
            )
        )
    # topics opened and gone quiet
    quiet = [
        t
        for t in topics
        if t["quiet_days"] >= cfg["quiet_topic_days"] and t["items_open"] > 0
    ]
    if quiet:
        out.append(
            Pattern(
                "quiet-topics",
                "quiet",
                [date.fromisoformat(t["updated"]) for t in quiet if t["updated"]],
                f"{len(quiet)} тем без движения {cfg['quiet_topic_days']}+ дн.",
                [t["ref"] for t in quiet],
            )
        )
    # the same correction in several sessions
    for c in correction_clusters(sessions, cfg["correction_regex"]):
        if c["sessions"] >= 2:
            out.append(
                Pattern(
                    f"correction:{c['session_ids'][0][:8]}",
                    "correction",
                    [date.fromisoformat(x) for x in c["occ_dates"]],
                    f"одна правка в {c['sessions']} сессиях: «{c['example'][:80]}»",
                    c["session_ids"][:5],
                )
            )
    # a new project started while the declared focus is untouched
    if new_projects and not focus_active:
        out.append(
            Pattern(
                "new-project-focus-idle",
                "new_project",
                [d for _, d in new_projects],
                f"{len(new_projects)} новых проектов при нетронутом фокусе: "
                + ", ".join(n for n, _ in new_projects),
                [n for n, _ in new_projects],
            )
        )
    return out


# ---------------------------------------------------------------- ledger, experiments


def read_ledger(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(x) for x in path.read_text().splitlines() if x.strip()]


def prev_week(week: str) -> str:
    y, w = int(week[:4]), int(week[-2:])
    d = date.fromisocalendar(y, w, 1) - timedelta(days=7)
    return iso_week(d)


def streak(ledger: list[dict], pattern_id: str, week: str) -> int:
    """Consecutive weeks, counting `week` itself, in which the pattern was recorded or is being reported now."""
    weeks = {
        e["week"]
        for e in ledger
        if e.get("type") == "pattern" and e.get("id") == pattern_id
    }
    n, w = 1, prev_week(week)
    while w in weeks:
        n += 1
        w = prev_week(w)
    return n


_OPS = {
    ">=": lambda a, b: a >= b,
    "<=": lambda a, b: a <= b,
    ">": lambda a, b: a > b,
    "<": lambda a, b: a < b,
    "==": lambda a, b: a == b,
}


def judge(exp: dict, metrics: dict) -> dict:
    """Verdict on an experiment {metric, op, value}: the metric is read from the same numbers `collect` prints."""
    cur: object = metrics
    for part in str(exp["metric"]).split("."):
        cur = cur.get(part) if isinstance(cur, dict) else None
    if cur is None:
        return {
            "verdict": "unknown",
            "metric": exp["metric"],
            "actual": None,
            "target": f"{exp['op']} {exp['value']}",
        }
    ok = _OPS[exp["op"]](cur, exp["value"])
    return {
        "verdict": "met" if ok else "missed",
        "metric": exp["metric"],
        "actual": cur,
        "target": f"{exp['op']} {exp['value']}",
    }


# ---------------------------------------------------------------- load reduction


def goal_of_topic(t: dict, roots: dict[str, set[str]], topics_by_id: dict) -> str:
    """A registry topic has a goal when it is a goal itself (it has children) or reaches a root through parents."""
    return (
        ""
        if t["parents"] == []
        and not any(t["ref"] in x["parents"] for x in topics_by_id.values())
        else "yes"
    )


def goal_slugs(todos: list[dict], topics: list[dict], cfg: dict) -> set[str]:
    """Topics that are goals: named in goal_priority, as a todo's goal, or as somebody's parent."""
    return (
        set(cfg["goal_priority"])
        | {t["goal"] for t in todos if t["goal"] not in ("", "?")}
        | {x for t in topics for x in t["parents"]}
    )


def protected_items(todos: list[dict]) -> list[dict]:
    return [
        {
            "ref": t["ref"],
            "title": t["title"],
            "due": t["due"],
            "effort": t["effort"],
            "last_note": t["last_note"],
        }
        for t in todos
        if t.get("protected")
    ]


def cut_list(
    todos: list[dict], topics: list[dict], cfg: dict, today: date
) -> list[dict]:
    out = []
    by_id = {t["ref"]: t for t in topics}
    goals = goal_slugs(todos, topics, cfg)
    for t in topics:
        goal = (
            "yes" if t["ref"] in goals else goal_of_topic(t, goal_roots(topics), by_id)
        )
        silent = t["quiet_days"] >= cfg["silent_days"]
        if not goal or silent:
            why = (
                ("нет цели" if not goal else "")
                + (", " if not goal and silent else "")
                + (f"тишина {t['quiet_days']} дн." if silent else "")
            )
            out.append(
                {
                    "ref": t["ref"],
                    "title": t["title"],
                    "why": why,
                    "proposal": _propose(not goal, silent, t["due"], today),
                    "kind": "topic",
                }
            )
    for t in todos:
        if t.get("protected"):
            continue  # a compliance, verification, legal, tax or penalty consequence: parked with a date or sized, never cut
        no_goal = t["goal"] in ("", "?")
        overdue = (today - date.fromisoformat(t["due"])).days if t["due"] else 0
        silent = overdue >= cfg["silent_days"]
        if no_goal and (
            silent or not t["due"] or len(t["reschedules"]) >= cfg["min_occurrences"]
        ):
            why = (
                "нет цели"
                + (f", срок просрочен на {overdue} дн." if silent else "")
                + (f", {len(t['reschedules'])} переносов" if t["reschedules"] else "")
            )
            out.append(
                {
                    "ref": t["ref"],
                    "title": t["title"],
                    "why": why,
                    "proposal": _propose(
                        True,
                        silent
                        or bool(t["reschedules"])
                        and t["due"] <= today.isoformat(),
                        t["due"],
                        today,
                    ),
                    "kind": "todo",
                }
            )
    return out


def _propose(no_goal: bool, silent: bool, due: str, today: date) -> str:
    if no_goal and silent:
        return "drop"
    if no_goal and due and due > today.isoformat():
        return "park-until " + due
    if no_goal:
        return "delegate-to-agent or park"
    return "park-until next review"


def effort_hours(effort) -> float | None:
    """Hours from an effort string such as '45 min', '2h', '1.5 ч'; None when no volume is stated."""
    m = re.search(r"(\d+(?:[.,]\d+)?)\s*(min|мин|m\b|h|ч)", str(effort or ""), re.I)
    if not m:
        return None
    n = float(m[1].replace(",", "."))
    return round(n / 60 if m[2].lower().startswith(("m", "мин")) else n, 2)


def week_candidates(
    todos: list[dict], topics: list[dict], cfg: dict, today: date, horizon: int = 7
) -> list[dict]:
    """Ranked pool for the «this week only» list: items behind a priority goal first, then by due date."""
    prio = {g: i for i, g in enumerate(cfg["goal_priority"])}
    rows = []
    roots = goal_roots(topics)
    for t in todos:
        if (
            t["due"]
            and (date.fromisoformat(t["due"]) - today).days <= horizon
            and t["goal"] not in ("", "?")
        ):
            rows.append(
                {
                    "ref": t["ref"],
                    "title": t["title"],
                    "due": t["due"],
                    "goal": t["goal"],
                    "why": t["purpose"],
                    "effort": t["effort"],
                    "cost_h": effort_hours(t["effort"]),
                    "kind": t.get("kind") or "",
                    "last_note": t["last_note"],
                    "rank": prio.get(t["goal"], len(prio)),
                }
            )
    for t in topics:
        rs = sorted(roots[t["ref"]] - {t["ref"]}, key=lambda g: prio.get(g, len(prio)))
        if (
            rs
            and t["due"]
            and 0 <= (date.fromisoformat(t["due"][:10]) - today).days <= horizon
        ):
            rows.append(
                {
                    "ref": t["ref"],
                    "title": t["title"],
                    "due": t["due"][:10],
                    "goal": rs[0],
                    "why": "",
                    "rank": prio.get(rs[0], len(prio)),
                }
            )
    return sorted(rows, key=lambda r: (r["rank"], r["due"]))[:10]


# ---------------------------------------------------------------- collect


def open_loops(todos: list[dict], topics: list[dict], cfg: dict) -> dict:
    """What he carries in his head: open items whose ball is on him and that have no dated next step.
    A plan closes a loop, not the completion: an item with a due date and a first step does not count."""
    mine = set(cfg["ball_names"])
    t_loops = [
        t["ref"]
        for t in todos
        if t["status"] in ("todo", "doing") and not (t["due"] and t["has_next"])
    ]
    r_loops = [
        t["ref"]
        for t in topics
        if t["ball"] in mine and not (t["due"] and t["has_next"])
    ]
    return {
        "count": len(t_loops) + len(r_loops),
        "todo": len(t_loops),
        "topics": len(r_loops),
    }


def _journal_cfg(cfg: dict) -> dict:
    jc = cfg.get("journal") or {}
    return {
        **cfg,
        "journal": {
            "path": str(p(cfg, jc.get("path", "mirror/prompts.jsonl"))),
            "cursor": str(p(cfg, jc.get("cursor", "mirror/prompts.cursor.json"))),
        },
    }


def journal_update(
    cfg: dict, relabel: bool = False, limit_files: int | None = None
) -> dict:
    """Bring the prompt journal up to date: new bytes only, a model call only for new own prompts."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mirror_energy as me
    import mirror_journal as mj

    jcfg = _journal_cfg(cfg)
    if relabel:  # on demand only: keep the old files beside, rebuild
        for k in ("path", "cursor"):
            f = Path(jcfg["journal"][k])
            if f.exists():
                f.rename(f.with_name(f.name + f".v{mj.LABEL_VERSION}.prev"))
    rules = me.settings(cfg)["timezones"]
    projects = project_paths(cfg)
    return mj.update(
        jcfg,
        lambda cwd: project_of(cwd, projects) or Path(cwd or "/").name or "(none)",
        lambda ts: me.tz_for(ts, rules),
        limit_files=limit_files,
    )


def energy_block(cfg: dict, end: date, ingest: bool = True) -> dict:
    """Blocks, leak and hours from the journal (after an incremental update). Writes energy.json when configured."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mirror_energy as me
    import mirror_journal as mj

    stats = journal_update(cfg) if ingest else {}
    rows = mj.read_journal(Path(_journal_cfg(cfg)["journal"]["path"]))
    out = me.compute(cfg, rows, end)
    out["journal"] = {"rows": len(rows), **stats}
    target = (cfg.get("energy") or {}).get("output")
    if target:
        path = p(cfg, target)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n")
    return out


def energy_today(cfg: dict, ingest: bool = False) -> dict:
    """Fast path: recompute from the journal (no transcript is read unless `ingest`)."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mirror_energy as me

    today = datetime.now(timezone.utc)
    local = today.astimezone(me.tz_for(today, me.settings(cfg)["timezones"])).date()
    return energy_block(cfg, local, ingest=ingest)


def _tools_mod():
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mirror_tools

    return mirror_tools


def tools_block(cfg: dict, end: date, root: Path) -> dict:
    return _tools_mod().tools_block(cfg, end, root)


def collect(cfg: dict, end: date, days: int) -> dict:
    start = end - timedelta(days=days - 1)
    week = iso_week(end)
    projects = project_paths(cfg)
    todos, topics = todo_items(cfg, end), registry_topics(cfg, end)
    sessions = read_sessions(cfg, projects, start, end)
    author = cfg.get("author_regex", "")
    commits = {
        n: ds
        for n, path in projects.items()
        if (ds := git_commits(path, start, end, author))
    }
    drafts = draft_rows(cfg)
    sh = shares(sessions, commits, cfg)
    focus = set(sh["focus_projects"])
    focus_active = any(
        sh["per_project"].get(f, {}).get("sessions", 0)
        + sh["per_project"].get(f, {}).get("commits", 0)
        for f in focus
    )
    new_projects = []
    for n, path in projects.items():
        fc = first_commit_date(path)
        if fc and start <= fc <= end:
            new_projects.append((n, fc))
    pats = find_patterns(
        cfg, end, start, todos, topics, drafts, sessions, new_projects, focus_active
    )
    ledger_path = p(cfg, cfg.get("ledger", "mirror/ledger.jsonl"))
    ledger = read_ledger(ledger_path)
    minimum = cfg["min_occurrences"]
    reported = [
        {
            "id": x.id,
            "kind": x.kind,
            "count": x.count,
            "dates": [d.isoformat() for d in x.dates],
            "number": x.number,
            "refs": x.refs,
            "bucket": x.bucket,
            "weeks_in_a_row": streak(ledger, x.id, week),
        }
        for x in pats
        if qualifies(x, minimum)
    ]
    below = [
        {"id": x.id, "count": x.count, "number": x.number}
        for x in pats
        if not qualifies(x, minimum)
    ]
    done = done_log(cfg, start, end, drafts)
    metrics = {
        "share_focus_sessions": sh["share_focus_sessions"],
        "share_focus_commits": sh["share_focus_commits"],
        "sessions": {k: v["share_sessions"] for k, v in sh["per_project"].items()},
        "commits": {k: v["share_commits"] for k, v in sh["per_project"].items()},
        "reschedules_total": sum(
            len([d for d in t["reschedules"] if start <= d <= end]) for t in todos
        ),
        "stale_drafts": sum(
            1
            for d in drafts
            if d.get("drafted_at")
            and (end - date.fromisoformat(d["drafted_at"][:10])).days
            > cfg["stale_draft_days"]
        ),
        "new_projects": len(new_projects),
        "sent": sum(1 for x in done if x["kind"] == "sent"),
    }
    last_exp = next(
        (
            e
            for e in reversed(ledger)
            if e.get("type") == "experiment" and e["week"] == prev_week(week)
        ),
        None,
    )
    result = {
        "week": week,
        "window": {"start": start.isoformat(), "end": end.isoformat(), "days": days},
        "said_vs_did": {**sh, "stated_focus": cfg["focus"]},
        "patterns": reported,
        "below_threshold": below,
        "experiment_last_week": (
            {**last_exp, "result": judge(last_exp, metrics)} if last_exp else None
        ),
        "metrics": metrics,
        "cut_list": cut_list(todos, topics, cfg, end),
        "this_week_candidates": week_candidates(todos, topics, cfg, end),
        "protected_not_cut": protected_items(todos),
        "releases": release_rows(cfg, start, end),
        "done_log": done,
        "noise_waiting_already_answered": stale_waits(topics, cfg["answered_regex"]),
        "goal_conflicts": goal_conflicts(cfg),
        "energy": energy_block(cfg, end),
        "tools": tools_block(cfg, end, cfg["_root"]),
        "open_loops": {
            **open_loops(todos, topics, cfg),
            "previous": next(
                (
                    e.get("count")
                    for e in reversed(ledger)
                    if e.get("type") == "loops" and e.get("week") == prev_week(week)
                ),
                None,
            ),
            "ledger_entry": "append {type: loops, week, count} so next week can compare",
        },
        "inputs": {
            "sessions": len(sessions),
            "todo_items": len(todos),
            "topics": len(topics),
            "drafts": len(drafts),
            "goals_files": [str(p(cfg, g)) for g in cfg.get("goals_files", [])],
        },
        "ledger": str(ledger_path),
    }
    result["arrows"] = _tools_mod().arrows(
        result["energy"], result["open_loops"], result["tools"]
    )
    return result


# ---------------------------------------------------------------- lint


def lint(text: str, max_chars: int) -> list[str]:
    problems = []
    if len(text) > max_chars:
        problems.append(f"{len(text)} chars > {max_chars}")
    if "—" in text:
        problems.append(f"{text.count('—')} em dash(es)")
    # observations are the numbered lines between the repeats heading and the experiment; the "this week" list has its own limit
    m = re.search(
        r"Повторы.*?(?=^Эксперимент|^\s*$|\Z)", text, re.DOTALL | re.MULTILINE
    )
    if len(re.findall(r"^\s*\d+[.)]\s", m[0] if m else text, re.MULTILINE)) > 3:
        problems.append("more than 3 numbered observations")
    return problems


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("collect")
    c.add_argument("--config", required=True)
    c.add_argument("--days", type=int, default=14)
    c.add_argument("--end", default="")
    c.add_argument("--json", action="store_true")
    e = sub.add_parser(
        "energy", help="fast: blocks against capacity, recomputed from the journal"
    )
    e.add_argument("--config", required=True)
    e.add_argument(
        "--ingest",
        action="store_true",
        help="also read new transcript bytes (may call the model)",
    )
    jn = sub.add_parser("journal", help="update the prompt journal incrementally")
    jn.add_argument("--config", required=True)
    jn.add_argument(
        "--relabel",
        action="store_true",
        help="rebuild all labels (label set changed); keeps the old files as .prev",
    )
    jn.add_argument("--limit-files", type=int, default=0)
    a = sub.add_parser("ledger-append")
    a.add_argument("--config", required=True)
    a.add_argument(
        "--file",
        required=True,
        help="JSON list of ledger entries (type pattern|experiment, week, ...)",
    )
    lt = sub.add_parser("lint")
    lt.add_argument("report")
    lt.add_argument("--max-chars", type=int, default=2400)
    args = ap.parse_args(argv)
    if args.cmd == "lint":
        probs = lint(Path(args.report).read_text(), args.max_chars)
        print("\n".join(probs) or "ok")
        return 1 if probs else 0
    cfg = load_config(Path(args.config))
    if args.cmd == "journal":
        print(json.dumps(journal_update(cfg, args.relabel, args.limit_files or None)))
        return 0
    if args.cmd == "energy":
        o = energy_today(cfg, args.ingest)
        keys = (
            "blocks_today",
            "suggested_blocks_today",
            "debt_blocks",
            "blocks_week",
            "blocks_week_capacity",
        )
        line = (o.get("work_week") or {}).get("midweek_line")
        print(
            json.dumps(
                {k: o[k] for k in keys} | {"midweek_line": line}, ensure_ascii=False
            )
        )
        return 0
    if args.cmd == "ledger-append":
        path = p(cfg, cfg.get("ledger", "mirror/ledger.jsonl"))
        path.parent.mkdir(parents=True, exist_ok=True)
        entries = json.loads(Path(args.file).read_text())
        with path.open("a") as fh:
            for e in entries:
                fh.write(json.dumps(e, ensure_ascii=False) + "\n")
        print(f"appended {len(entries)} to {path}")
        return 0
    end = date.fromisoformat(args.end) if args.end else date.today()
    out = collect(cfg, end, args.days)
    print(
        json.dumps(out, ensure_ascii=False, indent=1)
        if args.json
        else json.dumps(out, ensure_ascii=False)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
