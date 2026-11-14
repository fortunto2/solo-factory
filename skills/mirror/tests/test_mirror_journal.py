"""Journal seams: cursor, idempotence by uuid, batch parsing, no model call when nothing is new, the work-profile wall."""

import importlib.util
import json
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "mj", Path(__file__).resolve().parent.parent / "scripts" / "mirror_journal.py"
)
mj = importlib.util.module_from_spec(spec)
sys.modules["mj"] = mj
spec.loader.exec_module(mj)

CANARY_TEXT = "CANARY-PROMPT-TEXT-91"
CANARY_DIR = "-Users-x-clients-CANARYCLIENT"


def line(uuid, ts, text, cwd="/w/proj"):
    return (
        json.dumps(
            {
                "type": "user",
                "uuid": uuid,
                "timestamp": ts,
                "cwd": cwd,
                "message": {"content": text},
            },
            separators=(",", ":"),
        )
        + "\n"
    )


class FakeModel:
    def __init__(self):
        self.calls, self.inputs = 0, []

    def __call__(self, prompt):
        self.calls += 1
        self.inputs.append(prompt)
        n = len([x for x in prompt.splitlines() if x[:1].isdigit() and "|" in x[:6]])
        return json.dumps([{"i": i, "m": "task", "c": 0.9} for i in range(1, n + 1)])


def setup(tmp_path, with_work=False):
    own = tmp_path / "own" / "-proj"
    own.mkdir(parents=True)
    cfg = {
        "sessions": {
            "dir": str(tmp_path / "own"),
            "exclude_dir_substrings": ["personal"],
            "automation_regex": "^PERMISSIONS",
        },
        "journal": {
            "path": str(tmp_path / "j.jsonl"),
            "cursor": str(tmp_path / "c.json"),
        },
    }
    if with_work:
        w = tmp_path / "work" / CANARY_DIR
        w.mkdir(parents=True)
        cfg["work_profiles"] = [{"name": "work", "dir": str(tmp_path / "work")}]
    return cfg, own


def run(cfg, model):
    import datetime

    return mj.update(cfg, lambda cwd: "proj", lambda ts: datetime.timezone.utc, model)


def rows(cfg):
    return mj.read_journal(Path(cfg["journal"]["path"]))


def test_nothing_new_costs_no_model_call_and_no_reread(tmp_path):
    cfg, own = setup(tmp_path)
    (own / "s1.jsonl").write_text(
        line("u1", "2026-11-10T08:00:00Z", "сделай новую штуку для меня")
        + line("u2", "2026-11-10T08:20:00Z", "ещё одно задание тут")
    )
    m = FakeModel()
    s1 = run(cfg, m)
    assert s1["new_rows"] == 2 and m.calls == 1
    s2 = run(cfg, m)
    assert s2["files_read"] == 0 and s2["new_rows"] == 0 and m.calls == 1


def test_append_reads_only_new_bytes_and_partial_line_waits(tmp_path):
    cfg, own = setup(tmp_path)
    f = own / "s1.jsonl"
    f.write_text(line("u1", "2026-11-10T08:00:00Z", "first request here"))
    m = FakeModel()
    run(cfg, m)
    with f.open("a") as fh:
        fh.write(
            line("u2", "2026-11-10T09:00:00Z", "second request here")[:30]
        )  # torn line
    assert run(cfg, m)["new_rows"] == 0
    with f.open("a") as fh:
        fh.write(line("u2", "2026-11-10T09:00:00Z", "second request here")[30:])
    assert run(cfg, m)["new_rows"] == 1
    assert [r["uuid"] for r in rows(cfg)] == ["u1", "u2"] and m.calls == 2


