"""Seams of the collector: reschedule counting, stale drafts, share per project, the >=3 rule."""

import importlib.util
import json
import sys
from datetime import date
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "mc", Path(__file__).resolve().parent.parent / "scripts" / "mirror_collect.py"
)
mc = importlib.util.module_from_spec(spec)
sys.modules["mc"] = mc
spec.loader.exec_module(mc)

TODAY = date(2026, 11, 14)
CFG = {
    **mc.DEFAULTS,
    "focus": {"projects": ["airq"], "goals": []},
    "project_goal": {"airq": "product", "l2f": "income"},
    "_root": Path("."),
    "goal_priority": ["visa", "income"],
}


def test_reschedule_dates_counts_dated_due_reason_keys_only():
    item = {
        "id": "x",
        "due_reason_a": "4.11 moved",
        "due_reason_b": "10.11 again",
        "due_reason_c": "no date here",
        "note_14": "14.11 snoozed",
        "due_reason_d": "10.11 same day twice",
    }
    assert mc.reschedule_dates(item, ["due_reason"], TODAY) == [
        date(2026, 11, 4),
        date(2026, 11, 10),
    ]


def test_ddmm_year_rolls_back_for_a_date_far_in_the_future():
    assert mc.parse_ddmm("28.12 note", TODAY) == date(2025, 12, 28)
    assert mc.parse_ddmm("17.11 note", TODAY) == date(2026, 11, 17)


def test_three_rule_needs_count_and_number():
    three = mc.Pattern("p", "k", [TODAY] * 3, "3 раза")
    two = mc.Pattern("p", "k", [TODAY] * 2, "2 раза")
    nonum = mc.Pattern("p", "k", [TODAY] * 5, "")
    assert (
        mc.qualifies(three, 3)
        and not mc.qualifies(two, 3)
        and not mc.qualifies(nonum, 3)
    )


def test_stale_drafts_counted_past_the_threshold_only():
    drafts = [
        {"ref": "a", "drafted_at": "2026-11-01T10:00:00+03:00"},
        {"ref": "b", "drafted_at": "2026-11-10T10:00:00+03:00"},
        {"ref": "c", "drafted_at": "2026-10-20"},
    ]
    pats = mc.find_patterns(CFG, TODAY, date(2026, 11, 1), [], [], drafts, [], [], True)
    st = next(x for x in pats if x.id == "stale-drafts")
    assert st.refs == ["a", "c"] and "старейший 25 дн." in st.number


def test_shares_per_project_and_focus():
    sessions = [
        {"project": "airq"},
        {"project": "l2f"},
        {"project": "l2f"},
        {"project": "l2f"},
    ]
    commits = {"airq": [TODAY], "l2f": [TODAY] * 3}
    sh = mc.shares(sessions, commits, CFG)
    assert sh["per_project"]["l2f"]["share_sessions"] == 0.75
    assert sh["share_focus_sessions"] == 0.25 and sh["share_focus_commits"] == 0.25
    assert sh["per_goal"]["income"]["sessions"] == 3


def test_new_project_while_focus_idle_is_a_pattern_only_when_focus_idle():
    npj = [("a", date(2026, 11, 2)), ("b", date(2026, 11, 5)), ("c", date(2026, 11, 9))]
    idle = mc.find_patterns(CFG, TODAY, date(2026, 11, 1), [], [], [], [], npj, False)
    busy = mc.find_patterns(CFG, TODAY, date(2026, 11, 1), [], [], [], [], npj, True)
    assert any(x.id == "new-project-focus-idle" and mc.qualifies(x, 3) for x in idle)
    assert not any(x.id == "new-project-focus-idle" for x in busy)


def test_reschedule_pattern_per_item_qualifies_at_three():
    todos = [
        {"ref": "ops/a", "reschedules": [date(2026, 11, d) for d in (4, 10, 12)]},
        {"ref": "ops/b", "reschedules": [date(2026, 11, 4)]},
    ]
    pats = {
        x.id: x
        for x in mc.find_patterns(
            CFG, TODAY, date(2026, 11, 1), todos, [], [], [], [], True
        )
    }
    assert mc.qualifies(pats["reschedule:ops/a"], 3) and not mc.qualifies(
        pats["reschedule:ops/b"], 3
    )


def test_correction_cluster_counts_distinct_sessions():
    def mk(sid, d, t):
        return {"id": sid, "prompts": [(d, t)]}

    ss = [
        mk("s1", "2026-11-03", "нет, не создавай новый файл отчёта"),
        mk("s2", "2026-11-07", "не создавай новый файл отчёта опять"),
        mk("s3", "2026-11-10", "стоп, не создавай файл отчёта"),
        mk("s4", "2026-11-11", "нет, запусти тесты"),
    ]
    cl = mc.correction_clusters(ss, CFG["correction_regex"])
    top = max(cl, key=lambda c: c["sessions"])
    assert top["sessions"] == 3 and len(top["occ_dates"]) == 3


