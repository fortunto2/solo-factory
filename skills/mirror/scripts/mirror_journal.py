"""Incremental journal of typed prompts: when, which project, how long, and what kind of act it was.

One line per typed prompt in an append-only JSONL file. The journal never holds prompt text or a summary of it; the text
exists in memory while a prompt is labelled and goes nowhere else (a model batch, when labelling is on).

Row: ts (UTC), day_local, project, session, uuid (message uuid = the key), chars, mode, conf, by, v.

A cursor file keeps, per transcript, the byte offset already read, so a run reads only new bytes and a run with nothing
new makes no model call. A truncated or replaced transcript is read again from the start; the uuid key keeps the
journal free of duplicates. Labels change only when `v` changes, and then only on demand (`relabel`).

A second profile (`work_profiles`) is counted as time only: its rows carry ts, uuid and chars, `project: work`,
`mode: work`, `by: none`. Its text, its directory names and its session ids never reach the journal, a model batch,
the cursor or a log line.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

LABEL_VERSION = 1
LABELS = ("task", "steer", "decide", "kick", "watch", "think", "other")
# a bucket takes the label with the highest rank
RANK = {
    "task": 6,
    "think": 5,
    "steer": 4,
    "decide": 3,
    "watch": 2,
    "kick": 1,
    "other": 0,
}
BATCH = 60
TRUNC = 600

INJECTED = re.compile(
    r"<(system-reminder|command-name|command-message|command-args|local-command-stdout|local-command-stderr|"
    r"task-notification|teammate-message|bash-input|bash-stdout|bash-stderr)\b.*?</\1>",
    re.DOTALL,
)
NOT_TYPED = re.compile(
    r"^(Another Claude|This session is being continued|\[Request interrupted|<artifact-comment|\[SYSTEM NOTIFICATION)"
)
CONTINUE = re.compile(
    r"^(продолжай|продолжи|дальше|далее|continue|go on|go ahead|next)[.!\s]*$",
    re.IGNORECASE,
)
MARKER = "MIRROR-LABEL-BATCH"  # first line of every labelling prompt, so a transcript of it is recognised as automation

LABEL_DEFS = """Labels (one per message; judge by what the message DOES, not by its length):
task   sets new work or a new goal: something to build, fix, write, find, explain or decide, including a direct question asking the agent to find out or explain something new.
steer  corrects, redirects or adds to work already in progress: a constraint, a reaction to a result ("not like that", "also X", "on the second video maybe"), a fragment that refines the current thing.
decide answers the agent's question, approves, picks an option, says yes/no to a proposal, or reports a result back to the agent so it can go on.
kick   a nudge with no new information: continue, well?, status?, ok go.
watch  asks to look at, check or report on something that is running or already exists, without changing it (is the build done, what is the disk usage now).
think  thinks aloud: an idea, a principle, how things should work, a reflection, a feeling about a result, a question to oneself.
other  ONLY a bare paste, path, id, command or code with no sentence and no intent that can be named. Prefer a specific label over other."""


# ---------------------------------------------------------------- parsing


def typed_text(rec: dict) -> str:
    """The text a person typed in a user record, or '' (tool results, injected blocks, sidechains, meta lines)."""
    if rec.get("type") != "user" or rec.get("isSidechain") or rec.get("isMeta"):
        return ""
    c = rec.get("message", {}).get("content")
    if isinstance(c, list):
        c = " ".join(
            x.get("text", "")
            for x in c
            if isinstance(x, dict) and x.get("type") == "text"
        )
    text = INJECTED.sub("", c).strip() if isinstance(c, str) else ""
    return "" if NOT_TYPED.search(text) else text


def rule_label(text: str) -> str | None:
    """Only the certain cases: a bare 'continue'."""
    return "kick" if CONTINUE.match(text.strip()) else None


def scan_file(
    path: Path, st: dict, auto_rx: re.Pattern | None, keep_cwd: bool = True
) -> tuple[list[dict], dict]:
    """New typed prompts of one transcript since the cursor state `st`. Rows carry `text` (memory only) and `cwd`.
    Returns (rows, new state). Only whole lines are consumed, so a line still being written is read next time."""
    sz, mt = path.stat().st_size, path.stat().st_mtime
    if st and st.get("size") == sz and st.get("mtime") == mt:
        return [], st
    with path.open("rb") as fh:
        head = hashlib.sha1(fh.read(256)).hexdigest()
        if st and (
            st.get("head") != head or sz < st.get("offset", 0)
        ):  # replaced or truncated: start again
            st = {}
        off = st.get("offset", 0)
        fh.seek(off)
        data = fh.read()
    cut = data.rfind(b"\n") + 1
    new = {**st, "head": head, "offset": off + cut, "size": sz, "mtime": mt}
    if st.get("auto"):
        return [], new
    rows = []
    for raw in data[:cut].splitlines():
        if b'"type":"user"' not in raw:
            continue
        try:
            rec = json.loads(raw)
        except ValueError:
            continue
        text = typed_text(rec)
        if not text or not rec.get("timestamp"):
            continue
        if not new.get("seen_first"):
            new["seen_first"] = True
            new["auto"] = bool(auto_rx and auto_rx.search(text[:400]))
            if new["auto"]:
                return [], new
        if (
            keep_cwd
        ):  # a work profile never keeps a directory name, not even in the cursor
            new["cwd"] = new.get("cwd") or rec.get("cwd", "")
        rows.append(
            {
                "ts": datetime.fromisoformat(
                    rec["timestamp"].replace("Z", "+00:00")
                ).astimezone(timezone.utc),
                "uuid": rec.get("uuid")
                or hashlib.sha1(
                    f"{path.stem}{rec['timestamp']}{len(text)}".encode()
                ).hexdigest()[:16],
                "chars": len(text),
                "text": text,
            }
        )
    return rows, new


# ---------------------------------------------------------------- labelling


def build_prompt(texts: list[str]) -> str:
    flat = [re.sub(r"\s+", " ", t)[:TRUNC] for t in texts]
    lines = [f"{i}|{t}" for i, t in enumerate(flat, 1)]
    return (
        f"{MARKER}\nYou label messages a person typed to an AI coding agent. {LABEL_DEFS}\n"
        'Output ONLY a JSON list, one object per message: [{"i":1,"m":"task","c":0.9}] where i is the message number, '
        "m one label, c your confidence 0..1. No prose, no text of the messages.\n\nMessages (number|text):\n"
        + "\n".join(lines)
    )


def parse_labels(out: str, n: int) -> dict[int, tuple[str, float]]:
    """Strict parse of the model's JSON list; anything malformed is simply absent from the result."""
    m = re.search(r"\[.*\]", out, re.DOTALL)
    got: dict[int, tuple[str, float]] = {}
    if not m:
        return got
    try:
        items = json.loads(m[0])
    except ValueError:
        return got
    for it in items if isinstance(items, list) else []:
        if (
            isinstance(it, dict)
            and isinstance(it.get("i"), int)
            and 1 <= it["i"] <= n
            and it.get("m") in LABELS
        ):
            c = it.get("c")
            got[it["i"]] = (it["m"], float(c) if isinstance(c, int | float) else 0.5)
    return got


