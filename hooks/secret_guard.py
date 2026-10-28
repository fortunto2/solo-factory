#!/usr/bin/env python3
"""secret_guard.py — keep credentials out of the conversation.

A secret that reaches the context is sent to the model and written to the session
transcript in plain text. Measured on one machine (2026-10-25): 34 transcripts held
.env-style assignments, plus 6 AWS keys, 28 Google keys and a private key block.

  post    PostToolUse, every tool: secrets in the tool's output are replaced with
          [REDACTED:<rule> len=N id=<sha8>] before the model sees them. The output keeps
          its structure (updatedToolOutput must match the tool's schema).
  pre     PreToolUse on Write/Edit/MultiEdit/NotebookEdit: refuse content that carries a
          redaction marker — writing it would replace the real secret with the marker.
  prompt  UserPromptSubmit: a pasted secret is moved to ~/.claude/secrets/<project>.env
          (0600) and the prompt is blocked, so the value never reaches the model.
  audit   Report secrets already in transcripts: rule, id, length, sessions. No values.
  scrub   Rewrite transcripts in place, values -> markers. Skips files written in the last
          10 minutes (a live session appends to its file). Needed because a prompt blocked
          by `prompt` is still echoed into the transcript as "Original prompt: ..." by
          Claude Code itself: the model never sees it, the disk does.

Rules are deterministic and conservative, adapted from ScreenShield's leak detectors:
a missed placeholder costs one marker, a missed key costs a rotation.
Off switch: SECRET_GUARD=off.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

MARK = "[REDACTED:"
TOKEN_RULES = [
    (
        "private-key-block",
        re.compile(
            r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|\Z)"
        ),
    ),
    ("anthropic-key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}")),
    ("openai-key", re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}")),
    ("aws-access-key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    (
        "github-token",
        re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,})"),
    ),
    ("stripe-live-key", re.compile(r"\b[sr]k_live_[0-9a-zA-Z]{20,}")),
    ("slack-token", re.compile(r"\bxox[baprs]-[0-9A-Za-z-]{10,}")),
    ("google-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}")),
    ("huggingface-token", re.compile(r"\bhf_[A-Za-z0-9]{34,}")),
    ("telegram-bot-token", re.compile(r"\b\d{8,10}:AA[A-Za-z0-9_-]{33}\b")),
    (
        "jwt",
        re.compile(
            r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
        ),
    ),
]
# Only the value is masked: the name tells the agent which variable to use.
ENV_RULE = re.compile(
    r"\b([A-Z][A-Z0-9_]*(?:SECRET|TOKEN|API_KEY|APIKEY|PASSWORD|PASSWD|PRIVATE_KEY|ACCESS_KEY)[A-Z0-9_]*)"
    r"(\s*[:=]\s*[\"']?)([^\s\"'`,;)]{12,})"
)
DSN_RULE = re.compile(
    r"\b((?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqp)://[^\s:/@]+:)([^\s@/]{4,})(@)"
)
PLACEHOLDER = re.compile(
    r"(?i)x{3,}|\*{3,}|your|example|changeme|placeholder|dummy|redacted|<|>|\$|\{|\.\.\."
)
NAMES = {
    "anthropic-key": "ANTHROPIC_API_KEY",
    "openai-key": "OPENAI_API_KEY",
    "aws-access-key": "AWS_ACCESS_KEY_ID",
    "github-token": "GITHUB_TOKEN",
    "stripe-live-key": "STRIPE_SECRET_KEY",
    "slack-token": "SLACK_TOKEN",
    "google-api-key": "GOOGLE_API_KEY",
    "huggingface-token": "HF_TOKEN",
    "telegram-bot-token": "TELEGRAM_BOT_TOKEN",
    "jwt": "JWT",
    "private-key-block": "PRIVATE_KEY",
}


def _looks_secret(v: str) -> bool:
    """An assigned value counts when it is not a placeholder and mixes character classes.
    A URL is an endpoint (OAUTH_TOKEN_URL), not a secret; credentials inside one are
    DSN_RULE's."""
    if PLACEHOLDER.search(v) or "EXAMPLE" in v or "://" in v:
        return False
    classes = sum(bool(re.search(p, v)) for p in (r"[a-z]", r"[A-Z]", r"\d"))
    return classes >= 2


