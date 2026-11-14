import json
import shutil
import sys
import zipfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import kindle as k  # noqa: E402

needs_pandoc = pytest.mark.skipif(not shutil.which("pandoc"), reason="pandoc missing")
RU = (
    "# Глава\n\nПривет, мир: ёжик и щука. Съешь же ещё этих мягких французских булок.\n"
)


@pytest.fixture(autouse=True)
def env(tmp_path, monkeypatch):
    monkeypatch.setenv("KINDLE_STATE_DIR", str(tmp_path / "state"))
    monkeypatch.setenv("KINDLE_WORK", str(tmp_path / "work"))
    monkeypatch.delenv("KINDLE_CONFIG", raising=False)


def cfg(tmp_path, enabled=True, address="reader_ab12cd@kindle.com", cap=10):
    p = tmp_path / "cfg.yaml"
    p.write_text(
        f"sender: {{command: gws-xx, from: s@example.com}}\nlimits: {{daily_cap: {cap}}}\n"
        f"recipients:\n  a: {{address: '{address}', enabled: {str(enabled).lower()}}}\n",
        encoding="utf-8",
    )
    return str(p)


@needs_pandoc
def test_convert_cyrillic_md(tmp_path, capsys):
    src = tmp_path / "ru.md"
    src.write_text(RU, encoding="utf-8")
    assert k.main(["convert", str(src), "--title", "Книга", "--author", "Автор"]) == 0
    rep = json.loads(capsys.readouterr().out)
    assert (
        rep["lang"] == "ru"
        and rep["title"] == "Книга"
        and rep["author"] == "Автор"
        and rep["has_toc"]
    )
    with zipfile.ZipFile(rep["output"]) as z:
        assert "мягких" in "".join(
            z.read(n).decode() for n in z.namelist() if n.endswith("xhtml")
        )


@needs_pandoc
def test_convert_fb2(tmp_path, capsys):
    fb2 = tmp_path / "b.fb2"
    fb2.write_text(
        '<?xml version="1.0" encoding="utf-8"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
        "<description><title-info><genre>prose</genre><author><first-name>Лев</first-name><last-name>Толстой</last-name></author>"
        "<book-title>Детство</book-title><lang>ru</lang></title-info></description>"
        "<body><section><title><p>Глава 1</p></title><p>Текст главы.</p></section></body></FictionBook>",
        encoding="utf-8",
    )
    assert k.main(["convert", str(fb2)]) == 0
    rep = json.loads(capsys.readouterr().out)
    assert rep["title"] == "Детство" and rep["lang"] == "ru"


@needs_pandoc
def test_convert_txt_escapes_markdown(tmp_path, capsys):
    t = tmp_path / "a.txt"
    t.write_text(
        "Line one\nwrapped * not italic *\n\nSecond <b> para\n", encoding="utf-8"
    )
    assert k.main(["convert", str(t), "--lang", "en"]) == 0
    rep = json.loads(capsys.readouterr().out)
    with zipfile.ZipFile(rep["output"]) as z:
        text = "".join(z.read(n).decode() for n in z.namelist() if n.endswith("xhtml"))
    assert "* not italic *" in text and "&lt;b&gt;" in text


def test_convert_pdf_passthrough(tmp_path, capsys):
    pdf = tmp_path / "x.pdf"
    pdf.write_bytes(b"%PDF-1.4 fake")
    assert k.main(["convert", str(pdf), "--out", str(tmp_path / "o")]) == 0
    assert (tmp_path / "o" / "x.pdf").read_bytes() == b"%PDF-1.4 fake"


@needs_pandoc
def test_make_three_chapters(tmp_path, capsys):
    d = tmp_path / "book"
    d.mkdir()
    (d / "book.yaml").write_text(
        "title: Роман\nauthor: Автор\nlang: ru\n", encoding="utf-8"
    )
    for i, name in enumerate(["01-one", "02-two", "03-three"], 1):
        (d / f"{name}.md").write_text(f"# Часть {i}\n\nТекст {i}.\n", encoding="utf-8")
    assert k.main(["make", str(d)]) == 0
    rep = json.loads(capsys.readouterr().out)
    assert rep["chapters"] == 3 and rep["title"] == "Роман" and not rep["problems"]
    with zipfile.ZipFile(rep["output"]) as z:
        assert sum(n.endswith(".xhtml") and "ch0" in n for n in z.namelist()) >= 3


def test_send_dry_run(tmp_path, capsys):
    f = tmp_path / "b.epub"
    f.write_bytes(b"x" * 100)
    assert (
        k.main(["send", str(f), "--to", "a", "--dry-run", "--config", cfg(tmp_path)])
        == 0
    )
    out = json.loads(capsys.readouterr().out)
    assert (
        out["dry_run"]
        and out["to"] == "reader_ab12cd@kindle.com"
        and out["bytes"] == 100
    )
    assert not (tmp_path / "state" / "sends.jsonl").exists()