def claude_model(prompt: str, model: str = "claude-haiku-5-5") -> str:
    """One headless call: no tools, no settings, no saved session, from a scratch directory."""
    with tempfile.TemporaryDirectory(prefix="mirror-label-") as cwd:
        r = subprocess.run(
            [
                "claude",
                "-p",
                "--model",
                model,
                "--no-session-persistence",
                "--tools",
                "",
                "--setting-sources",
                "",
                "--disable-slash-commands",
            ],
            input=prompt,
            capture_output=True,
            text=True,
            cwd=cwd,
            timeout=300,
            check=False,
        )
    if r.returncode:
        raise RuntimeError(
            f"labelling call failed rc={r.returncode}"
        )  # never echo stderr: it may quote the batch
    return r.stdout


def label_texts(
    texts: list[str], model_fn, workers: int = 3
) -> list[tuple[str, float, str]]:
    """(label, confidence, by) per text. Rules first, then batches; a text the model skipped is asked once more, then 'other'."""
    out: list[tuple[str, float, str] | None] = [None] * len(texts)
    todo = []
    for i, t in enumerate(texts):
        lab = rule_label(t)
        if lab:
            out[i] = (lab, 1.0, "rule")
        else:
            todo.append(i)

    def run(chunk: list[int]) -> dict[int, tuple[str, float, str]]:
        res: dict[int, tuple[str, float, str]] = {}
        pending = chunk
        for _ in range(2):
            got = parse_labels(
                model_fn(build_prompt([texts[i] for i in pending])), len(pending)
            )
            for k, (lab, c) in got.items():
                res[pending[k - 1]] = (lab, c, "claude")
            pending = [i for i in chunk if i not in res]
            if not pending:
                break
        for i in pending:
            res[i] = ("other", 0.0, "claude")
        return res

    chunks = [todo[i : i + BATCH] for i in range(0, len(todo), BATCH)]
    with ThreadPoolExecutor(max_workers=workers) as ex:
        for res in ex.map(run, chunks):
            for i, v in res.items():
                out[i] = v
    return [o or ("other", 0.0, "claude") for o in out]


# ---------------------------------------------------------------- journal


def read_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def read_journal(path: Path) -> list[dict]:
    if not path.exists():
        return []
    rows = []
    for line in path.read_text().splitlines():
        try:
            rows.append(json.loads(line))
        except ValueError:
            continue  # a torn last line from a killed run
    return rows


