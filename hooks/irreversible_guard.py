#!/usr/bin/env python3
"""irreversible_guard.py — PreToolUse(Bash): an irreversible or outward command needs a human.

A rule in CLAUDE.md ("confirm before force-pushing") is a sentence the agent can
misread; a guard that checks state the agent can change is a door with the key in it.
Measured: a delete command that refused anything but private videos was passed in two
calls, flip the video to private, then delete. So this guard looks at the *command*,
never at state the agent controls, and the only way past it belongs to the human.

Matched (per shell segment, after `;` `&&` `||` `|` and newlines):
  force-push       git push -f / --force / --force-with-lease / --force-if-includes / +refspec
  remote-delete    git push --delete / -d / :branch
  rm-recursive     rm -r/-R/--recursive on a path outside tmp, the scratchpad, or a
                   regenerable build dir (node_modules, target, dist, ...)
  gh-delete        gh repo delete, gh release delete
  project-pattern  any regex line in .claude/irreversible-commands.txt (project) or
                   ~/.claude/irreversible-commands.txt (user), e.g. `yt_upload\\.py\\s+delete`

Decision: "ask" where Claude Code guarantees a prompt (default, acceptEdits, plan, auto).
In bypassPermissions and dontAsk a hook's "ask" is not documented to prompt, so the
answer there is "deny" with a reason: the human runs it with `! <command>`, or starts
the session with SOLO_ALLOW_DESTRUCTIVE=1. That variable is read from the hook's own
environment, which the agent cannot set from a tool call (`VAR=1 cmd` does not reach it).

Every match is appended to one log: $SOLO_GUARD_LOG, default
${CLAUDE_CONFIG_DIR:-~/.claude}/solo/irreversible-guard.log (JSON lines).
"""

from __future__ import annotations

import datetime
import json
import os
import re
import shlex
import sys
from pathlib import Path

PROMPTING_MODES = {"default", "acceptEdits", "plan", "auto", "manual", ""}
REGENERABLE = {
    "node_modules",
    "target",
    "dist",
    "build",
    ".build",
    ".venv",
    "venv",
    "__pycache__",
    ".pytest_cache",
    ".ruff_cache",
    ".mypy_cache",
    ".next",
    ".turbo",
    "DerivedData",
    "coverage",
    ".cache",
}
TMP_PREFIXES = ("/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/")
SEPARATORS = re.compile(r"\|\||&&|[;|\n]")


def segments(command: str) -> list[list[str]]:
    out = []
    for part in SEPARATORS.split(command):
        try:
            words = shlex.split(part, comments=True)
        except ValueError:
            words = part.split()
        while words and (
            re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0])
            or words[0] in ("sudo", "command", "exec", "time", "nohup")
        ):
            words = words[1:]
        if words:
            out.append(words)
    return out


def tmp_like(path: str) -> bool:
    p = os.path.expanduser(os.path.expandvars(path))
    tmpdir = os.environ.get("TMPDIR", "")
    if tmpdir and os.path.abspath(p).startswith(os.path.abspath(tmpdir)):
        return True
    absolute = os.path.abspath(p) + "/"
    if absolute.startswith(TMP_PREFIXES) or "/scratchpad/" in absolute:
        return True
    return os.path.basename(os.path.normpath(p)) in REGENERABLE


def git_rule(words: list[str]) -> str | None:
    if words[0] != "git" or "push" not in words:
        return None
    args = words[words.index("push") + 1 :]
    flags = [a for a in args if a.startswith("-")]
    refs = [a for a in args if not a.startswith("-")]
    if any(
        f in ("-f", "--force", "--force-with-lease", "--force-if-includes")
        or f.startswith("--force-with-lease=")
        or (re.fullmatch(r"-[a-zA-Z]+", f) and "f" in f)
        for f in flags
    ) or any(r.startswith("+") for r in refs):
        return "force-push"
    if any(f in ("-d", "--delete") for f in flags) or any(
        r.startswith(":") and len(r) > 1 for r in refs
    ):
        return "remote-delete"
    return None


def rm_rule(words: list[str]) -> str | None:
    if os.path.basename(words[0]) != "rm":
        return None
    opts, paths, ended = [], [], False
    for w in words[1:]:
        if not ended and w == "--":
            ended = True
        elif not ended and w.startswith("-"):
            opts.append(w)
        else:
            paths.append(w)
    recursive = any(
        o in ("--recursive",)
        or (re.fullmatch(r"-[a-zA-Z]+", o) and ("r" in o or "R" in o))
        for o in opts
    )
    if recursive and paths and not all(tmp_like(p) for p in paths):
        return "rm-recursive"
    return None


def gh_rule(words: list[str]) -> str | None:
    if (
        words[0] == "gh"
        and len(words) >= 3
        and words[2] == "delete"
        and words[1] in ("repo", "release")
    ):
        return "gh-delete"
    return None


def project_patterns() -> list[re.Pattern]:
    files = [Path(os.path.expanduser("~/.claude/irreversible-commands.txt"))]
    proj = os.environ.get("CLAUDE_PROJECT_DIR")
    if proj:
        files.append(Path(proj) / ".claude" / "irreversible-commands.txt")
    out = []
    for f in files:
        try:
            lines = f.read_text().splitlines()
        except OSError:
            continue
        for line in lines:
            line = line.strip()
            if line and not line.startswith("#"):
                try:
                    out.append(re.compile(line))
                except re.error:
                    pass
    return out


def match(command: str) -> str | None:
    for words in segments(command):
        for rule in (git_rule, rm_rule, gh_rule):
            hit = rule(words)
            if hit:
                return hit
    for pat in project_patterns():
        if pat.search(command):
            return "project-pattern"
    return None


def log(entry: dict) -> None:
    path = os.environ.get("SOLO_GUARD_LOG") or os.path.join(
        os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"),
        "solo",
        "irreversible-guard.log",
    )
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a") as fh:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


def decide(inp: dict) -> dict | None:
    if inp.get("tool_name") != "Bash":
        return None
    command = (inp.get("tool_input") or {}).get("command", "")
    rule = match(command)
    if not rule:
        return None
    mode = inp.get("permission_mode", "")
    if os.environ.get("SOLO_ALLOW_DESTRUCTIVE") == "1":
        decision, out = "allow-override", None
    elif mode in PROMPTING_MODES:
        decision = "ask"
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason": f"irreversible_guard: {rule}. Confirm only if you asked for exactly this.",
            }
        }
    else:
        decision = "deny"
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    f"irreversible_guard: {rule} in {mode} mode, where no prompt is guaranteed. Ask the human "
                    "for this exact command and have them run it with `! <command>`, or restart the session "
                    "with SOLO_ALLOW_DESTRUCTIVE=1. Do not rephrase the command to get around this."
                ),
            }
        }
    log(
        {
            "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
            "mode": mode,
            "rule": rule,
            "decision": decision,
            "cwd": inp.get("cwd", ""),
            "command": command[:500],
        }
    )
    return out


def main() -> int:
    try:
        inp = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    out = decide(inp)
    if out:
        print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
