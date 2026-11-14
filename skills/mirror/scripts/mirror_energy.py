"""Creative blocks, routine leak and open loops, from the journal of typed prompts (mirror_journal). Read-only.

Hours stay in the data as the raw layer. The three derived numbers lead the report:

  blocks   a creative block is a run of >= block_min_buckets (default 3, i.e. 45 min) 15-minute buckets on ONE own
           project whose top label is in block_labels (task/think/steer) and that no bucket of another project, of
           the work profile, or of a routine label interrupts. block_gap_buckets (default 1) silent buckets between
           two such buckets are tolerated: an agent working for 15 minutes is not a break in thinking.
           Budget = blocks_per_day (default 3, about 4 h). debt = sum over the 7 days before today of
           max(0, blocks - capacity); suggested_today = capacity - min(capacity / 2, debt / 4), to 0.5.
  leak     the share of own active buckets whose top label is routine (decide/kick/watch), and switches per active hour.
  loops    open items whose ball is on the person and that have no dated next step (computed by the collector).

Per day also: own_h / work_h / overlap_h / total_h (buckets of 15 minutes; overlap counted once), hours per top label,
spent_h (label weights, a bucket with work at full weight), projects, switches, longest_block_h, night_h, first/last.
The journal holds no text; the work profile contributes time only.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

BUCKET_MIN = 15
LABELS = ("task", "think", "steer", "decide", "watch", "kick", "other")
DEFAULTS = {
    "blocks_per_day": 3,
    "block_min_buckets": 3,
    "block_gap_buckets": 1,
    "block_labels": ["task", "think", "steer"],
    "routine_labels": ["decide", "kick", "watch"],
    "weights": {
        "task": 1.0,
        "think": 1.0,
        "steer": 1.0,
        "decide": 0.5,
        "watch": 0.25,
        "kick": 0.25,
        "other": 0.25,
    },
    # rules apply from `from` (a UTC date or datetime) until the next rule; the first rule needs no `from`
    "timezones": [{"tz": "UTC"}],
    "not_measured": [
        "personal sessions and any directory in exclude_dir_substrings are not counted",
        "a second profile (work) is counted as time only, from timestamps",
        "time spent without typing (reading, thinking, waiting for an agent) is invisible",
    ],
}


def settings(cfg: dict) -> dict:
    es = {**DEFAULTS, **(cfg.get("energy") or {})}
    es["weights"] = {**DEFAULTS["weights"], **es["weights"]}
    return es


def _start(rule: dict) -> datetime:
    f = rule.get("from")
    if f is None:
        return datetime.min.replace(tzinfo=timezone.utc)
    if isinstance(f, datetime):
        return f if f.tzinfo else f.replace(tzinfo=timezone.utc)
    if isinstance(f, date):
        return datetime(f.year, f.month, f.day, tzinfo=timezone.utc)
    d = datetime.fromisoformat(str(f).replace("Z", "+00:00"))
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def rule_at(ts_utc: datetime, rules: list[dict]) -> dict:
    """The timeline rule in force at an instant: the last rule that has started."""
    cur = rules[0]
    for r in sorted(rules, key=_start):
        if _start(r) <= ts_utc:
            cur = r
    return cur


def tz_for(ts_utc: datetime, rules: list[dict]) -> ZoneInfo:
    return ZoneInfo(rule_at(ts_utc, rules)["tz"])


def travel_days(rules: list[dict]) -> set[str]:
    """The day of every zone change and the day after (jet lag). Marked, not judged."""
    out = set()
    for r in sorted(rules, key=_start):
        if r.get("from") is not None:
            d = _start(r).astimezone(ZoneInfo(r["tz"])).date()
            out |= {d.isoformat(), (d + timedelta(days=1)).isoformat()}
    return out


def parse_ts(s: str) -> datetime:
    return datetime.fromisoformat(s).astimezone(timezone.utc)


def _blocks(own: dict[int, dict], work: set[int], es: dict) -> list[int]:
    """Lengths (in buckets, gaps included) of the qualifying creative blocks of one day."""
    creative = {
        i for i, b in own.items() if b["label"] in es["block_labels"] and i not in work
    }
    out, run = [], None  # run = [project, first, last]
    for i in sorted(set(own) | work):
        if i in creative:
            proj = own[i]["owner"]
            if run and run[0] == proj and i - run[2] - 1 <= es["block_gap_buckets"]:
                run[2] = i
                continue
            if run:
                out.append(run[2] - run[1] + 1)
            run = [proj, i, i]
        elif (
            run
        ):  # a non-creative bucket (routine, other project's, work) ends the block
            out.append(run[2] - run[1] + 1)
            run = None
    if run:
        out.append(run[2] - run[1] + 1)
    return [n for n in out if n >= es["block_min_buckets"]]


def per_day(rows: list[dict], es: dict) -> dict[str, dict]:
    """Day table from journal rows. Local day and bucket follow the timeline rule in force at that instant."""
    by_day: dict[str, list] = defaultdict(list)
    for r in rows:
        t = parse_ts(r["ts"])
        loc = t.astimezone(tz_for(t, es["timezones"]))
        by_day[loc.date().isoformat()].append((loc, r))
    w, days = es["weights"], {}
    for day, items in sorted(by_day.items()):
        items.sort(key=lambda x: x[0])
        own: dict[int, dict] = {}
        work: set[int] = set()
        counts: Counter = Counter()
        projs: list[str] = []
        for loc, r in items:
            idx = loc.hour * 4 + loc.minute // BUCKET_MIN
            if r["mode"] == "work":
                work.add(idx)
                counts["work"] += 1
                continue
            counts[r["mode"]] += 1
            b = own.setdefault(idx, {"label": "other", "projects": Counter()})
            if _rank(r["mode"]) > _rank(b["label"]):
                b["label"] = r["mode"]
            b["projects"][r["project"]] += 1
            projs.append(r["project"])
        for b in own.values():
            b["owner"] = b["projects"].most_common(1)[0][0]
        label_h = {
            m: sum(1 for b in own.values() if b["label"] == m) / 4 for m in LABELS
        }
        union = set(own) | work
        spent = sum(1.0 if i in work else w[own[i]["label"]] for i in union)
        blocks = _blocks(own, work, es)
        own_h = len(own) / 4
        switches = sum(1 for a, b in zip(projs, projs[1:], strict=False) if a != b)
        routine = sum(1 for b in own.values() if b["label"] in es["routine_labels"])
        longest, run, prev = 0, 0, None
        for i in sorted(own):
            same = (
                prev is not None
                and i == prev + 1
                and own[i]["owner"] == own[prev]["owner"]
            )
            run = run + 1 if same else 1
            longest, prev = max(longest, run), i
        days[day] = {
            "own_h": own_h,
            "work_h": len(work) / 4,
            "overlap_h": len(set(own) & work) / 4,
            "total_h": len(union) / 4,
            "label_h": label_h,
            "prompts": dict(counts),
            "spent_h": round(spent / 4, 3),
            "blocks": len(blocks),
            "blocks_h": sum(blocks) / 4,
            "longest_creative_h": max(blocks, default=0) / 4,
            "routine_pct": round(100 * routine / len(own)) if own else 0,
            "projects": len(set(projs)),
            "switches": switches,
            "switches_per_active_hour": round(switches / own_h, 1) if own_h else 0,
            "longest_block_h": longest / 4,
            "night_h": sum(1 for i in union if i < 24) / 4,
            "first": items[0][0].strftime("%H:%M"),
            "last": items[-1][0].strftime("%H:%M"),
        }
    return days


def _rank(label: str) -> int:
    return {
        "task": 6,
        "think": 5,
        "steer": 4,
        "decide": 3,
        "watch": 2,
        "kick": 1,
        "other": 0,
    }.get(label, 0)


def _last(today: date, n: int = 7) -> list[str]:
    return [(today - timedelta(days=i)).isoformat() for i in range(n - 1, -1, -1)]


def budget(days: dict[str, dict], today: date, es: dict) -> dict:
    cap = es["blocks_per_day"]
    prev7 = [(today - timedelta(days=i)).isoformat() for i in range(1, 8)]
    debt = sum(max(0, days.get(d, {}).get("blocks", 0) - cap) for d in prev7)
    suggested = round(2 * (cap - min(cap / 2, debt / 4))) / 2
    week = _last(today)
    return {
        "blocks_per_day": cap,
        "blocks_week": sum(days.get(d, {}).get("blocks", 0) for d in week),
        "blocks_week_capacity": cap * 7,
        "over_capacity_days": [
            d for d in week if days.get(d, {}).get("blocks", 0) > cap
        ],
        "debt_blocks": debt,
        "suggested_blocks_today": suggested,
        "blocks_today": days.get(today.isoformat(), {}).get("blocks", 0),
        "week_spent_h": round(
            sum(days.get(d, {}).get("spent_h", 0.0) for d in week), 2
        ),
    }


def summary(days: dict[str, dict], today: date) -> dict:
    wk = [days[d] | {"date": d} for d in _last(today) if d in days]
    own_h = sum(r["own_h"] for r in wk)
    routine = sum(r["routine_pct"] * r["own_h"] for r in wk)
    sw = sum(r["switches"] for r in wk)
    longest = max(wk, key=lambda r: r["longest_creative_h"], default=None)
    return {
        "hours_week": {
            k: sum(r[k] for r in wk)
            for k in ("own_h", "work_h", "overlap_h", "total_h")
        },
        "label_hours_week": {m: sum(r["label_h"][m] for r in wk) for m in LABELS},
        "longest_creative_block": {
            "h": longest["longest_creative_h"],
            "date": longest["date"],
        }
        if longest and longest["longest_creative_h"]
        else None,
        "routine_pct_week": round(routine / own_h) if own_h else 0,
        "switches_per_active_hour_week": round(sw / own_h, 1) if own_h else 0,
        "switches_per_day": round(sw / len(wk), 1) if wk else 0,
        "days_over_50_switches": [r["date"] for r in wk if r["switches"] > 50],
        "parallel_days_over_2h": [r["date"] for r in wk if r["overlap_h"] > 2],
    }


def history(days: dict[str, dict], es: dict) -> list[dict]:
    """One row per ISO week since the first covered day: hours, hours per label, blocks, place. Travel days are marked."""
    tdays = travel_days(es["timezones"])
    weeks: dict[str, dict] = {}
    for day, v in sorted(days.items()):
        d = date.fromisoformat(day)
        y, wn, _ = d.isocalendar()
        w = weeks.setdefault(
            f"{y}-W{wn:02d}",
            {
                "from": day,
                "own_h": 0.0,
                "work_h": 0.0,
                "total_h": 0.0,
                "label_h": Counter(),
                "blocks": 0,
                "places": Counter(),
                "travel_days": [],
            },
        )
        w["own_h"] += v["own_h"]
        w["work_h"] += v["work_h"]
        w["total_h"] += v["total_h"]
        w["blocks"] += v["blocks"]
        w["label_h"].update(v["label_h"])
        noon = datetime(d.year, d.month, d.day, 12, tzinfo=timezone.utc)
        w["places"][rule_at(noon, es["timezones"]).get("place", "?")] += 1
        if day in tdays:
            w["travel_days"].append(day)
    return [
        {"week": k, **v, "label_h": dict(v["label_h"]), "places": dict(v["places"])}
        for k, v in weeks.items()
    ]


def compute(cfg: dict, rows: list[dict], today: date) -> dict:
    es = settings(cfg)
    days = per_day(rows, es)
    out = {
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "timezones": es["timezones"],
        **budget(days, today, es),
        **summary(days, today),
        "days": days,
        "history": history(days, es),
        "not_measured": es["not_measured"],
    }
    out["today"] = days.get(today.isoformat())
    before = today - timedelta(days=7)
    out["previous"] = {
        "blocks_week": budget(days, before, es)["blocks_week"],
        "routine_pct_week": summary(days, before)["routine_pct_week"],
    }
    return out
