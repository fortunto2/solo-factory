#!/usr/bin/env python3
"""Stream-json formatter for Claude Code pipeline output.

Reads stream-json events from stdin, outputs colored human-readable progress.
Designed for tmux pipelines — always outputs colors (use --no-color to disable).
Plays 8-bit sound effects per tool call (use --no-sound to disable).

Usage:
  claude --print --output-format stream-json -p "prompt" | solo-stream-fmt.py
  claude --print --output-format stream-json -p "prompt" | solo-stream-fmt.py --no-color
  claude --print --output-format stream-json -p "prompt" | solo-stream-fmt.py --no-sound
"""
import json
import sys
import os
import shutil
import wave
import struct
import math
import random
import subprocess
import tempfile
import time

# ── Flags ──
NO_COLOR = "--no-color" in sys.argv or os.environ.get("NO_COLOR")
NO_SOUND = "--no-sound" in sys.argv or os.environ.get("NO_SOUND")

# ── Colors (always on for tmux pipelines, --no-color to disable) ──
if NO_COLOR:
    DIM = CYAN = YELLOW = GREEN = RED = MAGENTA = BLUE = BOLD = RESET = ""
else:
    DIM = "\033[2m"
    CYAN = "\033[36m"
    YELLOW = "\033[33m"
    GREEN = "\033[32m"
    RED = "\033[31m"
    MAGENTA = "\033[35m"
    BLUE = "\033[34m"
    BOLD = "\033[1m"
    RESET = "\033[0m"

# Terminal width for path truncation
COLS = shutil.get_terminal_size((120, 40)).columns
HOME = os.path.expanduser("~")

# Tool icons (ASCII — hacker style, no emoji)
ICONS = {
    "Read": f"{CYAN}>>{RESET}",
    "Write": f"{YELLOW}<<{RESET}",
    "Edit": f"{YELLOW}<>{RESET}",
    "Bash": f"{GREEN}$ {RESET}",
    "Glob": f"{CYAN}**{RESET}",
    "Grep": f"{CYAN}//",
    "WebSearch": f"{GREEN}@@{RESET}",
    "WebFetch": f"{GREEN}@@{RESET}",
    "Task": f"{MAGENTA}::{RESET}",
    "Skill": f"{MAGENTA}=>{RESET}",
    "mcp": f"{BLUE}~~{RESET}",
    "BrowserNavigate": f"{GREEN}->{RESET}",
    "BrowserScreenshot": f"{GREEN}[]{RESET}",
    "BrowserClick": f"{GREEN}*!{RESET}",
    "BrowserType": f"{GREEN}aA{RESET}",
    "BrowserConsole": f"{GREEN}>_{RESET}",
    "BrowserWait": f"{GREEN}..{RESET}",
    "BrowserClose": f"{GREEN}xx{RESET}",
}


# ═══════════════════════════════════════════════
# 8-bit Sound Effects — generated once at startup
# ═══════════════════════════════════════════════

SAMPLE_RATE = 22050
SFX_VOLUME = float(os.environ.get("SFX_VOLUME", "0.15"))
_sfx_cache: dict[str, str] = {}  # event_type -> wav path
_sfx_dir: str = ""
_last_sfx_time: float = 0
SFX_COOLDOWN = 0.3  # min seconds between sounds


def _square(freq: float, duration: float, vol: float = 1.0, duty: float = 0.5) -> list[float]:
    """Generate square wave samples."""
    samples = []
    n = int(SAMPLE_RATE * duration)
    for i in range(n):
        if freq == 0:
            samples.append(0)
        else:
            t = i / SAMPLE_RATE
            phase = (t * freq) % 1.0
            val = vol if phase < duty else -vol
            # Quick attack + decay envelope
            env = min(1.0, i / (SAMPLE_RATE * 0.003))
            tail = max(0.0, 1.0 - (i / n) * 0.8)
            samples.append(val * env * tail)
    return samples


def _triangle(freq: float, duration: float, vol: float = 1.0) -> list[float]:
    """Generate triangle wave samples (softer than square)."""
    samples = []
    n = int(SAMPLE_RATE * duration)
    for i in range(n):
        if freq == 0:
            samples.append(0)
        else:
            t = i / SAMPLE_RATE
            phase = (t * freq) % 1.0
            val = (4 * abs(phase - 0.5) - 1) * vol
            env = min(1.0, i / (SAMPLE_RATE * 0.003))
            tail = max(0.0, 1.0 - (i / n) * 0.6)
            samples.append(val * env * tail)
    return samples