def marker(rule: str, value: str) -> str:
    return f"[REDACTED:{rule} len={len(value)} id={hashlib.sha256(value.encode()).hexdigest()[:8]}]"


def find(text: str) -> list[tuple[str, str, str | None]]:
    """(rule, value, env name if assigned) for every secret in text."""
    out = []
    for rule, rx in TOKEN_RULES:
        for m in rx.finditer(text):
            v = m.group(0)
            if rule == "aws-access-key" and "EXAMPLE" in v:
                continue
            if rule in ("openai-key", "jwt") and not re.search(r"\d", v):
                continue
            out.append((rule, v, None))
    for m in ENV_RULE.finditer(text):
        if (
            MARK not in m.group(3)
            and _looks_secret(m.group(3))
            and not any(m.group(3) in v for _, v, _ in out)
        ):
            out.append(("env-secret", m.group(3), m.group(1)))
    for m in DSN_RULE.finditer(text):
        if not PLACEHOLDER.search(m.group(2)):
            out.append(("dsn-password", m.group(2), None))
    return out


def mask_text(text: str) -> tuple[str, list[str]]:
    hits = find(text)
    # longest first, so a key inside a longer match is not half-replaced
    for rule, v, _ in sorted(hits, key=lambda h: -len(h[1])):
        text = text.replace(v, marker(rule, v))
    return text, [h[0] for h in hits]


def mask_obj(obj, rules: list[str]):
    if isinstance(obj, str):
        if len(obj) > 4_000_000:
            return obj
        new, hit = mask_text(obj)
        rules += hit
        return new
    if isinstance(obj, list):
        return [mask_obj(x, rules) for x in obj]
    if isinstance(obj, dict):
        return {k: mask_obj(v, rules) for k, v in obj.items()}
    return obj


def emit(obj: dict) -> None:
    print(json.dumps(obj))


def post(inp: dict) -> None:
    resp = inp.get("tool_response")
    if resp is None:
        return
    rules: list[str] = []
    masked = mask_obj(resp, rules)
    if not rules:
        return
    kinds = ", ".join(sorted(set(rules)))
    emit(
        {
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "updatedToolOutput": masked,
                "additionalContext": f"secret_guard masked {len(rules)} secret(s) in this output ({kinds}). Refer to them by "
                "variable name or file (e.g. `source .env`); never type or write a [REDACTED:...] marker.",
            }
        }
    )


def pre(inp: dict) -> None:
    if MARK in json.dumps(inp.get("tool_input", {})):
        emit(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": "This content contains a [REDACTED:...] marker from secret_guard: writing it "
                    "would replace the real secret with the marker. Edit around the secret (a smaller Edit), or reference it "
                    "through an environment variable.",
                }
            }
        )


def secrets_file(cwd: str) -> Path:
    d = Path(os.environ.get("SECRET_GUARD_DIR", Path.home() / ".claude" / "secrets"))
    d.mkdir(parents=True, exist_ok=True, mode=0o700)
    slug = re.sub(r"[^A-Za-z0-9_-]", "-", Path(cwd or os.getcwd()).name) or "default"
    return d / f"{slug}.env"


def prompt(inp: dict) -> None:
    hits = find(inp.get("prompt", ""))
    if not hits:
        return
    f = secrets_file(inp.get("cwd", ""))
    existing = f.read_text() if f.exists() else ""
    taken = set(re.findall(r"^([A-Z][A-Z0-9_]*)=", existing, re.M))
    saved = []
    for rule, value, name in hits:
        if value in existing:
            saved.append(
                next(
                    n
                    for n, v in re.findall(r"^([A-Z][A-Z0-9_]*)=(.*)$", existing, re.M)
                    if v.strip("'") == value
                )
            )
            continue
        base = name or NAMES.get(rule, "SECRET")
        n, i = base, 2
        while n in taken:
            n, i = f"{base}_{i}", i + 1
        taken.add(n)
        quoted = "'" + value.replace("'", "'\\''") + "'"
        existing += f"{n}={quoted}\n"
        saved.append(n)
    f.write_text(existing)
    os.chmod(f, 0o600)
    emit(
        {
            "decision": "block",
            "reason": f"secret_guard: your message contained {len(hits)} secret(s); the prompt was NOT sent. Saved to {f} as "
            f"{', '.join(saved)}. Resend without the value and refer to it by name; the agent can `set -a; source {f}`.",
        }
    )


