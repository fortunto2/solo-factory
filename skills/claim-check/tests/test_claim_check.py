import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import claim_check as cc  # noqa: E402

QUOTE = "Eugenol has shown excellent antimicrobial activity in studies"
GOOD = {
    "video": {"id": "abc12345", "title": "t"},
    "claims": [
        {
            "id": "c1",
            "ts": "01:00",
            "text": "kills all microbes",
            "kind": "promise",
            "harm": False,
            "verdict": "не подтверждено",
            "reason": "только в капле",
            "sources": [{"url": "https://example.org/a", "quote": QUOTE}],
        }
    ],
    "message": {
        "true_part": "Вы правы: гвоздика правда пахнет и в ней есть эвгенол.",
        "doesnt_hold": "Капля в стекле не то же самое, что тело.",
        "dont": "",
        "help": "Спросите врача, что подойдёт именно вам.",
        "technique": "Громкий заголовок и страшные слова.",
        "links": [{"name": "Обзор", "url": "https://example.org/a"}],
    },
}


def put_source(root: Path, vid: str, url: str, text: str) -> Path:
    d = root / vid
    d.mkdir(parents=True, exist_ok=True)
    p = cc.source_path(d, url)
    p.parent.mkdir(exist_ok=True)
    p.write_text(f"{url}\n\n{text}")
    return d


@pytest.fixture
def vdir(tmp_path):
    return put_source(
        tmp_path,
        "abc12345",
        "https://example.org/a",
        f"Intro. {QUOTE}, against fungi and bacteria.",
    )


def lint(work, vdir, short=None):
    short = short if short is not None else cc.build_short(work["message"])
    return cc.lint_work(work, short, vdir, [])


def test_youtube_ids():
    assert cc.youtube_id("https://youtu.be/_oNAkmFeCoA") == "_oNAkmFeCoA"
    assert (
        cc.youtube_id("https://www.youtube.com/watch?v=y6pvguItv3w&t=5")
        == "y6pvguItv3w"
    )
    assert cc.youtube_id("https://youtube.com/shorts/abcdefghij") == "abcdefghij"
    assert cc.youtube_id("https://example.org/post") is None
    assert len(cc.item_id("https://example.org/post")) == 11


def test_parse_json3_drops_empty_and_repeats():
    data = {
        "events": [
            {"tStartMs": 0, "segs": [{"utf8": "Привет"}, {"utf8": " мир"}]},
            {"tStartMs": 1500, "segs": [{"utf8": "\n"}]},
            {"tStartMs": 2000, "segs": [{"utf8": "Привет мир"}]},
            {"tStartMs": 3000, "aAppend": 1},
            {"tStartMs": 4200, "segs": [{"utf8": "дальше"}]},
        ]
    }
    assert cc.parse_json3(data) == [
        {"t": 0.0, "text": "Привет мир"},
        {"t": 4.2, "text": "дальше"},
    ]


def test_parse_whisper_txt():
    txt = "[00:05] (ru) Привет\n[01:02:03] (en) Hello\nnoise\n[00:09] (ru)   \n"
    assert cc.parse_whisper_txt(txt) == [
        {"t": 5.0, "text": "Привет"},
        {"t": 3723.0, "text": "Hello"},
    ]


def test_good_work_passes(vdir):
    errors, _ = lint(GOOD, vdir)
    assert errors == []


def test_length_limit(vdir):
    w = json.loads(json.dumps(GOOD))
    w["message"]["doesnt_hold"] = "Очень длинно. " * 100
    errors, _ = lint(w, vdir)
    assert any("limit 900" in e for e in errors)


@pytest.mark.parametrize(
    "bad", ["Это конспирология", "Какой фейк", "полный бред", "ты опять", "Это ложь"]
)
def test_banned_words(vdir, bad):
    w = json.loads(json.dumps(GOOD))
    w["message"]["true_part"] = bad
    errors, _ = lint(w, vdir)
    assert errors


def test_must_start_with_common_ground(vdir):
    w = json.loads(json.dumps(GOOD))
    w["message"]["true_part"] = "Нет, так не работает."
    errors, _ = lint(w, vdir)
    assert any("common ground" in e for e in errors)


def test_dosing_refused(vdir):
    w = json.loads(json.dumps(GOOD))
    w["message"]["help"] = "Пейте 5 мл отвара."
    errors, _ = lint(w, vdir)
    assert any("dosing" in e for e in errors)


