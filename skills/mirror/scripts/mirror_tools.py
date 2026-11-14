"""Do the tools serve the person or load them? Weekly numbers from three generic sources, all read-only.

items_cmd     a command printing JSON: a list of cards the person's assistant or bot put in front of them. Fields used:
              id, kind, state (new|shown|snoozed|done|dropped|expired), first_seen and closed_at (epoch ms or ISO),
              shown_at (null = never shown), closed_by (optional: "reap" when the source died, "user"), close_reason
              (optional: a drop reason such as irrelevant / not_mine / do_not_show).
checkins      a JSONL file, one object per line: {date, level} an energy tap; {date, reason} a drop reason;
              {date, effort_min} an effort answer for an item whose cost was unknown.
audit_cmd     a command printing JSON counters: work_origin_leaks (must be 0), mutes_added, rest_days, protected_days
              (list of dates).
directions    a checklist from the config: [{id, title, sign, state: done|live-unverified|not-started, since}].
              The report asks at most ONE live check per week, the oldest first.

The collector never changes any of these sources. A missing source is reported as unknown, never as zero.
"""

from __future__ import annotations

import json
import shlex
import statistics
import subprocess
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

NOISE_DEFAULT = ("irrelevant", "not_mine", "do_not_show")


def _day(v) -> date | None:
    if v in (None, ""):
        return None
    if isinstance(v, int | float):
        return datetime.fromtimestamp(v / 1000 if v > 1e11 else v, timezone.utc).date()
    try:
        return datetime.fromisoformat(str(v).replace("Z", "+00:00")).date()
    except ValueError:
        return None


def _ms(v) -> float | None:
    if v in (None, ""):
        return None
    if isinstance(v, int | float):
        return float(v if v > 1e11 else v * 1000)
    try:
        return datetime.fromisoformat(str(v).replace("Z", "+00:00")).timestamp() * 1000
    except ValueError:
        return None


def run_json(cmd: str | None, cwd: Path):
    if not cmd:
        return None
    try:
        r = subprocess.run(
            shlex.split(cmd),
            capture_output=True,
            text=True,
            cwd=cwd,
            check=False,
            timeout=90,
        )
        return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out = []
    for line in path.read_text().splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            continue
    return out


def card_week(items: list[dict], start: date, end: date, tc: dict) -> dict:
    """Counts for one week window [start, end]."""
    cap = tc.get("cards_per_day_cap", 5)
    noise_reasons = set(tc.get("noise_reasons", NOISE_DEFAULT))
    protected = set(tc.get("_protected_days", []))
    created = [
        i for i in items if (d := _day(i.get("first_seen"))) and start <= d <= end
    ]
    closed = [i for i in items if (d := _day(i.get("closed_at"))) and start <= d <= end]
    per_day = Counter(
        _day(i["first_seen"]).isoformat()
        for i in created
        if i.get("kind") == "decision"
    )
    mins = [
        (_ms(i["closed_at"]) - _ms(i["shown_at"])) / 60000
        for i in closed
        if _ms(i.get("shown_at"))
        and _ms(i.get("closed_at"))
        and i.get("state") in ("done", "dropped")
    ]
    states = Counter(i.get("state") for i in closed)
    reaped = sum(
        1 for i in closed if i.get("closed_by") == "reap" or i.get("source") == "reap"
    )
    noisy = sum(1 for i in closed if i.get("close_reason") in noise_reasons)
    unseen = sum(
        1 for i in closed if i.get("state") == "expired" and not i.get("shown_at")
    )
    return {
        "created": len(created),
        "done": states["done"],
        "dropped": states["dropped"],
        "expired": states["expired"],
        "reaped": reaped,
        "median_minutes_shown_to_closed": round(statistics.median(mins))
        if mins
        else None,
        "cards_per_day_max": max(per_day.values(), default=0),
        "days_over_cap": sorted(d for d, n in per_day.items() if n > cap),
        "cards_on_protected_days": sum(n for d, n in per_day.items() if d in protected),
        "noise_ratio_pct": round(100 * (noisy + unseen) / len(closed))
        if closed
        else None,
        "noise_counted": {
            "reasons": noisy,
            "expired_unseen": unseen,
            "closed": len(closed),
        },
    }