def test_send_refuses_disabled_unknown_placeholder(tmp_path):
    f = tmp_path / "b.epub"
    f.write_bytes(b"x")
    assert (
        k.main(
            [
                "send",
                str(f),
                "--to",
                "a",
                "--dry-run",
                "--config",
                cfg(tmp_path, enabled=False),
            ]
        )
        == k.EXIT_CONFIG
    )
    assert (
        k.main(["send", str(f), "--to", "zzz", "--dry-run", "--config", cfg(tmp_path)])
        == k.EXIT_CONFIG
    )
    assert (
        k.main(
            [
                "send",
                str(f),
                "--to",
                "a",
                "--dry-run",
                "--config",
                cfg(tmp_path, address="FILL_ME"),
            ]
        )
        == k.EXIT_CONFIG
    )


def test_send_refuses_type_and_size(tmp_path, monkeypatch):
    c = cfg(tmp_path)
    m = tmp_path / "b.mobi"
    m.write_bytes(b"x")
    assert (
        k.main(["send", str(m), "--to", "a", "--dry-run", "--config", c])
        == k.EXIT_REFUSED
    )
    big = tmp_path / "big.epub"
    big.write_bytes(b"x" * 1024)
    monkeypatch.setitem(k.SENDER_MAX_MB, "gws", 0)
    assert (
        k.main(["send", str(big), "--to", "a", "--dry-run", "--config", c])
        == k.EXIT_REFUSED
    )


def test_send_idempotent_cap_and_again(tmp_path, monkeypatch):
    c = cfg(tmp_path, cap=2)
    calls = []
    monkeypatch.setattr(k, "deliver_gws", lambda w, m, wd: calls.append(1))
    files = []
    for i in range(3):
        f = tmp_path / f"b{i}.epub"
        f.write_bytes(bytes([i]) * 10)
        files.append(f)
    assert k.main(["send", str(files[0]), "--to", "a", "--config", c]) == 0
    assert k.main(["send", str(files[0]), "--to", "a", "--config", c]) == k.EXIT_DUP
    assert k.main(["send", str(files[0]), "--to", "a", "--again", "--config", c]) == 0
    assert k.main(["send", str(files[1]), "--to", "a", "--config", c]) == k.EXIT_CAP
    assert len(calls) == 2
    rows = [
        json.loads(x)
        for x in (tmp_path / "state" / "sends.jsonl").read_text().splitlines()
    ]
    assert [r["result"] for r in rows] == ["sent", "sent"] and len(
        rows[0]["sha256"]
    ) == 64


def test_send_failure_is_logged(tmp_path, monkeypatch):
    def boom(*a):
        raise k.KindleError("nope", k.EXIT_SEND)

    monkeypatch.setattr(k, "deliver_gws", boom)
    f = tmp_path / "b.epub"
    f.write_bytes(b"x")
    assert (
        k.main(["send", str(f), "--to", "a", "--config", cfg(tmp_path)]) == k.EXIT_SEND
    )
    row = json.loads((tmp_path / "state" / "sends.jsonl").read_text())
    assert row["result"].startswith("failed")


def test_parse_gutendex():
    d = {
        "results": [
            {
                "id": 1,
                "title": "T",
                "authors": [{"name": "A"}],
                "languages": ["en"],
                "copyright": False,
                "formats": {
                    "application/epub+zip": "http://x/1.epub",
                    "text/plain; charset=utf-8": "http://x/1.txt",
                },
            },
            {"id": 2, "title": "NoFiles", "formats": {}},
        ]
    }
    r = k.parse_gutendex(d)
    assert (
        len(r) == 1 and r[0]["url"].endswith(".epub") and r[0]["source"] == "gutenberg"
    )


OPDS = """<feed xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/"><entry><id>https://se/x</id>
<title>Demons</title><author><name>F. D.</name></author><dc:language>en-GB</dc:language><rights>Public domain in the United States. More.</rights>
<link href="https://se/k.kepub.epub" rel="http://opds-spec.org/acquisition/open-access" type="application/kepub+zip"/>
<link href="https://se/a.epub" title="Advanced epub" rel="http://opds-spec.org/acquisition/open-access" type="application/epub+zip"/>
<link href="https://se/r.epub" title="Recommended compatible epub" rel="http://opds-spec.org/acquisition/open-access" type="application/epub+zip"/></entry></feed>"""


def test_parse_opds():
    r = k.parse_opds(OPDS)
    assert (
        r[0]["url"] == "https://se/r.epub"
        and r[0]["license"] == "Public domain in the United States"
    )


def test_parse_archive_and_wikisource():
    a = k.parse_archive(
        {
            "response": {
                "docs": [
                    {
                        "identifier": "id1",
                        "title": "T",
                        "creator": ["X"],
                        "language": "eng",
                        "licenseurl": "https://creativecommons.org/publicdomain/mark/1.0/",
                    }
                ]
            }
        }
    )
    assert a[0]["url"] == "archive:id1"
    w = k.parse_wikisource(
        {"query": {"search": [{"title": "Шинель (Гоголь)"}, {"title": "ТСД2/Шинель"}]}},
        "ru",
    )
    assert len(w) == 1 and "format=epub&lang=ru" in w[0]["url"]


def test_epub_check_rejects_non_epub(tmp_path):
    z = tmp_path / "bad.epub"
    with zipfile.ZipFile(z, "w") as f:
        f.writestr("a.txt", "x")
    with pytest.raises(k.KindleError):
        k.epub_info(z)
