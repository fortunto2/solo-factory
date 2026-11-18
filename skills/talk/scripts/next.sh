#!/usr/bin/env bash
# Monitor source for attach mode: one line per finished turn (READY / TURN ...), from
# `voice_channel.py --http PORT`. Turns queue in that process, so re-arming loses nothing.
# Exits with a VOICE DOWN line when the voice process is gone (after 90 s of waiting at start).
port="${1:-7799}"
url="http://127.0.0.1:$port/next?timeout=25"
seen=0
start=$(date +%s)
while true; do
  if out=$(curl -s --max-time 60 "$url"); then
    seen=1
    if [ -n "$out" ]; then printf '%s\n' "$out"; fi
  elif [ "$seen" = 1 ] || [ $(($(date +%s) - start)) -gt 90 ]; then
    echo "VOICE DOWN: nothing answers on 127.0.0.1:$port"
    exit 1
  else
    sleep 1
  fi
done