def test_truncated_or_rotated_transcript_never_duplicates(tmp_path):
    cfg, own = setup(tmp_path)
    f = own / "s1.jsonl"
    f.write_text(
        line("u1", "2026-11-10T08:00:00Z", "alpha request words")
        + line("u2", "2026-11-10T09:00:00Z", "beta request words")
    )
    m = FakeModel()
    run(cfg, m)
    f.write_text(
        line("u1", "2026-11-10T08:00:00Z", "alpha request words")
    )  # truncated: shorter than the cursor
    run(cfg, m)
    f.write_text(
        line("u9", "2026-11-11T08:00:00Z", "gamma request words")
        + line("u1", "2026-11-10T08:00:00Z", "alpha request words")
    )  # replaced
    run(cfg, m)
    assert sorted(r["uuid"] for r in rows(cfg)) == ["u1", "u2", "u9"]


def test_continue_is_a_rule_and_journal_has_no_text(tmp_path):
    cfg, own = setup(tmp_path)
    (own / "s1.jsonl").write_text(
        line("u1", "2026-11-10T08:00:00Z", "продолжай")
        + line("u2", "2026-11-10T08:05:00Z", "SECRET-WORDS in a long request")
    )
    m = FakeModel()
    run(cfg, m)
    r = {x["uuid"]: x for x in rows(cfg)}
    assert (
        r["u1"]["by"] == "rule"
        and r["u1"]["mode"] == "kick"
        and r["u2"]["by"] == "claude"
    )
    assert (
        "SECRET-WORDS"
        not in Path(cfg["journal"]["path"]).read_text()
        + Path(cfg["journal"]["cursor"]).read_text()
    )


def test_automation_first_prompt_skips_the_whole_transcript(tmp_path):
    cfg, own = setup(tmp_path)
    (own / "s1.jsonl").write_text(
        line("u1", "2026-11-10T08:00:00Z", "PERMISSIONS: sandboxed")
        + line("u2", "2026-11-10T08:05:00Z", "later typed words")
    )
    m = FakeModel()
    assert run(cfg, m)["new_rows"] == 0 and m.calls == 0


def test_parse_labels_is_strict_and_missing_ids_are_asked_again_then_other():
    assert mj.parse_labels(
        'noise [{"i":1,"m":"task","c":0.9},{"i":2,"m":"bogus"},{"i":9,"m":"kick"}] tail',
        2,
    ) == {1: ("task", 0.9)}
    assert mj.parse_labels("not json", 3) == {}
    answers = iter(
        ['[{"i":1,"m":"steer","c":1}]', '[{"i":1,"m":"think","c":0.7}]']
    )  # 2 texts: first call answers #1, retry answers #1 of the leftover
    out = mj.label_texts(
        ["alpha words here", "beta words here"], lambda p: next(answers), workers=1
    )
    assert [o[0] for o in out] == ["steer", "think"] and all(
        o[2] == "claude" for o in out
    )
    assert mj.label_texts(["gamma words here"], lambda p: "[]", workers=1)[0][:2] == (
        "other",
        0.0,
    )


def test_work_profile_is_time_only_and_nothing_leaks(tmp_path, capsys):
    cfg, own = setup(tmp_path, with_work=True)
    (own / "s1.jsonl").write_text(
        line("u1", "2026-11-10T08:00:00Z", "own request with words")
    )
    work = tmp_path / "work" / CANARY_DIR
    (work / "wsess-1.jsonl").write_text(
        line(
            "w1",
            "2026-11-10T08:05:00Z",
            f"{CANARY_TEXT} please",
            cwd=f"/Users/x/clients/{CANARY_DIR}",
        )
        + line("w2", "2026-11-10T08:40:00Z", "more work words")
    )
    m = FakeModel()
    stats = run(cfg, m)
    assert stats["work_rows"] == 2
    out = capsys.readouterr()
    blob = (
        Path(cfg["journal"]["path"]).read_text()
        + Path(cfg["journal"]["cursor"]).read_text()
        + "".join(m.inputs)
        + out.out
        + out.err
        + json.dumps(stats)
    )
    assert (
        CANARY_TEXT not in blob
        and "CANARYCLIENT" not in blob
        and "/Users/x/clients" not in blob
    )
    wr = [r for r in rows(cfg) if r["mode"] == "work"]
    assert [(r["project"], r["by"], r["session"]) for r in wr] == [
        ("work", "none", "")
    ] * 2 and wr[0]["chars"] == len(f"{CANARY_TEXT} please")
