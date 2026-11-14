"""Energy seams: buckets, the timezone timeline, label rank, creative blocks, work overlap, the debt rule, travel days."""

import importlib.util
import sys
from datetime import date
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "me", Path(__file__).resolve().parent.parent / "scripts" / "mirror_energy.py"
)
me = importlib.util.module_from_spec(spec)
sys.modules["me"] = me
spec.loader.exec_module(me)

TZ = [
    {"tz": "Europe/Istanbul", "place": "Turkey"},
    {"from": "2026-09-16T14:00:00Z", "tz": "America/Chicago", "place": "US"},
    {"from": "2026-11-08T14:55:00Z", "tz": "Europe/Istanbul", "place": "Turkey"},
]
ES = {**me.DEFAULTS, "timezones": TZ}


def r(ts, mode="task", project="a"):
    return {"ts": ts + "+00:00", "mode": mode, "project": project}


def q(h, m, **kw):  # a prompt at UTC h:m on 10 Nov
    return r(f"2026-11-10T{h:02d}:{m:02d}:00", **kw)


def test_timeline_picks_the_rule_in_force_and_moves_the_local_day():
    # 23:30 UTC on 9.10: Istanbul (+3) is already 10.10 02:30; Chicago (-5) after 16.09 is 9.10 18:30
    assert me.rule_at(me.parse_ts("2026-09-10T23:30:00+00:00"), TZ)["place"] == "Turkey"
    d = me.per_day([r("2026-09-10T23:30:00"), r("2026-10-10T23:30:00")], ES)
    assert sorted(d) == ["2026-09-11", "2026-10-10"] and d["2026-10-10"]["night_h"] == 0


def test_buckets_label_rank_and_hours():
    rows = [
        q(8, 0, mode="kick"),
        q(8, 14, mode="think"),
        q(8, 15, mode="decide"),
        q(9, 40, mode="watch"),
    ]
    d = me.per_day(rows, ES)["2026-11-10"]  # Istanbul +3
    assert (
        d["own_h"] == 0.75
        and d["label_h"]["think"] == 0.25
        and d["label_h"]["decide"] == 0.25
        and d["label_h"]["watch"] == 0.25
    )
    assert d["routine_pct"] == 67


def test_creative_block_needs_45_minutes_one_project_and_no_interrupt():
    ok = [q(8, 0), q(8, 15, mode="think"), q(8, 30, mode="steer")]
    assert me.per_day(ok, ES)["2026-11-10"]["blocks"] == 1
    assert me.per_day(ok[:2], ES)["2026-11-10"]["blocks"] == 0  # 30 min only
    other_project = [q(8, 0), q(8, 15), q(8, 30, project="b")]
    assert me.per_day(other_project, ES)["2026-11-10"]["blocks"] == 0
    routine_inside = [q(8, 0), q(8, 15, mode="kick"), q(8, 30)]
    assert me.per_day(routine_inside, ES)["2026-11-10"]["blocks"] == 0
    gap = [q(8, 0), q(8, 30), q(9, 0)]  # one silent bucket tolerated
    assert me.per_day(gap, ES)["2026-11-10"]["blocks"] == 1
    far = [q(8, 0), q(9, 0), q(10, 0)]
    assert me.per_day(far, ES)["2026-11-10"]["blocks"] == 0
    with_work = ok + [
        {"ts": "2026-11-10T08:15:00+00:00", "mode": "work", "project": "work"}
    ]  # work in the same bucket as the middle prompt
    assert me.per_day(with_work, ES)["2026-11-10"]["blocks"] == 0


def test_work_overlap_counts_once_and_work_bucket_is_full_weight():
    rows = [
        q(5, 0, mode="kick"),
        {"ts": "2026-11-10T05:00:00+00:00", "mode": "work", "project": "work"},
        {"ts": "2026-11-10T06:00:00+00:00", "mode": "work", "project": "work"},
    ]
    d = me.per_day(rows, ES)["2026-11-10"]
    assert (d["own_h"], d["work_h"], d["overlap_h"], d["total_h"]) == (
        0.25,
        0.5,
        0.25,
        0.5,
    ) and d["spent_h"] == 0.5


def test_debt_in_blocks_lowers_the_suggestion():
    days = {f"2026-11-{x:02d}": {"blocks": 6, "spent_h": 0} for x in (8, 9, 10, 11)}
    b = me.budget(days, date(2026, 11, 14), ES)
    assert (
        b["debt_blocks"] == 12 and b["suggested_blocks_today"] == 1.5
    )  # 3 - min(1.5, 3)
    assert (
        me.budget({"2026-11-13": {"blocks": 5}}, date(2026, 11, 14), ES)[
            "suggested_blocks_today"
        ]
        == 2.5
    )  # debt 2 -> 3 - 0.5
    assert me.budget({}, date(2026, 11, 14), ES)["suggested_blocks_today"] == 3


def test_history_marks_travel_days_and_places():
    es = {**ES}
    days = me.per_day([r("2026-09-17T12:00:00"), r("2026-11-09T09:00:00")], es)
    h = {w["week"]: w for w in me.history(days, es)}
    assert h["2026-W38"]["places"] == {"US": 1} and h["2026-W46"]["places"] == {
        "Turkey": 1
    }
    assert "2026-11-08" in me.travel_days(TZ) and "2026-09-17" in me.travel_days(TZ)
