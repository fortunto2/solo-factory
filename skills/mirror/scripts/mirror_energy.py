"""Energy and attention modes from the timestamps of typed prompts. Read-only; no prompt text is stored or printed.

A typed prompt is a user turn in a Claude Code transcript that is left after stripping injected blocks (reminders,
task notifications, teammate messages) and that is not the opening prompt of an automated job. Per local day:

  active_h   distinct 15-minute buckets holding a typed prompt, divided by 4
  modes      a bucket takes the highest mode among its prompts: task (>= task_min chars, sets work), steer (>= steer_min,
             corrects or directs), kick (shorter: a nudge, yes/no, "continue"); hours per mode and prompt counts
  spent_h    task + steer hours at full weight plus kick hours at weight kick (default 0.5): the budgeted attention
  projects, switches (project changes between consecutive prompts), longest_block_h (longest run of adjacent buckets on
  one project), night_h (buckets 00:00-06:00), first and last active time

Budget: budget_hours_per_day, week_budget = 7 x budget, overload_days = days with spent >= 2 x budget, debt = sum over the
7 days before today of max(0, spent - budget), suggested_today = budget - min(budget / 2, debt / 4) rounded to 0.5.
"""

from __future__ import annotations

import json
import os
import re
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

BUCKET_MIN = 15
INJECTED = re.compile(
    r"<(system-reminder|command-name|command-message|command-args|local-command-stdout|local-command-stderr|"
    r"task-notification|teammate-message|bash-input|bash-stdout|bash-stderr)\b.*?</\1>",
    re.DOTALL,
)
DEFAULTS = {
    "budget_hours_per_day": 4.0,
    "days_per_week": 7,
    "weights": {"task": 1.0, "steer": 1.0, "kick": 0.5},
    "task_min": 250,
    "steer_min": 50,
    # first rule whose `until` (UTC date, inclusive) has not passed wins; the last rule has no `until`
    "timezones": [{"tz": "UTC"}],
    "overload_factor": 2.0,
    # user-role messages Claude Code itself or other sessions inject, not typed by the person
    "not_typed_regex": r"^(Another Claude|This session is being continued|\[Request interrupted|<artifact-comment|\[SYSTEM NOTIFICATION)",
    "not_measured": [
        "sessions in excluded directories (personal, client work) and in a separate work profile are not counted, so real load is higher",
        "time spent without typing (reading, thinking, waiting for an agent) is invisible",
    ],
}


def settings(cfg: dict) -> dict:
    return {**DEFAULTS, **(cfg.get("energy") or {})}


def tz_for(ts_utc: datetime, rules: list[dict]) -> ZoneInfo:
    d = ts_utc.date()
    for r in rules:
        if "until" not in r or d <= date.fromisoformat(str(r["until"])):
            return ZoneInfo(r["tz"])
    return ZoneInfo(rules[-1]["tz"])


def mode_of(length: int, es: dict) -> str:
    return (
        "task"
        if length >= es["task_min"]
        else "steer"
        if length >= es["steer_min"]
        else "kick"
    )


_RANK = {"kick": 0, "steer": 1, "task": 2}


def typed_length(text: str) -> int:
    """Length of what he typed: the message with injected blocks removed."""
    return len(INJECTED.sub("", text).strip())


def read_typed(
    cfg: dict, projects_of, since: datetime
) -> list[tuple[datetime, str, int]]:
    """(utc time, project, length) of every typed prompt at or after `since`. `projects_of(cwd)` maps a cwd to a project."""
    sess = cfg["sessions"]
    root = Path(os.path.expanduser(sess["dir"]))
    excl = [s for s in sess["exclude_dir_substrings"] if s]
    auto = re.compile(sess["automation_regex"]) if sess["automation_regex"] else None
    not_typed = re.compile(settings(cfg)["not_typed_regex"])
    out = []
    for d in sorted(root.glob("*")) if root.exists() else []:
        if not d.is_dir() or any(s in d.name for s in excl):
            continue
        for f in d.glob("*.jsonl"):
            if datetime.fromtimestamp(f.stat().st_mtime, timezone.utc) < since:
                continue
            rows, first, cwd, is_auto = [], True, "", False
            for line in f.open(encoding="utf-8", errors="replace"):
                if '"type":"user"' not in line:
                    continue
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
                c = rec.get("message", {}).get("content")
                text = (
                    c
                    if isinstance(c, str)
                    else " ".join(
                        x.get("text", "")
                        for x in c
                        if isinstance(x, dict) and x.get("type") == "text"
                    )
                    if isinstance(c, list)
                    else ""
                )
                text = INJECTED.sub("", text).strip()
                if not text or not rec.get("timestamp") or not_typed.search(text):
                    continue
                cwd = cwd or rec.get("cwd", "")
                if first:
                    first = False
                    is_auto = bool(auto and auto.search(text[:400]))
                if is_auto:
                    break
                rows.append(
                    (
                        datetime.fromisoformat(rec["timestamp"].replace("Z", "+00:00")),
                        len(text),
                    )
                )
            proj = projects_of(cwd) or "(none)"
            out += [(t, proj, n) for t, n in rows if t >= since]
    return sorted(out)


