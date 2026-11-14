"""Energy seams: 15-minute buckets, the timezone switch, modes, the debt rule."""

import importlib.util
import json
import sys
from datetime import date, datetime, timezone
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "me", Path(__file__).resolve().parent.parent / "scripts" / "mirror_energy.py"
)
me = importlib.util.module_from_spec(spec)
sys.modules["me"] = me
spec.loader.exec_module(me)

ES = {
    **me.DEFAULTS,
    "timezones": [
        {"tz": "America/Chicago", "until": "2026-11-07"},
        {"tz": "Europe/Istanbul"},
    ],
}


def utc(s):
    return datetime.fromisoformat(s).replace(tzinfo=timezone.utc)


def test_active_hours_count_distinct_quarter_hour_buckets():
    ps = [
        (utc("2026-11-10T08:00:00"), "a", 10),
        (utc("2026-11-10T08:14:59"), "a", 10),  # one bucket
        (utc("2026-11-10T08:15:00"), "a", 10),
        (utc("2026-11-10T09:40:00"), "a", 10),
    ]
    d = me.per_day(ps, ES)["2026-11-10"]
    assert d["active_h"] == 0.75 and d["prompts"]["kick"] == 4


def test_timezone_switch_moves_a_late_prompt_to_the_next_local_day():
    ps = [(utc("2026-11-07T23:30:00"), "a", 10), (utc("2026-11-08T23:30:00"), "a", 10)]
    days = me.per_day(ps, ES)
    # 7.11 23:30 UTC is still Chicago (until inclusive) = 17:30 on 7.11; 8.11 23:30 UTC is Istanbul = 02:30 on 9.11
    assert (
        sorted(days) == ["2026-11-07", "2026-11-09"]
        and days["2026-11-09"]["night_h"] == 0.25
    )


def test_bucket_takes_highest_mode_and_spent_weights_kick_by_half():
    ps = [
        (utc("2026-11-10T08:00:00"), "a", 10),
        (utc("2026-11-10T08:05:00"), "a", 300),  # task bucket
        (utc("2026-11-10T09:00:00"), "a", 60),
        (utc("2026-11-10T10:00:00"), "a", 5),
    ]
    d = me.per_day(ps, ES)["2026-11-10"]
    assert (
        d["mode_h"] == {"task": 0.25, "steer": 0.25, "kick": 0.25}
        and d["spent_h"] == 0.25 + 0.25 + 0.125
    )


def test_switches_and_longest_block_on_one_project():
    ps = [
        (utc(f"2026-11-10T08:{m:02d}:00"), p, 10)
        for m, p in ((0, "a"), (15, "a"), (30, "a"), (45, "b"))
    ] + [(utc("2026-11-10T09:00:00"), "a", 10)]
    d = me.per_day(ps, ES)["2026-11-10"]
    assert d["switches"] == 2 and d["longest_block_h"] == 0.75 and d["projects"] == 2


def test_injected_blocks_are_not_typed_text():
    assert me.typed_length("<system-reminder>long long long</system-reminder>\nhi") == 2
    assert me.typed_length("<teammate-message>x</teammate-message>") == 0


def test_debt_and_suggestion_after_heavy_days():
    days = {f"2026-11-{d:02d}": {"spent_h": 12.0} for d in (8, 9, 10, 11)} | {
        "2026-11-12": {"spent_h": 3.0}
    }
    b = me.budget(days, date(2026, 11, 14), me.DEFAULTS)
    assert b["debt"] == 32.0 and b["suggested_today"] == 2.0  # floor at budget/2
    assert b["overload_days"] == [
        "2026-11-08",
        "2026-11-09",
        "2026-11-10",
        "2026-11-11",
    ]
    calm = me.budget({"2026-11-13": {"spent_h": 8.0}}, date(2026, 11, 14), me.DEFAULTS)
    assert calm["debt"] == 4.0 and calm["suggested_today"] == 3.0  # 4 - min(2, 1)
    assert me.budget({}, date(2026, 11, 14), me.DEFAULTS)["suggested_today"] == 4.0


def test_read_typed_skips_excluded_dirs_and_automation(tmp_path):
    def sess(dirname, lines):
        d = tmp_path / dirname
        d.mkdir()
        (d / "s.jsonl").write_text(
            "\n".join(json.dumps(x, separators=(",", ":")) for x in lines)
        )

    def u(t, ts):
        return {"type": "user", "timestamp": ts, "cwd": "/w", "message": {"content": t}}

    sess("-w", [u("fix the thing please", "2026-11-10T08:00:00Z")])
    sess("-personal", [u("private", "2026-11-10T08:00:00Z")])
    sess(
        "-job",
        [
            u("PERMISSIONS: this run", "2026-11-10T08:00:00Z"),
            u("more", "2026-11-10T08:30:00Z"),
        ],
    )
    cfg = {
        "sessions": {
            "dir": str(tmp_path),
            "exclude_dir_substrings": ["personal"],
            "automation_regex": "^PERMISSIONS",
        }
    }
    got = me.read_typed(cfg, lambda cwd: "proj", utc("2026-11-01T00:00:00"))
    assert [(p, n) for _, p, n in got] == [("proj", 20)]
