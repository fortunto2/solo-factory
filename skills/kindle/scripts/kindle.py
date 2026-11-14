#!/usr/bin/env -S uv run --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6", "trafilatura>=2", "pillow>=10", "certifi"]
# ///
"""kindle: convert, make, send and find books for Kindle.

  kindle.py convert <file|url> [--title --author --lang --cover --out]
  kindle.py make <outline.md|folder> [--title --author --lang --cover --out]
  kindle.py check <file.epub>
  kindle.py send <file> --to <slug> [--dry-run] [--again] [--config PATH]
  kindle.py find <query> [--source ...] [--lang ru] | find --get N

Exit codes: 0 ok, 1 error, 2 config/recipient, 3 file refused, 4 duplicate,
5 daily cap, 6 send failed.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import shutil
import smtplib
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from datetime import datetime, timedelta
from email.message import EmailMessage
from pathlib import Path

UA = "solo-kindle-skill/1.0 (open-source; polite, one request per second)"
# Source: Amazon help pages, read 2026-11-14 (see references/amazon-limits.md).
AMAZON_MAIL_MAX_MB = 50
SEND_TYPES = {
    ".pdf",
    ".doc",
    ".docx",
    ".txt",
    ".rtf",
    ".htm",
    ".html",
    ".png",
    ".gif",
    ".jpg",
    ".jpeg",
    ".bmp",
    ".epub",
}
# Gmail's own send limit is 25 MB per message; base64 adds a third, so ~18 MB of file.
SENDER_MAX_MB = {"gws": 18, "smtp": AMAZON_MAIL_MAX_MB}
EXIT_OK, EXIT_ERR, EXIT_CONFIG, EXIT_REFUSED, EXIT_DUP, EXIT_CAP, EXIT_SEND = (
    0,
    1,
    2,
    3,
    4,
    5,
    6,
)

CSS = """body { line-height: 1.4; margin: 0 4%; hyphens: auto; -webkit-hyphens: auto; }
p { margin: 0; text-indent: 1.2em; text-align: justify; }
h1, h2, h3 { text-align: left; hyphens: none; page-break-after: avoid; }
h1 { page-break-before: always; margin-top: 2em; }
img { max-width: 100%; height: auto; }
blockquote { margin: 1em 1.5em; font-style: italic; }
"""


class KindleError(Exception):
    def __init__(self, msg: str, code: int = EXIT_ERR):
        super().__init__(msg)
        self.code = code


# ---------------------------------------------------------------- paths


def state_dir() -> Path:
    return Path(
        os.environ.get("KINDLE_STATE_DIR") or Path.home() / ".config" / "kindle"
    )


def config_path(arg: str | None) -> Path:
    return Path(
        arg or os.environ.get("KINDLE_CONFIG") or state_dir() / "config.yaml"
    ).expanduser()


def load_config(arg: str | None, required: bool = True) -> dict:
    import yaml

    p = config_path(arg)
    if not p.exists():
        if required:
            raise KindleError(
                f"no config at {p} (set KINDLE_CONFIG or --config; example in references/config.example.yaml)",
                EXIT_CONFIG,
            )
        return {}
    return yaml.safe_load(p.read_text(encoding="utf-8")) or {}


def work_dir(cfg: dict | None = None) -> Path:
    raw = (
        os.environ.get("KINDLE_WORK")
        or (cfg or {}).get("work_dir")
        or Path.home() / ".cache" / "kindle"
    )
    p = Path(raw).expanduser()
    p.mkdir(parents=True, exist_ok=True)
    return p


def slugify(text: str) -> str:
    s = re.sub(r"[^\w\-]+", "-", text.strip().lower(), flags=re.UNICODE).strip("-")
    return s[:60] or "book"


# ---------------------------------------------------------------- convert


def guess_lang(text: str) -> str:
    letters = [c for c in text[:5000] if c.isalpha()]
    if not letters:
        return "en"
    cyr = sum("Ѐ" <= c <= "ӿ" for c in letters)
    return "ru" if cyr / len(letters) > 0.3 else "en"


def fit_image(
    src: Path, dst: Path, greyscale: bool, max_w: int = 1200, max_h: int = 1600
) -> Path:
    """Resize for e-ink (and optionally greyscale); writes a JPEG, or PNG when transparency matters."""
    from PIL import Image

    with Image.open(src) as im:
        im.thumbnail((max_w, max_h))
        if greyscale:
            im = im.convert("L")
        elif im.mode not in ("RGB", "L"):
            im = im.convert("RGB")
        dst = dst.with_suffix(".jpg")
        im.save(dst, "JPEG", quality=85, optimize=True)
    return dst


def pandoc_epub(
    src_text_or_file: Path,
    fmt: str,
    out: Path,
    meta: dict,
    cover: Path | None,
    wd: Path,
    extra: list[str] | None = None,
) -> None:
    if not shutil.which("pandoc"):
        raise KindleError("pandoc not found (brew install pandoc)", EXIT_ERR)
    css = wd / "kindle.css"
    css.write_text(CSS, encoding="utf-8")
    cmd = [
        "pandoc",
        str(src_text_or_file),
        "-f",
        fmt,
        "-t",
        "epub3",
        "-o",
        str(out),
        "--toc",
        "--toc-depth=2",
        "--split-level=1",
        f"--css={css}",
        "--standalone",
        "--resource-path",
        f"{src_text_or_file.parent}:{wd}",
    ]
    for k, v in meta.items():
        if v:
            cmd += ["--metadata", f"{k}={v}"]
    if cover:
        cmd += ["--epub-cover-image", str(cover)]
    cmd += extra or []
    r = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if r.returncode != 0:
        raise KindleError(f"pandoc failed: {r.stderr.strip()[:400]}")


def epub_info(path: Path) -> dict:
    """Open the EPUB as a zip, find the OPF, return title/author/lang/size. Raises on a broken book."""
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        if not names or names[0] != "mimetype":
            raise KindleError("epub: first entry is not 'mimetype'", EXIT_REFUSED)
        container = ET.fromstring(z.read("META-INF/container.xml"))
        opf_path = next(
            e.get("full-path") for e in container.iter() if e.tag.endswith("rootfile")
        )
        opf = ET.fromstring(z.read(opf_path))
    ns = "{http://purl.org/dc/elements/1.1/}"

    def first(tag: str) -> str:
        e = opf.find(f".//{ns}{tag}")
        return (e.text or "").strip() if e is not None else ""

    has_toc = any(
        n.endswith(("nav.xhtml", "toc.ncx")) or "nav" in n.lower() for n in names
    )
    return {
        "title": first("title"),
        "author": first("creator"),
        "lang": first("language"),
        "opf": opf_path,
        "bytes": path.stat().st_size,
        "has_toc": has_toc,
        "entries": len(names),
    }


def check_epub(path: Path, limit_mb: int = SENDER_MAX_MB["gws"]) -> dict:
    info = epub_info(path)
    problems = [f"missing {k}" for k in ("title", "lang") if not info[k]]
    if not info["has_toc"]:
        problems.append("no table of contents")
    if info["bytes"] > limit_mb * 1024 * 1024:
        problems.append(f"larger than {limit_mb} MB")
    info["problems"] = problems
    return info


def fetch_url_as_md(url: str, wd: Path) -> tuple[Path, dict]:
    import trafilatura

    downloaded = trafilatura.fetch_url(url)
    if not downloaded:
        raise KindleError(f"could not fetch {url}")
    md = trafilatura.extract(
        downloaded,
        output_format="markdown",
        include_formatting=True,
        include_links=False,
    )
    if not md:
        raise KindleError("no article text found at that URL")
    meta = trafilatura.extract_metadata(downloaded)
    info = {
        "title": getattr(meta, "title", None),
        "author": getattr(meta, "author", None),
        "lang": None,
    }
    note = f"\n\n---\n\nSource: {url}\n"
    p = wd / f"{slugify(info['title'] or urllib.parse.urlparse(url).netloc)}.md"
    p.write_text(f"# {info['title'] or url}\n\n{md}{note}", encoding="utf-8")
    return p, info


def txt_to_html(src: Path, wd: Path, title: str) -> Path:
    """Hard-wrapped plain text (Gutenberg style): blank line = paragraph, single newline = space. Escaped, never read as markdown."""
    raw = src.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")
    paras = [" ".join(p.split()) for p in re.split(r"\n\s*\n", raw) if p.strip()]
    body = "\n".join(f"<p>{html.escape(p)}</p>" for p in paras)
    out = wd / f"{src.stem}.html"
    out.write_text(
        f"<!doctype html><html><head><meta charset='utf-8'><title>{html.escape(title)}</title></head><body><h1>{html.escape(title)}</h1>\n{body}</body></html>",
        encoding="utf-8",
    )
    return out


def cmd_convert(a: argparse.Namespace) -> int:
    wd = work_dir(load_config(a.config, required=False))
    src_arg = a.input
    info: dict = {}
    if re.match(r"https?://", src_arg):
        src, info = fetch_url_as_md(src_arg, wd)
    else:
        src = Path(src_arg).expanduser()
        if not src.exists():
            raise KindleError(f"no such file: {src}", EXIT_CONFIG)
    ext = src.suffix.lower()
    out_dir = Path(a.out).expanduser() if a.out else wd
    out_dir.mkdir(parents=True, exist_ok=True)
    if ext == ".pdf":
        dst = out_dir / src.name
        if dst.resolve() != src.resolve():
            shutil.copy2(src, dst)
        print(
            json.dumps(
                {
                    "output": str(dst),
                    "note": "PDF passes through unchanged; Kindle shows it fixed-layout, reflow is poor. Convert from the source text if you have it.",
                },
                ensure_ascii=False,
            )
        )
        return EXIT_OK
    fmts = {
        ".md": "markdown",
        ".markdown": "markdown",
        ".html": "html",
        ".htm": "html",
        ".docx": "docx",
        ".fb2": "fb2",
        ".epub": "epub",
    }
    sample = (
        src.read_text(encoding="utf-8", errors="replace")[:5000]
        if ext in (".md", ".markdown", ".txt", ".html", ".htm", ".fb2")
        else ""
    )
    title = a.title or info.get("title") or src.stem.replace("_", " ")
    if ext == ".txt":
        src, fmt = txt_to_html(src, wd, title), "html"
    elif ext in fmts:
        fmt = fmts[ext]
    elif shutil.which("ebook-convert") and ext in (
        ".mobi",
        ".azw3",
        ".azw",
        ".djvu",
        ".rtf",
        ".lit",
    ):
        dst = out_dir / (src.stem + ".epub")
        subprocess.run(
            ["ebook-convert", str(src), str(dst)], check=True, capture_output=True
        )
        print(json.dumps(check_epub(dst), ensure_ascii=False))
        return EXIT_OK
    else:
        raise KindleError(
            f"unsupported input {ext or src.name}: md txt html docx fb2 epub pdf or a URL (mobi/azw3/djvu need Calibre's ebook-convert)",
            EXIT_REFUSED,
        )
    meta = {
        "title": a.title or info.get("title")
        if (a.title or info.get("title") or ext == ".txt")
        else None,
        "author": a.author or info.get("author"),
        "lang": a.lang or info.get("lang"),
    }
    if fmt == "fb2" and not meta["lang"]:  # pandoc's fb2 reader drops <lang>
        m = re.search(r"<lang>\s*([a-zA-Z-]+)\s*</lang>", sample)
        meta["lang"] = m.group(1) if m else guess_lang(sample)
    elif (
        fmt in ("markdown", "html")
        and not meta["lang"]
        and not re.search(r"^lang:", sample, re.M)
    ):
        meta["lang"] = guess_lang(sample)
    if ext == ".txt":
        meta["title"] = title
    cover = (
        fit_image(Path(a.cover).expanduser(), wd / "cover", greyscale=False)
        if a.cover
        else None
    )
    dst = out_dir / (slugify(a.title or src.stem) + ".epub")
    pandoc_epub(src, fmt, dst, meta, cover, wd)
    rep = check_epub(dst)
    print(json.dumps({"output": str(dst), **rep}, ensure_ascii=False))
    return EXIT_OK if not rep["problems"] else EXIT_ERR


# ---------------------------------------------------------------- make


def chapter_files(src: Path) -> list[Path]:
    if src.is_dir():
        files = sorted(
            p
            for p in src.iterdir()
            if p.suffix.lower() in (".md", ".markdown")
            and p.stem.lower() not in ("book", "meta")
        )
        if not files:
            raise KindleError(f"no .md chapter files in {src}", EXIT_CONFIG)
        return files
    return [src]


def read_book_meta(src: Path) -> dict:
    import yaml

    for name in ("book.yaml", "book.yml", "meta.yaml"):
        p = (src if src.is_dir() else src.parent) / name
        if p.exists():
            return yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    return {}


IMG_RE = re.compile(r"(!\[[^\]]*\]\()([^)\s]+)((?:\s+\"[^\"]*\")?\))")


def localise_images(
    text: str, base: Path, wd: Path, counter: list[int], greyscale: bool
) -> str:
    def sub(m: re.Match) -> str:
        ref = m.group(2)
        if re.match(r"[a-z]+://", ref):
            return m.group(0)
        p = (base / ref).expanduser()
        if not p.exists():
            raise KindleError(f"image not found: {ref} (in {base})", EXIT_CONFIG)
        counter[0] += 1
        img_dir = wd / "img"
        img_dir.mkdir(exist_ok=True)
        out = fit_image(p, img_dir / f"i{counter[0]:03d}", greyscale)
        return f"{m.group(1)}img/{out.name}{m.group(3)}"

    return IMG_RE.sub(sub, text)


def cmd_make(a: argparse.Namespace) -> int:
    src = Path(a.input).expanduser()
    if not src.exists():
        raise KindleError(f"no such path: {src}", EXIT_CONFIG)
    wd = (
        work_dir(load_config(a.config, required=False))
        / f"make-{slugify(src.stem if src.is_file() else src.name)}"
    )
    if wd.exists():
        shutil.rmtree(wd)
    wd.mkdir(parents=True)
    book = read_book_meta(src)
    parts, counter = [], [0]
    for f in chapter_files(src):
        text = f.read_text(encoding="utf-8")
        if not re.search(r"^# ", text, flags=re.M):
            text = f"# {f.stem.split('-', 1)[-1].replace('-', ' ').replace('_', ' ').strip().capitalize()}\n\n{text}"
        parts.append(
            localise_images(text, f.parent, wd, counter, greyscale=not a.color)
        )
    body = "\n\n".join(parts)
    # A leading YAML block in a single-file outline is pandoc metadata already; keep it.
    title = a.title or book.get("title") or (src.stem if src.is_file() else src.name)
    meta = {
        "title": title,
        "author": a.author or book.get("author"),
        "lang": a.lang or book.get("lang") or guess_lang(body),
        "date": book.get("date") or datetime.now().strftime("%Y-%m-%d"),
        "publisher": book.get("publisher"),
    }
    has_front = body.lstrip().startswith("---")
    md = wd / "book.md"
    md.write_text(body, encoding="utf-8")
    cover_arg = a.cover or book.get("cover")
    if cover_arg and not Path(cover_arg).is_absolute() and src.is_dir():
        cover_arg = str(src / cover_arg)
    cover = (
        fit_image(
            Path(cover_arg).expanduser(),
            wd / "cover",
            greyscale=False,
            max_w=1600,
            max_h=2400,
        )
        if cover_arg
        else None
    )
    out_dir = Path(a.out).expanduser() if a.out else work_dir()
    out_dir.mkdir(parents=True, exist_ok=True)
    dst = out_dir / (slugify(title) + ".epub")
    pandoc_epub(md, "markdown" if not has_front else "markdown", dst, meta, cover, wd)
    rep = check_epub(dst)
    rep["chapters"] = len(parts)
    rep["images"] = counter[0]
    print(json.dumps({"output": str(dst), **rep}, ensure_ascii=False))
    return EXIT_OK if not rep["problems"] else EXIT_ERR


def cmd_check(a: argparse.Namespace) -> int:
    rep = check_epub(Path(a.file).expanduser(), limit_mb=AMAZON_MAIL_MAX_MB)
    print(json.dumps(rep, ensure_ascii=False))
    return EXIT_OK if not rep["problems"] else EXIT_ERR


# ---------------------------------------------------------------- send


def sha256_of(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_log() -> list[dict]:
    p = state_dir() / "sends.jsonl"
    if not p.exists():
        return []
    rows = []
    for line in p.read_text(encoding="utf-8").splitlines():
        try:
            rows.append(json.loads(line))
        except ValueError:
            continue
    return rows


def append_log(row: dict) -> None:
    d = state_dir()
    d.mkdir(parents=True, exist_ok=True)
    with (d / "sends.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def sent_rows(slug: str, within: timedelta, now: datetime) -> list[dict]:
    out = []
    for r in read_log():
        if r.get("slug") != slug or r.get("result") != "sent":
            continue
        try:
            t = datetime.fromisoformat(r["time"])
        except (KeyError, ValueError):
            continue
        if now - t <= within:
            out.append(r)
    return out


def build_message(to: str, sender_from: str, path: Path) -> EmailMessage:
    import mimetypes

    msg = EmailMessage()
    msg["To"] = to
    if sender_from:
        msg["From"] = sender_from
    msg["Subject"] = ""  # Amazon: "You don't need to include a subject line."
    msg.set_content("")
    mt, _ = mimetypes.guess_type(path.name)
    main, _, sub = (mt or "application/octet-stream").partition("/")
    msg.add_attachment(
        path.read_bytes(), maintype=main, subtype=sub, filename=path.name
    )
    return msg


def deliver_gws(wrapper: str, msg: EmailMessage, wd: Path) -> None:
    if wrapper not in ("gws-rs", "gws-sd") and not re.fullmatch(
        r"gws-[a-z0-9]+", wrapper
    ):
        raise KindleError(
            f"sender wrapper {wrapper!r} is not a gws-style wrapper name", EXIT_CONFIG
        )
    if not shutil.which(wrapper):
        raise KindleError(f"{wrapper} not on PATH", EXIT_SEND)
    eml = Path(tempfile.mkstemp(suffix=".eml", dir=wd)[1])
    try:
        eml.write_bytes(bytes(msg))
        r = subprocess.run(
            [
                wrapper,
                "gmail",
                "users",
                "messages",
                "send",
                "--params",
                json.dumps({"userId": "me"}),
                "--upload",
                eml.name,
                "--upload-content-type",
                "message/rfc822",
            ],
            capture_output=True,
            text=True,
            timeout=300,
            check=False,
            cwd=wd,  # gws only uploads files under its cwd
        )
    finally:
        eml.unlink(missing_ok=True)
    if r.returncode != 0:
        raise KindleError(
            f"{wrapper} rc={r.returncode}: {(r.stderr or r.stdout).strip()[:300]}",
            EXIT_SEND,
        )


def deliver_smtp(msg: EmailMessage) -> None:
    host, user = os.environ.get("KINDLE_SMTP_HOST"), os.environ.get("KINDLE_SMTP_USER")
    pw = os.environ.get("KINDLE_SMTP_PASS")
    if not (host and user and pw):
        raise KindleError(
            "smtp needs KINDLE_SMTP_HOST, KINDLE_SMTP_USER, KINDLE_SMTP_PASS (KINDLE_SMTP_PORT optional, default 465)",
            EXIT_CONFIG,
        )
    port = int(os.environ.get("KINDLE_SMTP_PORT", "465"))
    if "From" not in msg:
        msg["From"] = os.environ.get("KINDLE_SMTP_FROM", user)
    try:
        if port == 465:
            with smtplib.SMTP_SSL(host, port, timeout=60) as s:
                s.login(user, pw)
                s.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=60) as s:
                s.starttls()
                s.login(user, pw)
                s.send_message(msg)
    except (OSError, smtplib.SMTPException) as e:
        raise KindleError(f"smtp: {e}", EXIT_SEND) from e


def resolve_recipient(cfg: dict, slug: str) -> dict:
    rec = (cfg.get("recipients") or {}).get(slug)
    if rec is None:
        raise KindleError(f"unknown recipient {slug!r}", EXIT_CONFIG)
    if not rec.get("enabled"):
        raise KindleError(f"recipient {slug!r} is disabled", EXIT_CONFIG)
    addr = (rec.get("address") or "").strip()
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", addr) or addr == "FILL_ME":
        raise KindleError(
            f"recipient {slug!r} has no valid address in the config", EXIT_CONFIG
        )
    sender = rec.get("sender") or (cfg.get("sender") or {}).get("command") or "smtp"
    return {
        "address": addr,
        "sender": sender,
        "from": rec.get("from") or (cfg.get("sender") or {}).get("from") or "",
    }


def cmd_send(a: argparse.Namespace) -> int:
    cfg = load_config(a.config)
    path = Path(a.file).expanduser()
    if not path.is_file():
        raise KindleError(f"no such file: {path}", EXIT_CONFIG)
    rec = resolve_recipient(cfg, a.to)
    ext = path.suffix.lower()
    if ext not in SEND_TYPES:
        hint = (
            " (run `convert` first)" if ext in (".fb2", ".md", ".mobi", ".azw3") else ""
        )
        raise KindleError(
            f"{ext or path.name} is not accepted by Send to Kindle{hint}", EXIT_REFUSED
        )
    kind = "smtp" if rec["sender"] == "smtp" else "gws"
    limit = min(
        AMAZON_MAIL_MAX_MB,
        SENDER_MAX_MB[kind],
        int((cfg.get("limits") or {}).get("max_mb", AMAZON_MAIL_MAX_MB)),
    )
    size = path.stat().st_size
    if size > limit * 1024 * 1024:
        raise KindleError(
            f"{path.name} is {size / 1048576:.1f} MB, over the {limit} MB limit for {rec['sender']}",
            EXIT_REFUSED,
        )
    digest, now = sha256_of(path), datetime.now()
    cap = int((cfg.get("limits") or {}).get("daily_cap", 10))
    if not a.again and any(
        r.get("sha256") == digest for r in sent_rows(a.to, timedelta(hours=24), now)
    ):
        raise KindleError(
            f"already sent to {a.to} within 24 h (use --again to resend)", EXIT_DUP
        )
    if len(sent_rows(a.to, timedelta(hours=24), now)) >= cap:
        raise KindleError(f"daily cap of {cap} reached for {a.to}", EXIT_CAP)
    summary = {
        "to": rec["address"],
        "from": rec["from"] or f"(account of {rec['sender']})",
        "via": rec["sender"],
        "file": path.name,
        "bytes": size,
        "sha256": digest[:16],
    }
    if a.dry_run:
        print(json.dumps({"dry_run": True, **summary}, ensure_ascii=False))
        return EXIT_OK
    msg = build_message(rec["address"], rec["from"], path)
    row = {
        "time": now.isoformat(timespec="seconds"),
        "slug": a.to,
        "file": path.name,
        "bytes": size,
        "sha256": digest,
    }
    try:
        deliver_smtp(msg) if kind == "smtp" else deliver_gws(
            rec["sender"], msg, work_dir(cfg)
        )
    except KindleError as e:
        append_log({**row, "result": f"failed: {e}"[:200]})
        raise
    append_log({**row, "result": "sent"})
    print(json.dumps({"sent": True, **summary}, ensure_ascii=False))
    return EXIT_OK


# ---------------------------------------------------------------- find


def http_get(url: str, binary: bool = False, timeout: int = 90):
    time.sleep(1.0)  # one request per second, always
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    import ssl

    import certifi

    ctx = ssl.create_default_context(
        cafile=os.environ.get("SSL_CERT_FILE") or certifi.where()
    )
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
                data = r.read()
            break
        except urllib.error.HTTPError as e:
            if attempt == 2 or e.code < 500:
                raise
            time.sleep(3)
    return data if binary else data.decode("utf-8", "replace")


def parse_gutendex(d: dict) -> list[dict]:
    out = []
    for b in d.get("results", []):
        fm = b.get("formats", {})
        epub = next((fm[k] for k in fm if k.startswith("application/epub+zip")), None)
        txt = next((fm[k] for k in fm if k.startswith("text/plain")), None)
        link = epub or txt
        if not link:
            continue
        out.append(
            {
                "title": b.get("title", ""),
                "author": "; ".join(x["name"] for x in b.get("authors", []))
                or "unknown",
                "lang": ",".join(b.get("languages", [])),
                "source": "gutenberg",
                "license": "Public domain in the USA (Project Gutenberg)"
                if not b.get("copyright")
                else "check copyright",
                "url": link,
                "page": f"https://www.gutenberg.org/ebooks/{b.get('id')}",
            }
        )
    return out


def parse_opds(xml_text: str) -> list[dict]:
    ns = {"a": "http://www.w3.org/2005/Atom", "dc": "http://purl.org/dc/elements/1.1/"}
    root = ET.fromstring(xml_text)
    out = []
    for e in root.findall("a:entry", ns):
        links = e.findall("a:link", ns)
        epub = [
            x
            for x in links
            if x.get("type") == "application/epub+zip"
            and "open-access" in (x.get("rel") or "")
        ]
        best = next(
            (x for x in epub if (x.get("title") or "").startswith("Recommended")),
            epub[0] if epub else None,
        )
        if best is None:
            continue
        out.append(
            {
                "title": (e.findtext("a:title", "", ns) or "").strip(),
                "author": (
                    e.findtext("a:author/a:name", "unknown", ns) or "unknown"
                ).strip(),
                "lang": (e.findtext("dc:language", "", ns) or "").strip(),
                "source": "standardebooks",
                "license": (
                    (e.findtext("a:rights", "", ns) or "public domain (US)")
                    .strip()
                    .split(". ")[0]
                ),
                "url": best.get("href"),
                "page": e.findtext("a:id", "", ns),
            }
        )
    return out


def parse_archive(d: dict) -> list[dict]:
    out = []
    for x in d.get("response", {}).get("docs", []):
        creator = x.get("creator", "unknown")
        lang = x.get("language", "")
        out.append(
            {
                "title": x.get("title", ""),
                "author": "; ".join(creator) if isinstance(creator, list) else creator,
                "lang": "; ".join(lang) if isinstance(lang, list) else lang,
                "source": "archive",
                "license": f"marked public domain: {x.get('licenseurl', '')}",
                "url": f"archive:{x['identifier']}",
                "page": f"https://archive.org/details/{x['identifier']}",
            }
        )
    return out


def parse_wikisource(d: dict, lang: str) -> list[dict]:
    hits = d.get("query", {}).get("search", [])
    main = [h for h in hits if "/" not in h["title"]] or hits
    return [
        {
            "title": h["title"],
            "author": "see page",
            "lang": lang,
            "source": f"wikisource-{lang}",
            "license": "Wikisource text, public domain per page (verify on the page)",
            "url": f"https://ws-export.wmcloud.org/?format=epub&lang={lang}&page={urllib.parse.quote(h['title'].replace(' ', '_'))}",
            "page": f"https://{lang}.wikisource.org/wiki/{urllib.parse.quote(h['title'].replace(' ', '_'))}",
        }
        for h in main
    ]


def search_gutenberg(q: str, lang: str | None) -> list[dict]:
    url = "https://gutendex.com/books/?" + urllib.parse.urlencode(
        {"search": q, **({"languages": lang} if lang else {})}
    )
    return parse_gutendex(json.loads(http_get(url)))


def search_standardebooks(q: str, lang: str | None) -> list[dict]:
    if lang and lang != "en":
        return []
    return parse_opds(
        http_get(
            "https://standardebooks.org/feeds/opds/all?"
            + urllib.parse.urlencode({"query": q})
        )
    )


def search_archive(q: str, lang: str | None) -> list[dict]:
    clean = re.sub(r'["\\()]', " ", q)
    query = f"({clean}) AND mediatype:texts AND licenseurl:*publicdomain*" + (
        f" AND language:{lang}" if lang else ""
    )
    url = "https://archive.org/advancedsearch.php?" + urllib.parse.urlencode(
        [
            ("q", query),
            ("fl[]", "identifier"),
            ("fl[]", "title"),
            ("fl[]", "creator"),
            ("fl[]", "language"),
            ("fl[]", "licenseurl"),
            ("rows", "8"),
            ("output", "json"),
        ]
    )
    return parse_archive(json.loads(http_get(url)))


def search_wikisource(q: str, lang: str | None) -> list[dict]:
    wl = lang or ("ru" if guess_lang(q) == "ru" else "en")
    url = f"https://{wl}.wikisource.org/w/api.php?" + urllib.parse.urlencode(
        {
            "action": "query",
            "list": "search",
            "srsearch": f"intitle:{q}",
            "srnamespace": 0,
            "srlimit": 8,
            "format": "json",
        }
    )
    res = parse_wikisource(json.loads(http_get(url)), wl)
    if not res:
        url = url.replace("intitle%3A", "")
        res = parse_wikisource(json.loads(http_get(url)), wl)
    return res


SOURCES = {
    "gutenberg": search_gutenberg,
    "standardebooks": search_standardebooks,
    "archive": search_archive,
    "wikisource": search_wikisource,
}


def archive_best_file(identifier: str) -> tuple[str, str]:
    meta = json.loads(http_get(f"https://archive.org/metadata/{identifier}"))
    files = [f["name"] for f in meta.get("files", [])]
    for suffix in (".epub", "_djvu.txt", ".pdf"):
        name = next((n for n in files if n.endswith(suffix) and "_bw" not in n), None)
        if name:
            return (
                f"https://archive.org/download/{identifier}/{urllib.parse.quote(name)}",
                Path(name).suffix,
            )
    raise KindleError(f"no epub/txt/pdf in archive item {identifier}")


def cmd_find(a: argparse.Namespace) -> int:
    wd = work_dir(load_config(a.config, required=False))
    cache = wd / "last-find.json"
    if a.get is not None:
        results = (
            json.loads(cache.read_text(encoding="utf-8")) if cache.exists() else []
        )
        if not 1 <= a.get <= len(results):
            raise KindleError(
                f"--get {a.get}: no such result (last find has {len(results)})",
                EXIT_CONFIG,
            )
        r = results[a.get - 1]
        url = r["url"]
        ext = ".epub"
        if url.startswith("archive:"):
            url, ext = archive_best_file(url.split(":", 1)[1])
        elif (
            r["source"] == "gutenberg"
            and not url.endswith(".epub")
            and "epub" not in url
        ):
            ext = ".txt"
        dst = wd / (slugify(r["title"]) + ext)
        dst.write_bytes(http_get(url, binary=True, timeout=120))
        print(
            json.dumps(
                {
                    "saved": str(dst),
                    "bytes": dst.stat().st_size,
                    "title": r["title"],
                    "author": r["author"],
                    "license": r["license"],
                },
                ensure_ascii=False,
            )
        )
        return EXIT_OK
    if not a.query:
        raise KindleError("find needs a query or --get N", EXIT_CONFIG)
    results: list[dict] = []
    errors: list[str] = []
    for name in a.source.split(",") if a.source else SOURCES:
        if name not in SOURCES:
            raise KindleError(
                f"unknown source {name!r}; choose from {', '.join(SOURCES)}",
                EXIT_CONFIG,
            )
        try:
            results += SOURCES[name](a.query, a.lang)[: a.limit]
        except Exception as e:  # one dead catalog must not hide the others
            errors.append(f"{name}: {e}")
    cache.write_text(
        json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    for i, r in enumerate(results, 1):
        print(
            f"{i:>2}. {r['title']} - {r['author']} [{r['lang']}] ({r['source']})\n    {r['license']}\n    {r['page']}"
        )
    for e in errors:
        print(f"! {e}", file=sys.stderr)
    if not results:
        print(
            "nothing found in the free catalogs. Own the file? Pass it to convert. Otherwise buy it in the Kindle store."
        )
    return EXIT_OK if results or not errors else EXIT_ERR


# ---------------------------------------------------------------- cli


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="kindle",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp: argparse.ArgumentParser) -> None:
        sp.add_argument(
            "--config",
            help="config path (else KINDLE_CONFIG, else ~/.config/kindle/config.yaml)",
        )

    def book_opts(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("--title")
        sp.add_argument("--author")
        sp.add_argument(
            "--lang", help="BCP-47 code, e.g. ru, en (guessed from the text if omitted)"
        )
        sp.add_argument("--cover", help="cover image path")
        sp.add_argument("--out", help="output directory (default: work dir)")

    c = sub.add_parser("convert", help="file or URL -> Kindle-ready EPUB")
    c.add_argument("input")
    book_opts(c)
    common(c)
    c.set_defaults(fn=cmd_convert)
    m = sub.add_parser("make", help="chapters (folder or one md) -> EPUB")
    m.add_argument("input")
    book_opts(m)
    m.add_argument(
        "--color",
        action="store_true",
        help="keep images in colour (default: greyscale for e-ink)",
    )
    common(m)
    m.set_defaults(fn=cmd_make)
    k = sub.add_parser("check", help="validate an EPUB")
    k.add_argument("file")
    k.set_defaults(fn=cmd_check)
    s = sub.add_parser(
        "send", help="e-mail a file to a recipient's Send-to-Kindle address"
    )
    s.add_argument("file")
    s.add_argument("--to", required=True, help="recipient slug from the config")
    s.add_argument("--dry-run", action="store_true")
    s.add_argument(
        "--again",
        action="store_true",
        help="resend a file already sent in the last 24 h",
    )
    common(s)
    s.set_defaults(fn=cmd_send)
    f = sub.add_parser("find", help="search legal free catalogs")
    f.add_argument("query", nargs="?")
    f.add_argument(
        "--get", type=int, metavar="N", help="download result N of the last find"
    )
    f.add_argument("--source", help=f"comma list of {', '.join(SOURCES)}")
    f.add_argument("--lang", help="language code filter, e.g. ru")
    f.add_argument("--limit", type=int, default=5, help="results per source")
    common(f)
    f.set_defaults(fn=cmd_find)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args)
    except KindleError as e:
        print(f"error: {e}", file=sys.stderr)
        return e.code


if __name__ == "__main__":
    sys.exit(main())