def test_harm_requires_dont(vdir):
    w = json.loads(json.dumps(GOOD))
    w["claims"][0]["harm"] = True
    errors, _ = lint(w, vdir)
    assert any("message.dont" in e for e in errors)
    w["message"]["dont"] = "Не заменяйте лекарства отваром."
    assert lint(w, vdir)[0] == []


def test_verdict_needs_fetched_source_and_real_quote(vdir):
    w = json.loads(json.dumps(GOOD))
    w["claims"][0]["sources"] = [
        {"url": "https://example.org/never-fetched", "quote": QUOTE}
    ]
    assert any("not fetched" in e for e in lint(w, vdir)[0])
    w["claims"][0]["sources"] = [
        {
            "url": "https://example.org/a",
            "quote": "A sentence nobody ever wrote on that page",
        }
    ]
    assert any("quote not found" in e for e in lint(w, vdir)[0])
    w["claims"][0]["sources"] = []
    assert any("no source" in e for e in lint(w, vdir)[0])


def test_unverifiable_needs_no_source(vdir):
    w = json.loads(json.dumps(GOOD))
    w["claims"][0].update(verdict="не удалось проверить", sources=[])
    assert lint(w, vdir)[0] == []


def test_verdict_must_be_on_scale(vdir):
    w = json.loads(json.dumps(GOOD))
    w["claims"][0]["verdict"] = "ложь"
    assert any("not in scale" in e for e in lint(w, vdir)[0])


def test_render_and_lint_cli(tmp_path, capsys):
    d = put_source(tmp_path, "abc12345", "https://example.org/a", QUOTE + " in vitro")
    (d / "work.json").write_text(json.dumps(GOOD, ensure_ascii=False))
    assert (
        cc.main(["--config", "/dev/null", "render", "abc12345", "--out", str(tmp_path)])
        == 0
    )
    short = (d / "short.txt").read_text()
    assert len(short.strip()) <= cc.MAX_CHARS
    assert "| не подтверждено |" in (d / "card.md").read_text()
    assert (
        cc.main(["--config", "/dev/null", "lint", "abc12345", "--out", str(tmp_path)])
        == 0
    )
    assert "lint: ok" in capsys.readouterr().out


def test_queue_idempotent_and_run_with_fake_agent(tmp_path, capsys):
    out = ["--out", str(tmp_path)]
    url = "https://youtu.be/abc12345XYZ"
    cfg = ["--config", "/dev/null"]
    assert cc.main([*cfg, "queue", "add", url, "--from", "t", *out]) == 0
    assert cc.main([*cfg, "queue", "add", url, *out]) == 0
    assert len(cc.load_queue(tmp_path)["items"]) == 1
    assert '"existing": true' in capsys.readouterr().out
    # a done item is never run again: pre-seed everything the pipeline needs
    sid = "abc12345XYZ"
    d = put_source(tmp_path, sid, "https://example.org/a", QUOTE + " in vitro")
    (d / "video.json").write_text(json.dumps({"id": sid, "transcript": []}))
    (d / "work.json").write_text(json.dumps(GOOD, ensure_ascii=False))
    assert cc.main([*cfg, "queue", "run", *out]) == 0
    assert cc.load_queue(tmp_path)["items"][sid]["status"] == "done"
    mtime = (d / "short.txt").stat().st_mtime_ns
    assert cc.main([*cfg, "queue", "run", *out]) == 0
    assert (d / "short.txt").stat().st_mtime_ns == mtime
    assert cc.main([*cfg, "queue", "show", sid, *out]) == 0
    assert GOOD["message"]["true_part"] in capsys.readouterr().out


def test_queue_failed_agent_exits_4(tmp_path):
    sid = "zzz00000111"
    d = tmp_path / sid
    d.mkdir()
    (d / "video.json").write_text("{}")
    cfg = ["--config", "/dev/null"]
    out = ["--out", str(tmp_path)]
    cc.main([*cfg, "queue", "add", f"https://youtu.be/{sid}", *out])
    assert cc.main([*cfg, "queue", "run", "--agent-cmd", "true", *out]) == 4
    assert cc.load_queue(tmp_path)["items"][sid]["status"] == "failed"
