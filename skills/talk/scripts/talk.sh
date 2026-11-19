#!/usr/bin/env bash
# Open a Claude Code session you can talk to: the `voice` channel (mic, smart-turn, ASR, TTS)
# starts with it as an MCP server and stops when the session ends.
#
#   talk.sh                                    # Russian ASR (GigaAM), the designed voice
#   talk.sh -- --asr parakeet --ref ~/me.wav   # after `--`: voice_channel.py options
#   talk.sh --resume <id> -- --barge-in        # before `--`: claude options
#   talk.sh --supervox                         # also load the supervox live-transcript channel
#
# Custom channels are not on the research-preview allowlist, so claude shows a confirmation
# screen for --dangerously-load-development-channels on every start.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
claude_args=()
voice_args=()
after=0
supervox=0
for arg in "$@"; do
  if [ "$after" = 0 ] && [ "$arg" = "--" ]; then
    after=1
  elif [ "$after" = 0 ] && [ "$arg" = "--supervox" ]; then
    supervox=1
  elif [ "$after" = 0 ]; then
    claude_args+=("$arg")
  else
    voice_args+=("$arg")
  fi
done

uv_bin="$(command -v uv)" || { echo "uv is not on PATH: https://docs.astral.sh/uv/" >&2; exit 1; }
cfg="${XDG_CACHE_HOME:-$HOME/.cache}/solo-tts/talk-mcp.json"
mkdir -p "$(dirname "$cfg")"
python3 - "$cfg" "$uv_bin" "$here/voice_channel.py" "$supervox" "$here/../../supervox/scripts/supervox_channel.py" "${voice_args[@]+"${voice_args[@]}"}" <<'PY'
import json, sys
cfg, uv, script, sv, sv_script, *extra = sys.argv[1:]
servers = {"voice": {"command": uv, "args": ["run", "--script", script, *extra]}}
if sv == "1":
    servers["supervox"] = {"command": uv, "args": ["run", "--script", sv_script]}
with open(cfg, "w") as f:
    json.dump({"mcpServers": servers}, f, indent=2)
PY

channels=(server:voice)
[ "$supervox" = 1 ] && channels+=(server:supervox)
exec claude --mcp-config "$cfg" --dangerously-load-development-channels "${channels[@]}" \
  "${claude_args[@]+"${claude_args[@]}"}"