def tools_block(cfg: dict, end: date, root: Path) -> dict:
    tc = cfg.get("tools") or {}
    if not tc:
        return {"known": False}
    audit = run_json(tc.get("audit_cmd"), root) or {}
    tc = {**tc, "_protected_days": audit.get("protected_days", [])}
    items = run_json(tc.get("items_cmd"), root)
    w_start, p_end = end - timedelta(days=6), end - timedelta(days=7)
    p_start = end - timedelta(days=13)
    cards = (
        {
            "this_week": card_week(items, w_start, end, tc),
            "previous_week": card_week(items, p_start, p_end, tc),
        }
        if isinstance(items, list)
        else None
    )
    rows = read_jsonl(root / tc["checkins"]) if tc.get("checkins") else []

    def wk(r: dict) -> bool:
        d = _day(r.get("date"))
        return bool(d and w_start <= d <= end)

    taps = [r for r in rows if wk(r) and "level" in r]
    checkins = {
        "energy_days_answered": len({r["date"] for r in taps}),
        "energy_level_mean": round(statistics.mean(r["level"] for r in taps), 1)
        if taps
        else None,
        "drop_reasons": dict(
            Counter(r["reason"] for r in rows if wk(r) and "reason" in r)
        ),
        "effort_answers": sum(1 for r in rows if wk(r) and "effort_min" in r),
    }
    dirs = [d for d in (cfg.get("directions") or cfg.get("bot_directions") or [])]
    unverified = sorted(
        (d for d in dirs if d.get("state") == "live-unverified"),
        key=lambda d: str(d.get("since", "")),
    )
    leak = audit.get("work_origin_leaks")
    return {
        "known": True,
        "cards": cards,
        "checkins": checkins if rows else None,
        "audit": {
            k: audit.get(k) for k in ("work_origin_leaks", "mutes_added", "rest_days")
        }
        if audit
        else None,
        "work_origin_leaks_nonzero": bool(leak),
        "noise_target_pct": tc.get("noise_target_pct"),
        "directions": {
            "by_state": dict(Counter(d.get("state", "not-started") for d in dirs)),
            "items": [
                {k: d.get(k) for k in ("id", "title", "sign", "state")} for d in dirs
            ],
            "ask_one_check": (
                {"id": unverified[0]["id"], "title": unverified[0].get("title", "")}
                if unverified
                else None
            ),
        },
    }


def arrow(now, prev) -> str:
    if now is None or prev is None:
        return "?"
    return "↑" if now > prev else "↓" if now < prev else "="


def arrows(energy: dict, loops: dict, tools: dict) -> dict:
    """Week-over-week arrows for the focus and energy numbers and the tools number they are linked to."""
    prev = energy.get("previous") or {}
    cards = (tools or {}).get("cards") or {}
    return {
        "blocks": {
            "now": energy.get("blocks_week"),
            "prev": prev.get("blocks_week"),
            "arrow": arrow(energy.get("blocks_week"), prev.get("blocks_week")),
        },
        "routine_pct": {
            "now": energy.get("routine_pct_week"),
            "prev": prev.get("routine_pct_week"),
            "arrow": arrow(
                energy.get("routine_pct_week"), prev.get("routine_pct_week")
            ),
        },
        "open_loops": {
            "now": loops.get("count"),
            "prev": loops.get("previous"),
            "arrow": arrow(loops.get("count"), loops.get("previous")),
        },
        "cards_per_day_max": {
            "now": (cards.get("this_week") or {}).get("cards_per_day_max"),
            "prev": (cards.get("previous_week") or {}).get("cards_per_day_max"),
            "arrow": arrow(
                (cards.get("this_week") or {}).get("cards_per_day_max"),
                (cards.get("previous_week") or {}).get("cards_per_day_max"),
            ),
        },
    }