def sources(cfg: dict) -> list[dict]:
    """Transcript directories to read: own (text labelled) and work profiles (time only)."""
    sess = cfg["sessions"]
    excl = [s for s in sess["exclude_dir_substrings"] if s]
    out = []
    root = Path(os.path.expanduser(sess["dir"]))
    for d in sorted(root.glob("*")) if root.exists() else []:
        if d.is_dir() and not any(s in d.name for s in excl):
            out += [
                {"kind": "own", "path": f, "key": f"{d.name}/{f.name}"}
                for f in sorted(d.glob("*.jsonl"))
            ]
    for wp in cfg.get("work_profiles") or []:
        wroot = Path(os.path.expanduser(wp["dir"]))
        for f in sorted(wroot.glob("*/*.jsonl")) if wroot.exists() else []:
            out.append(
                {"kind": "work", "path": f, "key": f"work/{f.stem}"}
            )  # the file's own uuid, never its directory
    return out


def update(
    cfg: dict,
    projects_of,
    tz_of,
    model_fn=claude_model,
    limit_files: int | None = None,
    log=print,
) -> dict:
    """Read new bytes of every transcript, label the new own prompts, append rows, advance the cursor.
    Cursor and journal advance together per group of files, so a failed labelling call loses nothing."""
    jc = cfg.get("journal") or {}
    jpath = Path(os.path.expanduser(jc["path"]))
    cpath = Path(os.path.expanduser(jc["cursor"]))
    cursor = read_json(cpath, {})
    seen = {r["uuid"] for r in read_journal(jpath) if r.get("uuid")}
    auto = (
        re.compile(cfg["sessions"]["automation_regex"])
        if cfg["sessions"]["automation_regex"]
        else None
    )
    stats = {"files_read": 0, "new_rows": 0, "model_calls": 0, "work_rows": 0}
    group: list[tuple[dict, list[dict], dict]] = []
    inner = model_fn

    def counted(prompt: str) -> str:
        stats["model_calls"] += 1
        return inner(prompt)

    def flush() -> None:
        if not group:
            return
        own = [
            (s, r)
            for s, rows, _ in group
            if s["kind"] == "own"
            for r in rows
            if r["uuid"] not in seen
        ]
        labelled = label_texts([r["text"] for _, r in own], counted) if own else []
        lines = []
        for (s, r), (mode, conf, by) in zip(own, labelled, strict=True):
            lines.append(
                _row(
                    r,
                    s["st_cwd"],
                    projects_of(s["st_cwd"]) or "(none)",
                    s["session"],
                    mode,
                    conf,
                    by,
                    tz_of,
                )
            )
        for s, rows, _ in group:
            if s["kind"] == "work":
                for r in rows:
                    if r["uuid"] not in seen:
                        stats["work_rows"] += 1
                        lines.append(
                            _row(r, "", "work", "", "work", 1.0, "none", tz_of)
                        )
        lines = [ln for ln in lines if ln["uuid"] not in seen]
        for ln in lines:
            seen.add(ln["uuid"])
        if lines:
            jpath.parent.mkdir(parents=True, exist_ok=True)
            with jpath.open("a") as fh:
                for ln in lines:
                    fh.write(json.dumps(ln, ensure_ascii=False) + "\n")
        stats["new_rows"] += len(lines)
        for s, _, new in group:
            cursor[s["key"]] = new
        cpath.parent.mkdir(parents=True, exist_ok=True)
        cpath.write_text(json.dumps(cursor, indent=1) + "\n")
        group.clear()

    n = 0
    for s in sources(cfg):
        st = cursor.get(s["key"], {})
        try:
            rows, new = scan_file(s["path"], st, auto, s["kind"] == "own")
        except OSError:
            continue
        if new is st:
            continue
        stats["files_read"] += 1
        s = {
            **s,
            "st_cwd": new.get("cwd", ""),
            "session": s["path"].stem if s["kind"] == "own" else "",
        }
        group.append((s, rows, new))
        n += 1
        if sum(len(g[1]) for g in group) >= BATCH * 6:
            flush()
        if limit_files and n >= limit_files:
            break
    flush()
    return stats


def _row(
    r: dict,
    cwd: str,
    project: str,
    session: str,
    mode: str,
    conf: float,
    by: str,
    tz_of,
) -> dict:
    ts = r["ts"]
    return {
        "ts": ts.isoformat(timespec="seconds"),
        "day_local": ts.astimezone(tz_of(ts)).date().isoformat(),
        "project": project,
        "session": session,
        "uuid": r["uuid"],
        "chars": r["chars"],
        "mode": mode,
        "conf": round(conf, 2),
        "by": by,
        "v": LABEL_VERSION if by != "none" else 0,
    }