def _noise_burst(duration: float, vol: float = 0.5) -> list[float]:
    """Short noise burst for percussive sounds."""
    samples = []
    n = int(SAMPLE_RATE * duration)
    for i in range(n):
        env = max(0, 1.0 - (i / n) * 6)
        samples.append(random.uniform(-vol, vol) * env)
    return samples


def _write_wav(path: str, samples: list[float]):
    """Write samples to WAV file."""
    with wave.open(path, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        for s in samples:
            s = max(-0.95, min(0.95, s))
            w.writeframes(struct.pack('<h', int(s * 32767)))


def _merge(a: list[float], b: list[float]) -> list[float]:
    """Mix two sample lists."""
    length = max(len(a), len(b))
    result = []
    for i in range(length):
        va = a[i] if i < len(a) else 0
        vb = b[i] if i < len(b) else 0
        result.append(max(-0.95, min(0.95, va + vb)))
    return result


def _generate_all_sfx():
    """Generate all sound effect WAV files into a temp directory."""
    global _sfx_dir
    _sfx_dir = tempfile.mkdtemp(prefix="solo-sfx-")
    v = SFX_VOLUME

    # Read: soft ascending two-note (C5 → E5, triangle, gentle)
    s = _triangle(523, 0.06, v * 0.5) + _triangle(659, 0.08, v * 0.6)
    _write_wav(os.path.join(_sfx_dir, "read.wav"), s)
    _sfx_cache["read"] = os.path.join(_sfx_dir, "read.wav")

    # Write/Edit: decisive two-note chord (E4 → C5, square, punchy)
    s = _square(330, 0.05, v * 0.4, 0.25) + _square(523, 0.08, v * 0.5, 0.25)
    _write_wav(os.path.join(_sfx_dir, "write.wav"), s)
    _sfx_cache["write"] = os.path.join(_sfx_dir, "write.wav")

    # Bash: sharp click (noise + high square blip)
    s = _merge(_noise_burst(0.03, v * 0.3), _square(880, 0.04, v * 0.3, 0.15))
    _write_wav(os.path.join(_sfx_dir, "bash.wav"), s)
    _sfx_cache["bash"] = os.path.join(_sfx_dir, "bash.wav")

    # Search (Glob/Grep): scanning sweep (ascending A4→D5→A5)
    s = _triangle(440, 0.04, v * 0.4) + _triangle(587, 0.04, v * 0.45) + _triangle(880, 0.05, v * 0.5)
    _write_wav(os.path.join(_sfx_dir, "search.wav"), s)
    _sfx_cache["search"] = os.path.join(_sfx_dir, "search.wav")

    # Web (WebSearch/WebFetch): melodic ping (G5 with harmonics)
    s1 = _triangle(784, 0.1, v * 0.5)
    s2 = _square(784 * 2, 0.1, v * 0.15, 0.25)
    s = _merge(s1, s2)
    _write_wav(os.path.join(_sfx_dir, "web.wav"), s)
    _sfx_cache["web"] = os.path.join(_sfx_dir, "web.wav")

    # Task/Agent: arpeggio (C4→E4→G4→C5, exciting)
    s = (_square(262, 0.05, v * 0.35, 0.25) +
         _square(330, 0.05, v * 0.4, 0.25) +
         _square(392, 0.05, v * 0.45, 0.25) +
         _square(523, 0.08, v * 0.5, 0.25))
    _write_wav(os.path.join(_sfx_dir, "agent.wav"), s)
    _sfx_cache["agent"] = os.path.join(_sfx_dir, "agent.wav")

    # Skill: power-up (ascending fast: E5→G5→B5)
    s = _square(659, 0.04, v * 0.4, 0.3) + _square(784, 0.04, v * 0.45, 0.3) + _square(988, 0.06, v * 0.5, 0.3)
    _write_wav(os.path.join(_sfx_dir, "skill.wav"), s)
    _sfx_cache["skill"] = os.path.join(_sfx_dir, "skill.wav")

    # MCP: electronic blip (high square + quick noise)
    s = _merge(_square(1047, 0.04, v * 0.3, 0.2), _noise_burst(0.02, v * 0.1))
    _write_wav(os.path.join(_sfx_dir, "mcp.wav"), s)
    _sfx_cache["mcp"] = os.path.join(_sfx_dir, "mcp.wav")

    # Error: descending (A4→E4→C4, ominous)
    s = _square(440, 0.08, v * 0.5, 0.5) + _square(330, 0.08, v * 0.45, 0.5) + _square(262, 0.12, v * 0.4, 0.5)
    _write_wav(os.path.join(_sfx_dir, "error.wav"), s)
    _sfx_cache["error"] = os.path.join(_sfx_dir, "error.wav")

    # Stage start: fanfare (C4→E4→G4→C5, longer + louder)
    s = (_square(262, 0.08, v * 0.4, 0.25) +
         _square(330, 0.08, v * 0.45, 0.25) +
         _square(392, 0.08, v * 0.5, 0.25) +
         _triangle(523, 0.15, v * 0.6))
    _write_wav(os.path.join(_sfx_dir, "stage.wav"), s)
    _sfx_cache["stage"] = os.path.join(_sfx_dir, "stage.wav")

    # Completion: victory jingle (C5→E5→G5→C6, bright + long)
    s = (_triangle(523, 0.08, v * 0.5) +
         _triangle(659, 0.08, v * 0.55) +
         _triangle(784, 0.08, v * 0.6) +
         _triangle(1047, 0.2, v * 0.7))
    _write_wav(os.path.join(_sfx_dir, "complete.wav"), s)
    _sfx_cache["complete"] = os.path.join(_sfx_dir, "complete.wav")

    # Browser: navigation ping (D5 → A5, bright web feel)
    s = _triangle(587, 0.06, v * 0.45) + _triangle(880, 0.08, v * 0.5)
    _write_wav(os.path.join(_sfx_dir, "browser.wav"), s)
    _sfx_cache["browser"] = os.path.join(_sfx_dir, "browser.wav")

    # Generic tool: single blip
    s = _triangle(659, 0.06, v * 0.35)
    _write_wav(os.path.join(_sfx_dir, "blip.wav"), s)
    _sfx_cache["blip"] = os.path.join(_sfx_dir, "blip.wav")


def _play_sfx(event_type: str):
    """Play sound effect non-blocking. Respects cooldown."""
    global _last_sfx_time
    if NO_SOUND:
        return
    now = time.monotonic()
    if now - _last_sfx_time < SFX_COOLDOWN:
        return
    _last_sfx_time = now
    wav = _sfx_cache.get(event_type)
    if wav and os.path.exists(wav):
        try:
            subprocess.Popen(
                ["afplay", "-v", str(SFX_VOLUME), wav],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass


def _sfx_for_tool(name: str) -> str:
    """Map tool name to sound effect type."""
    if name == "Read":
        return "read"
    elif name in ("Write", "Edit"):
        return "write"
    elif name == "Bash":
        return "bash"
    elif name in ("Glob", "Grep"):
        return "search"
    elif name in ("WebSearch", "WebFetch"):
        return "web"
    elif name.startswith("Browser"):
        return "browser"
    elif name == "Task":
        return "agent"
    elif name == "Skill":
        return "skill"
    elif name.startswith("mcp__"):
        return "mcp"
    else:
        return "blip"


def _cleanup_sfx():
    """Remove temp sound files."""
    if _sfx_dir and os.path.isdir(_sfx_dir):
        import shutil as _sh
        _sh.rmtree(_sfx_dir, ignore_errors=True)


# ═══════════════════════════════════════════════
# Formatting
# ═══════════════════════════════════════════════

# Track state
_last_was_tool = False
_last_was_text = False


def short_path(path: str) -> str:
    """Shorten path: replace home, truncate middle if too long."""
    path = path.replace(HOME, "~")
    max_len = COLS - 20
    if len(path) > max_len and max_len > 30:
        return path[:15] + "..." + path[-(max_len - 18):]
    return path


def tool_icon(name: str) -> str:
    """Get icon for tool name."""
    if name.startswith("mcp__"):
        return ICONS.get("mcp", f"{DIM}--{RESET}")
    return ICONS.get(name, f"{DIM}--{RESET}")


def short_tool_name(name: str) -> str:
    """Shorten MCP tool names: mcp__solopreneur__kb_search → kb_search."""
    if name.startswith("mcp__"):
        parts = name.split("__")
        return parts[-1] if len(parts) > 1 else name
    return name


def format_tool_line(name: str, inp: dict) -> str:
    """Format a tool call as a single colored line."""
    icon = tool_icon(name)
    short = short_tool_name(name)

    if name in ("Read", "Write", "Edit"):
        path = short_path(inp.get("file_path", ""))
        return f"  {icon} {CYAN}{short}{RESET} {DIM}{path}{RESET}"

    elif name == "Bash":
        cmd = inp.get("command", "")
        desc = inp.get("description", "")
        display = desc if desc else cmd
        if len(display) > COLS - 20:
            display = display[:COLS - 23] + "..."
        return f"  {icon} {YELLOW}{short}{RESET} {DIM}{display}{RESET}"

    elif name in ("Glob", "Grep"):
        pat = inp.get("pattern", "")
        path = short_path(inp.get("path", ""))
        detail = f'"{pat}"'
        if path:
            detail += f" {path}"
        return f"  {icon} {CYAN}{short}{RESET} {DIM}{detail}{RESET}"

    elif name == "WebSearch":
        query = inp.get("query", "")
        return f"  {icon} {GREEN}{short}{RESET} {DIM}{query}{RESET}"

    elif name == "WebFetch":
        url = inp.get("url", "")[:80]
        return f"  {icon} {GREEN}{short}{RESET} {DIM}{url}{RESET}"

    elif name.startswith("Browser"):
        url = inp.get("url", inp.get("selector", inp.get("text", "")))
        if len(url) > COLS - 30:
            url = url[:COLS - 33] + "..."
        return f"  {icon} {GREEN}{short}{RESET} {DIM}{url}{RESET}"

    elif name == "Task":
        desc = inp.get("description", "")
        agent = inp.get("subagent_type", "")
        detail = f"[{agent}] {desc}" if agent else desc
        return f"  {icon} {MAGENTA}{short}{RESET} {DIM}{detail}{RESET}"

    elif name == "Skill":
        skill = inp.get("skill", "")
        return f"  {icon} {MAGENTA}{skill}{RESET}"

    elif name.startswith("mcp__"):
        # MCP tool — show tool name + first meaningful value
        first_val = ""
        for k, v in inp.items():
            if v and isinstance(v, str) and len(v) > 2:
                first_val = v[:80]
                break
        return f"  {icon} {BLUE}{short}{RESET} {DIM}{first_val}{RESET}"

    else:
        first_val = next((str(v)[:60] for v in inp.values() if v), "")
        return f"  {DIM}--{RESET} {CYAN}{short}{RESET} {DIM}{first_val}{RESET}"


def emit_tool(name: str, inp: dict):
    """Print a tool call line + play sound."""
    global _last_was_tool, _last_was_text
    if _last_was_text:
        print(flush=True)  # newline after text block
    line = format_tool_line(name, inp)
    print(line, flush=True)
    _play_sfx(_sfx_for_tool(name))
    _last_was_tool = True
    _last_was_text = False


def emit_text(text: str):
    """Print text content."""
    global _last_was_tool, _last_was_text
    if _last_was_tool and text.strip():
        print(flush=True)  # blank line after tools before text
    print(text, end="", flush=True)
    if text.strip():
        _last_was_text = True
        _last_was_tool = False


def main():
    # Generate sound effects at startup
    if not NO_SOUND:
        try:
            _generate_all_sfx()
        except Exception:
            pass  # sound is optional

    _play_sfx("stage")  # opening sound

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            print(line, flush=True)
            continue

        etype = event.get("type", "")

        if etype == "assistant":
            msg = event.get("message", {})
            for block in msg.get("content", []):
                btype = block.get("type", "")
                if btype == "tool_use":
                    emit_tool(block.get("name", "?"), block.get("input", {}))
                elif btype == "text":
                    text = block.get("text", "")
                    if text:
                        emit_text(text)

        elif etype == "result":
            # Final result text
            result = event.get("result", "")
            if isinstance(result, str) and result.strip():
                emit_text(result)
            # Check nested content
            for block in event.get("content", []):
                if block.get("type") == "text":
                    emit_text(block.get("text", ""))
            _play_sfx("complete")  # completion sound

        elif etype == "content_block_start":
            block = event.get("content_block", {})
            if block.get("type") == "tool_use":
                name = block.get("name", "?")
                inp = block.get("input", {})
                if inp:
                    emit_tool(name, inp)
                # If no input yet, we'll see it in deltas

        elif etype == "content_block_delta":
            delta = event.get("delta", {})
            if delta.get("type") == "text_delta":
                emit_text(delta.get("text", ""))

        elif etype == "error":
            err = event.get("error", {})
            msg = err.get("message", str(err))
            print(f"\n  {RED}!! Error: {msg}{RESET}", flush=True)
            _play_sfx("error")

        elif etype == "system":
            msg = event.get("message", "")
            subtype = event.get("subtype", "")
            if subtype == "init":
                session = event.get("session_id", "")[:8]
                model = event.get("model", "")
                if model or session:
                    print(f"  {DIM}session: {session}  model: {model}{RESET}", flush=True)

    # Final newline
    print(flush=True)
    _play_sfx("complete")

    # Cleanup temp files
    _cleanup_sfx()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        _cleanup_sfx()
        sys.exit(0)
    except BrokenPipeError:
        _cleanup_sfx()
        sys.exit(0)
