#!/usr/bin/env -S uv run --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6", "trafilatura>=2", "certifi"]
# ///
"""claim-check: the mechanical half of a gentle fact-check of a video or article.

  claim_check.py fetch <url|file|-> [--out DIR] [--config PATH] [--no-whisper]
  claim_check.py source <id> <url> [--out DIR]     # fetch a page as evidence, cached
  claim_check.py render <id> [--out DIR]           # work.json -> short.txt + card.md
  claim_check.py lint <id> [--out DIR]
  claim_check.py queue add <url> [--from LABEL] | run [--max N] | list | show <id>

The reasoning (claims, evidence, wording) is done by the agent following SKILL.md;
this script fetches, stores, renders and refuses output that breaks the rules.

Exit codes: 0 ok, 1 error, 2 lint failed, 3 fetch failed, 4 a queue item failed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import ssl
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import certifi
import yaml

VERDICTS = (
    "верно",
    "частично верно",
    "не подтверждено",
    "неверно",
    "опасно",
    "не удалось проверить",
)
CLAIM_KINDS = ("fact", "promise", "call_to_action", "sale")
MAX_CHARS = 900
BANNED = [
    "конспиролог",
    "конспирологи",
    "фейк",
    "бред",
    "опять",
    "это ложь",
    "глупост",
    "как можно верить",
    "наивн",
    "дурак",
    "дура",
]
FIRST_LINE_BANNED = re.compile(
    r"^\s*(это\s+(ложь|неправда|обман)|нет[,.!]|неправда)", re.I
)
DOSING = re.compile(
    r"\b\d+([.,]\d+)?\s*(мг|мкг|г|мл|капел|капли|таблет|ложк|чайн|столов)", re.I
)
DEFAULTS = {
    "out_dir": "_work/claim-check",
    "audiences": {
        "default": {
            "lang": "ru",
            "address": "вы",
            "call_them": "",
            "style": "Plain words, short sentences, everyday comparisons, no jargon.",
        }
    },
    "audience": "default",
    "banned": [],
    "whisper_script": "",
    "agent_cmd": "claude -p --permission-mode acceptEdits --allowedTools Bash,Read,Write,Edit,WebFetch,WebSearch",
    "agent_timeout_s": 1500,
}


# ---------- config and paths ----------


def load_config(path: str | None) -> dict:
    cfg = json.loads(json.dumps(DEFAULTS))
    p = (
        path
        or os.environ.get("CLAIM_CHECK_CONFIG")
        or ("claim-check.yaml" if Path("claim-check.yaml").exists() else "")
    )
    if p:
        user = yaml.safe_load(Path(p).expanduser().read_text()) or {}
        for k, v in user.items():
            cfg[k] = v
    return cfg


def out_dir(args, cfg) -> Path:
    d = Path(
        getattr(args, "out", None)
        or os.environ.get("CLAIM_CHECK_OUT")
        or cfg["out_dir"]
    ).expanduser()
    d.mkdir(parents=True, exist_ok=True)
    return d


def video_dir(root: Path, vid: str) -> Path:
    if not re.fullmatch(r"[\w.-]{3,64}", vid):
        raise SystemExit(f"bad id: {vid!r}")
    d = root / vid
    d.mkdir(parents=True, exist_ok=True)
    return d


# ---------- ids and transcript parsing ----------


def youtube_id(url: str) -> str | None:
    u = urlparse(url)
    host = (u.hostname or "").removeprefix("www.").removeprefix("m.")
    if host == "youtu.be":
        return u.path.strip("/").split("/")[0] or None
    if host.endswith("youtube.com"):
        if u.path == "/watch":
            return (parse_qs(u.query).get("v") or [None])[0]
        m = re.match(r"/(shorts|embed|live)/([\w-]{6,})", u.path)
        if m:
            return m.group(2)
    return None


def item_id(src: str) -> str:
    return youtube_id(src) or hashlib.sha1(src.encode()).hexdigest()[:11]


def fmt_ts(sec: float) -> str:
    s = int(sec)
    return f"{s // 60:02d}:{s % 60:02d}"


def parse_json3(data: dict) -> list[dict]:
    """YouTube json3 captions -> [{t, text}], one entry per caption event."""
    out: list[dict] = []
    for ev in data.get("events", []):
        segs = ev.get("segs")
        if not segs:
            continue
        text = "".join(s.get("utf8", "") for s in segs).replace("\n", " ").strip()
        text = re.sub(r"\s+", " ", text)
        if text and not (
            out and out[-1]["text"] == text
        ):  # rolling captions repeat lines
            out.append({"t": round(ev.get("tStartMs", 0) / 1000, 1), "text": text})
    return out


def parse_whisper_txt(txt: str) -> list[dict]:
    """transcribe_mlx.py output: `[MM:SS] (lang) text` (hours allowed)."""
    out = []
    for line in txt.splitlines():
        m = re.match(r"\[(?:(\d+):)?(\d+):(\d+)\]\s*(?:\(\w+\)\s*)?(.*)", line)
        if m and m.group(4).strip():
            h, mi, s = int(m.group(1) or 0), int(m.group(2)), int(m.group(3))
            out.append({"t": float(h * 3600 + mi * 60 + s), "text": m.group(4).strip()})
    return out


def transcript_text(segs: list[dict]) -> str:
    return "\n".join(f"[{fmt_ts(s['t'])}] {s['text']}" for s in segs)


# ---------- fetch ----------


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def fetch_youtube(url: str, vid: str, d: Path, cfg: dict, whisper: bool) -> dict:
    meta_p = run(
        ["yt-dlp", "--skip-download", "--dump-single-json", "--no-warnings", url]
    )
    if meta_p.returncode != 0:
        raise RuntimeError(
            f"yt-dlp: {meta_p.stderr.strip().splitlines()[-1] if meta_p.stderr.strip() else 'failed'}"
        )
    m = json.loads(meta_p.stdout)
    rec = {
        "id": vid,
        "url": url,
        "kind": "youtube",
        "title": m.get("title", ""),
        "channel": m.get("channel") or m.get("uploader", ""),
        "duration_s": m.get("duration"),
        "description": (m.get("description") or "")[:2000],
    }
    segs: list[dict] = []
    for f in d.glob("*.json3"):
        f.unlink()
    run(
        [
            "yt-dlp",
            "--skip-download",
            "--write-subs",
            "--write-auto-subs",
            "--sub-langs",
            "ru,en",
            "--sub-format",
            "json3",
            "--no-warnings",
            "-o",
            str(d / "cap"),
            url,
        ]
    )
    caps = sorted(d.glob("cap.*.json3"))
    if caps:
        segs = parse_json3(json.loads(caps[0].read_text()))
        rec["transcript_source"] = f"captions:{caps[0].name.split('.')[1]}"
    if not segs and whisper:
        segs = whisper_audio(url, d, cfg)
        rec["transcript_source"] = "whisper-local"
    if not segs:
        raise RuntimeError("no transcript (no captions, whisper off or failed)")
    rec["transcript"] = segs
    return rec


def whisper_audio(url: str, d: Path, cfg: dict) -> list[dict]:
    script = cfg.get("whisper_script") or ""
    if not script or not Path(script).expanduser().exists():
        return []
    audio = d / "audio.m4a"
    r = run(
        [
            "yt-dlp",
            "-f",
            "bestaudio[ext=m4a]/bestaudio",
            "-o",
            str(audio),
            "--no-warnings",
            url,
        ]
    )
    if r.returncode != 0 or not audio.exists():
        return []
    r = run(
        [
            "uv",
            "run",
            str(Path(script).expanduser()),
            str(audio),
            "--languages",
            "ru",
            "en",
        ]
    )
    txt = audio.with_suffix(".txt")
    segs = parse_whisper_txt(txt.read_text()) if txt.exists() else []
    audio.unlink(missing_ok=True)  # the audio never leaves the machine and is not kept
    return segs


def fetch_page(src: str, sid: str, stdin_text: str = "") -> dict:
    import trafilatura

    if src == "-":
        text, title, kind, url = stdin_text, "(pasted text)", "text", ""
    elif Path(src).expanduser().is_file():
        text, title, kind, url = (
            Path(src).expanduser().read_text(),
            Path(src).name,
            "text",
            "",
        )
    else:
        html = trafilatura.fetch_url(src)
        if not html:
            raise RuntimeError("could not download the page")
        text = trafilatura.extract(html, include_comments=False) or ""
        md = trafilatura.extract_metadata(html)
        title, kind, url = (md.title if md and md.title else src), "article", src
    if len(text.strip()) < 40:
        raise RuntimeError("no readable text")
    paras = [p.strip() for p in re.split(r"\n\s*\n|\n", text) if p.strip()]
    return {
        "id": sid,
        "url": url,
        "kind": kind,
        "title": title,
        "channel": "",
        "duration_s": None,
        "transcript_source": kind,
        "transcript": [{"t": float(i), "text": p} for i, p in enumerate(paras)],
    }


def cmd_fetch(args, cfg) -> int:
    root = out_dir(args, cfg)
    src = args.src
    stdin_text = sys.stdin.read() if src == "-" else ""
    sid = (
        item_id(src)
        if src != "-"
        else hashlib.sha1(stdin_text.encode()).hexdigest()[:11]
    )
    d = video_dir(root, sid)
    try:
        rec = (
            fetch_youtube(src, sid, d, cfg, not args.no_whisper)
            if youtube_id(src)
            else fetch_page(src, sid, stdin_text)
        )
    except (RuntimeError, OSError) as e:
        print(f"fetch failed: {e}", file=sys.stderr)
        return 3
    rec["fetched_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    (d / "video.json").write_text(json.dumps(rec, ensure_ascii=False, indent=1))
    (d / "transcript.txt").write_text(transcript_text(rec["transcript"]))
    print(
        json.dumps(
            {
                "id": sid,
                "dir": str(d),
                "title": rec["title"],
                "channel": rec["channel"],
                "duration_s": rec["duration_s"],
                "segments": len(rec["transcript"]),
                "transcript_source": rec["transcript_source"],
            },
            ensure_ascii=False,
        )
    )
    return 0


# ---------- sources (evidence cache) ----------


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.replace(" ", " ")).strip().lower()


def source_path(d: Path, url: str) -> Path:
    """Evidence cache shared by all videos: <out>/sources/<sha1(url)[:10]>.txt (d = a video dir)."""
    return d.parent / "sources" / (hashlib.sha1(url.encode()).hexdigest()[:10] + ".txt")


def cmd_source(args, cfg) -> int:
    import trafilatura

    d = video_dir(out_dir(args, cfg), args.id)
    m = re.match(r"https?://pubmed\.ncbi\.nlm\.nih\.gov/(\d+)", args.url)
    fetch_url = (
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed"
        f"&id={m.group(1)}&rettype=abstract&retmode=text"
        if m
        else args.url
    )  # PubMed pages are JS-heavy; the abstract text endpoint is exact
    req = urllib.request.Request(
        fetch_url,
        headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15",
            "Accept": "text/html,*/*",
        },
    )
    try:
        raw = (
            urllib.request.urlopen(
                req,
                timeout=30,
                context=ssl.create_default_context(cafile=certifi.where()),
            )
            .read()
            .decode("utf-8", "replace")
        )
    except (OSError, ValueError) as e:
        print(f"source fetch failed: {e}", file=sys.stderr)
        return 3
    text = trafilatura.extract(
        raw, include_comments=False, include_tables=True
    ) or re.sub(r"<[^>]+>", " ", raw)
    if len(text.strip()) < 100:
        print("source has no readable text", file=sys.stderr)
        return 3
    p = source_path(d, args.url)
    p.parent.mkdir(exist_ok=True)
    p.write_text(f"{args.url}\n\n{text}")
    print(json.dumps({"url": args.url, "file": str(p), "chars": len(text)}))
    return 0


# ---------- render ----------


def load_work(d: Path) -> dict:
    p = d / "work.json"
    if not p.exists():
        raise SystemExit(f"{p} missing: the agent writes it (see SKILL.md)")
    return json.loads(p.read_text())


def build_short(msg: dict) -> str:
    parts = [
        msg.get("true_part", ""),
        msg.get("doesnt_hold", ""),
        msg.get("dont", ""),
        msg.get("help", ""),
        msg.get("technique", ""),
    ]
    links = msg.get("links") or []
    if links:
        parts.append(
            "Где прочитать: " + "; ".join(f"{k['name']} {k['url']}" for k in links[:2])
        )
    return "\n\n".join(p.strip() for p in parts if p and p.strip())


def build_card(work: dict, video: dict | None) -> str:
    v = video or work.get("video", {})
    lines = [
        f"# {v.get('title', work.get('video', {}).get('title', ''))}",
        "",
        f"{v.get('channel', '')} · {v.get('url', '')}",
        "",
        "| Время | Утверждение | Вид | Вердикт | Почему | Источник |",
        "|---|---|---|---|---|---|",
    ]
    for c in work.get("claims", []):
        src = "<br>".join(s["url"] for s in c.get("sources", [])) or "нет"
        flag = " (риск)" if c.get("harm") else ""
        cells = [
            str(c.get("ts", "")),
            c.get("text", ""),
            c.get("kind", "") + flag,
            c.get("verdict", ""),
            c.get("reason", ""),
            src,
        ]
        lines.append(
            "| "
            + " | ".join(x.replace("|", "/").replace("\n", " ") for x in cells)
            + " |"
        )
    if work.get("sold"):
        lines += ["", f"Что продаётся: {work['sold']}"]
    return "\n".join(lines) + "\n"


def cmd_render(args, cfg) -> int:
    d = video_dir(out_dir(args, cfg), args.id)
    work = load_work(d)
    video = (
        json.loads((d / "video.json").read_text())
        if (d / "video.json").exists()
        else None
    )
    (d / "short.txt").write_text(build_short(work.get("message", {})) + "\n")
    (d / "card.md").write_text(build_card(work, video))
    print(
        f"wrote {d / 'short.txt'} ({len(build_short(work.get('message', {})))} chars), card.md"
    )
    return 0


# ---------- lint ----------


def lint_work(
    work: dict, short: str, d: Path, extra_banned: list[str]
) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warns: list[str] = []
    if len(short) > MAX_CHARS:
        errors.append(f"short.txt is {len(short)} chars, limit {MAX_CHARS}")
    low = short.lower()
    for w in BANNED + [b.lower() for b in extra_banned]:
        if w in low:
            errors.append(f"banned word in short.txt: {w!r}")
    first = short.strip().split("\n", 1)[0] if short.strip() else ""
    if not first:
        errors.append("short.txt is empty")
    elif FIRST_LINE_BANNED.search(first):
        errors.append("short.txt must start with common ground, not a denial")
    if DOSING.search(short):
        errors.append(
            "dosing-like amount in short.txt: never give doses, send to the doctor"
        )
    if short.count("—") > 1:
        warns.append("more than one em dash in short.txt")
    msg = work.get("message", {})
    for k in ("true_part", "doesnt_hold", "help", "technique"):
        if not (msg.get(k) or "").strip():
            errors.append(f"message.{k} is empty")
    claims = work.get("claims", [])
    if not claims:
        errors.append("no claims")
    risky = any(c.get("harm") or c.get("verdict") == "опасно" for c in claims)
    if risky and not (msg.get("dont") or "").strip():
        errors.append("a claim is marked harmful but message.dont is empty")
    for c in claims:
        cid = c.get("id", "?")
        v = c.get("verdict")
        if v not in VERDICTS:
            errors.append(f"claim {cid}: verdict {v!r} not in scale")
            continue
        if c.get("kind") not in CLAIM_KINDS:
            errors.append(f"claim {cid}: kind {c.get('kind')!r} not in {CLAIM_KINDS}")
        if not (c.get("reason") or "").strip():
            errors.append(f"claim {cid}: no reason")
        if v == "не удалось проверить":
            continue
        srcs = c.get("sources") or []
        if not srcs:
            errors.append(f"claim {cid}: verdict {v!r} has no source")
        for s in srcs:
            p = source_path(d, s.get("url", ""))
            if not p.exists():
                errors.append(
                    f"claim {cid}: source not fetched via `source`: {s.get('url')}"
                )
                continue
            q = norm(s.get("quote", ""))
            if len(q) < 20:
                errors.append(f"claim {cid}: quote missing or too short for {s['url']}")
            elif q not in norm(p.read_text()):
                errors.append(
                    f"claim {cid}: quote not found in fetched text of {s['url']}"
                )
    return errors, warns


def cmd_lint(args, cfg) -> int:
    d = video_dir(out_dir(args, cfg), args.id)
    work = load_work(d)
    sp = d / "short.txt"
    short = (
        sp.read_text().strip() if sp.exists() else build_short(work.get("message", {}))
    )
    errors, warns = lint_work(work, short, d, cfg.get("banned", []))
    for w in warns:
        print(f"warn: {w}")
    for e in errors:
        print(f"FAIL: {e}")
    print(
        f"lint: {'FAIL' if errors else 'ok'} ({len(errors)} errors, {len(warns)} warnings; ran: length, banned words, dosing, claims, sources+quotes)"
    )
    return 2 if errors else 0


# ---------- queue ----------


def queue_path(root: Path) -> Path:
    return root / "queue.json"


def load_queue(root: Path) -> dict:
    p = queue_path(root)
    return json.loads(p.read_text()) if p.exists() else {"items": {}}


def save_queue(root: Path, q: dict) -> None:
    queue_path(root).write_text(json.dumps(q, ensure_ascii=False, indent=1))


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def cmd_queue_add(args, cfg) -> int:
    root = out_dir(args, cfg)
    q = load_queue(root)
    sid = item_id(args.url)
    it = q["items"].get(sid)
    if it:
        print(json.dumps({"id": sid, "status": it["status"], "existing": True}))
        return 0
    q["items"][sid] = {
        "id": sid,
        "url": args.url,
        "from": args.from_label or "",
        "status": "pending",
        "added": now(),
    }
    save_queue(root, q)
    print(json.dumps({"id": sid, "status": "pending", "existing": False}))
    return 0


def agent_prompt(sid: str, d: Path, cfg: dict) -> str:
    skill = Path(__file__).resolve().parent.parent / "SKILL.md"
    aud = cfg["audiences"].get(cfg["audience"], cfg["audiences"]["default"])
    return (
        f"Read {skill} and follow its steps 2-4 for the already fetched item in {d} "
        f"(video.json, transcript.txt). Audience profile: {json.dumps(aud, ensure_ascii=False)}. "
        f"Save evidence with `claim_check.py source {sid} <url>`, write {d}/work.json, then run "
        f"`claim_check.py render {sid}` and `claim_check.py lint {sid}` with out dir {d.parent} "
        f"and fix until lint is ok. Do not send anything anywhere. Reply with one line."
    )


def process(sid: str, url: str, root: Path, cfg: dict, args) -> tuple[str, str]:
    """fetch -> agent -> render -> lint. Returns (status, note)."""
    d = video_dir(root, sid)
    if not (d / "video.json").exists():
        r = cmd_fetch(argparse.Namespace(src=url, out=str(root), no_whisper=False), cfg)
        if r != 0:
            return "failed", "fetch"
    if not (d / "work.json").exists():
        cmd = shlex.split(args.agent_cmd or cfg["agent_cmd"]) + [
            agent_prompt(sid, d, cfg)
        ]
        env = {**os.environ, "CLAIM_CHECK_OUT": str(root)}
        try:
            p = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=cfg["agent_timeout_s"],
                env=env,
            )
        except (subprocess.TimeoutExpired, OSError) as e:
            return "failed", f"agent: {e}"
        if p.returncode != 0 or not (d / "work.json").exists():
            return "failed", f"agent exit {p.returncode}, no work.json"
    ns = argparse.Namespace(id=sid, out=str(root))
    if cmd_render(ns, cfg) != 0:
        return "failed", "render"
    if cmd_lint(ns, cfg) != 0:
        return "needs-review", "lint failed"
    return "done", ""


def cmd_queue_run(args, cfg) -> int:
    root = out_dir(args, cfg)
    q = load_queue(root)
    todo = [i for i in q["items"].values() if i["status"] in ("pending", "failed")][
        : args.max
    ]
    bad = 0
    for it in todo:
        status, note = process(it["id"], it["url"], root, cfg, args)
        it.update(status=status, note=note, finished=now())
        save_queue(root, q)  # after every item: a crash loses at most one
        print(f"{it['id']}: {status} {note}".rstrip())
        bad += status != "done"
    print(f"queue run: {len(todo)} processed, {bad} not done")
    return 4 if bad else 0


def cmd_queue_list(args, cfg) -> int:
    for it in load_queue(out_dir(args, cfg))["items"].values():
        print(f"{it['id']}\t{it['status']}\t{it.get('from', '')}\t{it['url']}")
    return 0


def cmd_queue_show(args, cfg) -> int:
    d = out_dir(args, cfg) / args.id
    it = load_queue(out_dir(args, cfg))["items"].get(args.id)
    if not it or it["status"] != "done":
        print(f"not done: {it['status'] if it else 'unknown id'}", file=sys.stderr)
        return 1
    print((d / "short.txt").read_text(), end="")
    return 0


# ---------- cli ----------


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="claim_check")
    ap.add_argument("--config")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p):
        p.add_argument("--out")
        return p

    p = common(sub.add_parser("fetch"))
    p.add_argument("src")
    p.add_argument("--no-whisper", action="store_true")
    p = common(sub.add_parser("source"))
    p.add_argument("id")
    p.add_argument("url")
    for n in ("render", "lint"):
        p = common(sub.add_parser(n))
        p.add_argument("id")
    q = sub.add_parser("queue").add_subparsers(dest="qcmd", required=True)
    p = common(q.add_parser("add"))
    p.add_argument("url")
    p.add_argument("--from", dest="from_label")
    p = common(q.add_parser("run"))
    p.add_argument("--max", type=int, default=3)
    p.add_argument("--agent-cmd")
    common(q.add_parser("list"))
    p = common(q.add_parser("show"))
    p.add_argument("id")

    args = ap.parse_args(argv)
    cfg = load_config(args.config)
    if args.cmd == "queue":
        return {
            "add": cmd_queue_add,
            "run": cmd_queue_run,
            "list": cmd_queue_list,
            "show": cmd_queue_show,
        }[args.qcmd](args, cfg)
    return {
        "fetch": cmd_fetch,
        "source": cmd_source,
        "render": cmd_render,
        "lint": cmd_lint,
    }[args.cmd](args, cfg)


if __name__ == "__main__":
    sys.exit(main())
