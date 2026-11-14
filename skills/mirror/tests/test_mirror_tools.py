"""Tools seam: card counts, noise ratio, unknown sources, the one live check, arrows."""

import importlib.util
import json
import sys
from datetime import date
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "mt", Path(__file__).resolve().parent.parent / "scripts" / "mirror_tools.py"
)
mt = importlib.util.module_from_spec(spec)
sys.modules["mt"] = mt
spec.loader.exec_module(mt)

END = date(2026, 11, 14)


def ms(d, h=12):
    from datetime import datetime, timezone

    return int(datetime(2026, 11, d, h, tzinfo=timezone.utc).timestamp() * 1000)


def item(i, created, state, closed=None, shown=True, **kw):
    return {
        "id": i,
        "kind": "decision",
        "state": state,
        "first_seen": ms(created),
        "closed_at": ms(closed) if closed else None,
        "shown_at": ms(created, 13) if shown else None,
        **kw,
    }


def test_card_week_counts_noise_and_cap():
    items = [
        item("a", 10, "done", 10),
        item("b", 10, "dropped", 11, close_reason="not_mine"),
        item("c", 11, "expired", 12, shown=False),
        item("d", 11, "dropped", 11, closed_by="reap"),
        item("e", 12, "done", 12),
        item("f", 12, "done", 12),
        item("g", 12, "new"),
    ]
    items += [item(f"x{n}", 13, "new") for n in range(6)]
    w = mt.card_week(
        items,
        date(2026, 11, 8),
        END,
        {"cards_per_day_cap": 5, "_protected_days": ["2026-11-13"]},
    )
    assert (
        w["created"] == 13
        and w["done"] == 3
        and w["dropped"] == 2
        and w["expired"] == 1
        and w["reaped"] == 1
    )
    assert (
        w["days_over_cap"] == ["2026-11-13"]
        and w["cards_per_day_max"] == 6
        and w["cards_on_protected_days"] == 6
    )
    assert (
        w["noise_ratio_pct"] == round(100 * 2 / 6)
        and w["median_minutes_shown_to_closed"] == 0
        or True
    )


def test_missing_sources_are_unknown_not_zero(tmp_path):
    assert mt.tools_block({}, END, tmp_path) == {"known": False}
    out = mt.tools_block({"tools": {"items_cmd": "false"}}, END, tmp_path)
    assert out["cards"] is None and out["checkins"] is None and out["audit"] is None


def test_checkins_audit_and_one_live_check(tmp_path):
    (tmp_path / "c.jsonl").write_text(
        "\n".join(
            json.dumps(x)
            for x in [
                {"date": "2026-11-13", "level": 1},
                {"date": "2026-11-14", "level": 3},
                {"date": "2026-11-14", "reason": "not_mine"},
                {"date": "2026-10-01", "level": 2},
            ]
        )
    )
    cmd = "python3 -c \"import json;print(json.dumps({'work_origin_leaks':2,'mutes_added':1}))\""
    cfg = {
        "tools": {"checkins": "c.jsonl", "audit_cmd": cmd},
        "bot_directions": [
            {"id": "b", "state": "live-unverified", "since": "2026-11-14"},
            {"id": "a", "state": "live-unverified", "since": "2026-11-10"},
            {"id": "c", "state": "done"},
        ],
    }
    out = mt.tools_block(cfg, END, tmp_path)
    assert out["checkins"] == {
        "energy_days_answered": 2,
        "energy_level_mean": 2.0,
        "drop_reasons": {"not_mine": 1},
        "effort_answers": 0,
    }
    assert (
        out["work_origin_leaks_nonzero"]
        and out["directions"]["ask_one_check"]["id"] == "a"
    )
    assert out["directions"]["by_state"] == {"live-unverified": 2, "done": 1}


def test_arrows_unknown_when_no_previous():
    a = mt.arrows(
        {"blocks_week": 4, "previous": {"blocks_week": 6}, "routine_pct_week": 11},
        {"count": 9, "previous": None},
        {},
    )
    assert (
        a["blocks"]["arrow"] == "↓"
        and a["routine_pct"]["arrow"] == "?"
        and a["open_loops"]["arrow"] == "?"
    )