def test_streak_counts_consecutive_prior_weeks():
    led = [{"type": "pattern", "id": "p", "week": w} for w in ("2026-W44", "2026-W45")]
    assert mc.streak(led, "p", "2026-W46") == 3
    assert mc.streak(led, "p", "2026-W48") == 1
    assert mc.prev_week("2027-W01") == "2026-W53"


def test_judge_experiment_from_same_numbers():
    m = {"share_focus_sessions": 0.4, "sessions": {"airq": 0.4}}
    assert (
        mc.judge({"metric": "share_focus_sessions", "op": ">=", "value": 0.3}, m)[
            "verdict"
        ]
        == "met"
    )
    assert (
        mc.judge({"metric": "sessions.airq", "op": ">=", "value": 0.5}, m)["verdict"]
        == "missed"
    )
    assert (
        mc.judge({"metric": "nope", "op": ">=", "value": 1}, m)["verdict"] == "unknown"
    )


def test_cut_list_flags_goalless_and_silent():
    todos = [
        {
            "ref": "ops/a",
            "title": "t",
            "goal": "?",
            "due": "2026-10-01",
            "reschedules": [],
            "purpose": "",
        },
        {
            "ref": "ops/b",
            "title": "t",
            "goal": "visa",
            "due": "2026-10-01",
            "reschedules": [],
            "purpose": "x",
        },
    ]
    cl = mc.cut_list(todos, [], CFG, TODAY)
    assert [c["ref"] for c in cl] == ["ops/a"] and cl[0]["proposal"] == "drop"


def test_cut_list_never_flags_a_goal_topic_and_does_not_park_until_a_past_date():
    topics = [
        {"ref": "root", "title": "R", "parents": [], "quiet_days": 1, "due": ""},
        {"ref": "orphan", "title": "O", "parents": [], "quiet_days": 1, "due": ""},
    ]
    todos = [
        {
            "ref": "ops/a",
            "title": "t",
            "goal": "root",
            "due": "",
            "reschedules": [],
            "purpose": "x",
        },
        {
            "ref": "ops/b",
            "title": "t",
            "goal": "?",
            "due": "2026-11-14",
            "reschedules": [date(2026, 11, 2)] * 3,
            "purpose": "",
        },
    ]
    cl = {c["ref"]: c for c in mc.cut_list(todos, topics, CFG, TODAY)}
    assert "root" not in cl and "orphan" in cl
    assert cl["ops/b"]["proposal"] == "drop"


def test_lint_limits():
    assert mc.lint("ok", 1800) == []
    assert mc.lint("a — b", 1800) == ["1 em dash(es)"]
    assert "chars" in mc.lint("x" * 1900, 1800)[0]


def test_collect_end_to_end_on_fixture(tmp_path):
    (tmp_path / "tasks" / "open").mkdir(parents=True)
    (tmp_path / "tasks" / "open" / "a.json").write_text(
        json.dumps(
            {
                "id": "goal",
                "title": "Goal",
                "status": "open",
                "parents": [],
                "updated": "2026-11-01",
                "created": "2026-10-01",
                "items": [],
            }
        )
    )
    (tmp_path / "todo.yaml").write_text(
        "g:\n- id: x\n  task: T\n  status: todo\n  due: 2026-11-16\n  purpose: 'goal: because'\n  due_reason_1: '4.11 a'\n"
    )
    (tmp_path / "reg.yaml").write_text("projects: []\n")
    (tmp_path / "mirror.yaml").write_text(
        "root: .\nregistry_dir: tasks\ntodo_lists: [todo.yaml]\nprojects_registry: reg.yaml\n"
        "sessions: {dir: nosuch}\nledger: led.jsonl\ngoal_priority: [goal]\n"
    )
    out = mc.collect(mc.load_config(tmp_path / "mirror.yaml"), TODAY, 14)
    assert out["inputs"]["todo_items"] == 1 and out["week"] == "2026-W46"
    assert out["this_week_candidates"][0]["ref"] == "g/x" or out[
        "this_week_candidates"
    ][0]["ref"].endswith("/x")


def test_lint_counts_observations_not_the_this_week_list():
    ok = "Повторы:\n1. a\n2. b\nЭксперимент прошлой недели: x\nТолько на этой неделе:\n1) a\n2) b\n3) c\n4) d\n"
    assert mc.lint(ok, 1800) == []
    bad = "Повторы:\n1. a\n2. b\n3. c\n4. d\nЭксперимент: x\n"
    assert mc.lint(bad, 1800) == ["more than 3 numbered observations"]