def per_day(prompts: list[tuple[datetime, str, int]], es: dict) -> dict[str, dict]:
    """Day table from typed prompts. Local day and bucket come from the timezone rule valid at that instant."""
    by_day: dict[str, list] = defaultdict(list)
    for t, proj, n in prompts:
        loc = t.astimezone(tz_for(t, es["timezones"]))
        by_day[loc.date().isoformat()].append((loc, proj, n))
    w = es["weights"]
    days = {}
    for day, rows in sorted(by_day.items()):
        rows.sort(key=lambda r: r[0])
        buckets: dict[int, dict] = {}
        counts = {"task": 0, "steer": 0, "kick": 0}
        for loc, proj, n in rows:
            m = mode_of(n, es)
            counts[m] += 1
            b = buckets.setdefault(
                loc.hour * 4 + loc.minute // BUCKET_MIN,
                {"mode": "kick", "projects": defaultdict(int)},
            )
            if _RANK[m] > _RANK[b["mode"]]:
                b["mode"] = m
            b["projects"][proj] += 1
        hours = {
            m: sum(1 for b in buckets.values() if b["mode"] == m) / 4 for m in counts
        }
        owner = {
            i: max(b["projects"].items(), key=lambda kv: kv[1])[0]
            for i, b in buckets.items()
        }
        longest, run, prev = 0, 0, None
        for i in sorted(buckets):
            run = (
                run + 1
                if prev is not None and i == prev + 1 and owner[i] == owner[prev]
                else 1
            )
            longest, prev = max(longest, run), i
        projs = [p for _, p, _ in rows]
        days[day] = {
            "active_h": len(buckets) / 4,
            "mode_h": hours,
            "prompts": counts,
            "spent_h": round(sum(hours[m] * w[m] for m in hours), 3),
            "projects": len(set(projs)),
            "switches": sum(
                1 for a, b in zip(projs, projs[1:], strict=False) if a != b
            ),
            "longest_block_h": longest / 4,
            "night_h": sum(1 for i in buckets if i < 24) / 4,
            "first": rows[0][0].strftime("%H:%M"),
            "last": rows[-1][0].strftime("%H:%M"),
        }
    return days


def budget(days: dict[str, dict], today: date, es: dict) -> dict:
    b = es["budget_hours_per_day"]
    prev7 = [(today - timedelta(days=i)).isoformat() for i in range(1, 8)]
    debt = sum(max(0.0, days.get(d, {}).get("spent_h", 0.0) - b) for d in prev7)
    suggested = max(b / 2, b - min(b / 2, debt / 4))
    last7 = [(today - timedelta(days=i)).isoformat() for i in range(6, -1, -1)]
    return {
        "budget_hours_per_day": b,
        "week_budget": b * es["days_per_week"],
        "week_spent": round(sum(days.get(d, {}).get("spent_h", 0.0) for d in last7), 2),
        "overload_days": [
            d
            for d in last7
            if days.get(d, {}).get("spent_h", 0.0) >= es["overload_factor"] * b
        ],
        "debt": round(debt, 2),
        "suggested_today": round(suggested * 2) / 2,
        "capacity_h": round(max(0.0, b * es["days_per_week"] - debt), 2),
    }


def summary(days: dict[str, dict], today: date, es: dict) -> dict:
    last7 = [(today - timedelta(days=i)).isoformat() for i in range(6, -1, -1)]
    rows = [days[d] | {"date": d} for d in last7 if d in days]
    tot = {m: sum(r["mode_h"][m] for r in rows) for m in ("task", "steer", "kick")}
    longest = max(rows, key=lambda r: r["longest_block_h"], default=None)
    return {
        "mode_hours_week": tot,
        "longest_block": {"h": longest["longest_block_h"], "date": longest["date"]}
        if longest
        else None,
        "switches_per_day": round(sum(r["switches"] for r in rows) / len(rows), 1)
        if rows
        else 0,
        "days_over_50_switches": [r["date"] for r in rows if r["switches"] > 50],
    }


def compute(cfg: dict, projects_of, today: date, days_back: int = 16) -> dict:
    es = settings(cfg)
    since = datetime.combine(
        today - timedelta(days=days_back), datetime.min.time(), timezone.utc
    )
    days = per_day(read_typed(cfg, projects_of, since), es)
    out = {
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "weights": es["weights"],
        "thresholds": {"task_min": es["task_min"], "steer_min": es["steer_min"]},
        "timezones": es["timezones"],
        **budget(days, today, es),
        **summary(days, today, es),
        "days": days,
        "not_measured": es["not_measured"],
    }
    out["today"] = days.get(today.isoformat())
    return out


def today_fast(cfg: dict, projects_of, now: datetime, previous: dict) -> dict:
    """Only today's transcripts are read; earlier days come from the last full run's table. `previous` is energy.json."""
    es = settings(cfg)
    today = now.astimezone(tz_for(now, es["timezones"])).date()
    since = datetime.combine(
        today - timedelta(days=1), datetime.min.time(), timezone.utc
    )  # local day may start the UTC day before
    fresh = {
        d: v
        for d, v in per_day(read_typed(cfg, projects_of, since), es).items()
        if d == today.isoformat()
    }
    days = {**previous.get("days", {}), **fresh}
    out = {
        **previous,
        **budget(days, today, es),
        "days": days,
        "today": days.get(today.isoformat()),
        "refreshed": now.isoformat(timespec="seconds"),
    }
    spent = (out["today"] or {}).get("spent_h", 0.0)
    out["remaining_today_h"] = round(out["suggested_today"] - spent, 2)
    return out