def audit(root: Path) -> None:
    seen: dict[str, dict] = {}
    files = sorted(root.rglob("*.jsonl"))
    for path in files:
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        for rule, value, name in find(text.replace("\\n", "\n")):
            k = hashlib.sha256(value.encode()).hexdigest()[:8]
            s = seen.setdefault(
                k, {"rule": rule, "name": name, "len": len(value), "files": set()}
            )
            s["files"].add(path)
    by_rule = defaultdict(list)
    for k, s in seen.items():
        by_rule[s["rule"]].append((k, s))
    print(
        f"secret_guard audit: {len(files)} transcripts under {root}, {len(seen)} distinct secrets (values not shown)"
    )
    for rule, items in sorted(by_rule.items(), key=lambda x: -len(x[1])):
        print(f"\n{rule}: {len(items)}")
        for k, s in sorted(items, key=lambda x: -len(x[1]["files"]))[:15]:
            projects = sorted(
                {
                    p.parent.name.replace("-Users-rustam-", "~/").replace("-", "/")
                    for p in s["files"]
                }
            )
            print(
                f"  id={k} len={s['len']:<4} {s['name'] or '':28} in {len(s['files'])} session(s): {', '.join(projects[:3])}"
            )


def _broken_lines(before: str, after: str) -> bool:
    """True when a line that parsed as JSON before the rewrite no longer does."""
    for a, b in zip(before.splitlines(), after.splitlines(), strict=False):
        if a == b:
            continue
        try:
            json.loads(a)
        except ValueError:
            continue
        try:
            json.loads(b)
        except ValueError:
            return True
    return False


def scrub(paths: list[Path], min_age_s: int = 600) -> None:
    import time

    changed = skipped = 0
    for path in paths:
        if time.time() - path.stat().st_mtime < min_age_s:
            skipped += 1
            continue
        before = path.read_text(errors="ignore")
        lines, hits = [], 0
        for line in before.splitlines(keepends=True):
            body = line.rstrip("\n")
            try:
                obj = json.loads(body)
            except ValueError:
                obj = None
            if obj is None:  # not JSON: mask as plain text
                new, found = mask_text(body)
            else:  # JSON: mask the decoded strings, so escapes can never be cut in half
                found = []
                masked = mask_obj(obj, found)
                new = (
                    json.dumps(masked, ensure_ascii=False, separators=(",", ":"))
                    if found
                    else body
                )
            hits += len(found)
            lines.append(new + line[len(body) :])
        if not hits:
            continue
        text = "".join(lines)
        if _broken_lines(before, text):
            print(f"skipped {path}: a replacement would break a JSON line")
            continue
        tmp = path.with_suffix(".jsonl.scrub")
        tmp.write_text(text)
        tmp.replace(path)
        changed += 1
        print(f"scrubbed {hits} secret(s) in {path}")
    print(
        f"secret_guard scrub: {changed} file(s) rewritten, {skipped} skipped as live (< {min_age_s}s old)"
    )


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "audit":
        audit(
            Path(sys.argv[2])
            if len(sys.argv) > 2
            else Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
            / "projects"
        )
        return
    if mode == "scrub":
        args = [Path(a) for a in sys.argv[2:] if not a.startswith("--")]
        files = [
            f
            for a in args
            for f in ([a] if a.is_file() else sorted(a.rglob("*.jsonl")))
        ]
        scrub(files, 0 if "--now" in sys.argv else 600)
        return
    if os.environ.get("SECRET_GUARD") == "off":
        return
    try:
        inp = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    {"post": post, "pre": pre, "prompt": prompt}.get(mode, lambda _: None)(inp)


if __name__ == "__main__":
    main()
