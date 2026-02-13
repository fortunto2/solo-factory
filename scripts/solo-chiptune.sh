#!/bin/bash

# Solo Chiptune — 8-bit background music for pipeline runs
# Primary: ChucK (picks random .ck theme from scripts/chiptune/)
# Fallback: Python wave + afplay (if chuck not installed)
#
# Usage:
#   solo-chiptune.sh start [--volume 0.15]   # start background music
#   solo-chiptune.sh stop                     # stop music
#   solo-chiptune.sh status                   # check if playing

set -euo pipefail

PIDFILE="/tmp/solo-chiptune.pid"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THEMES_DIR="$SCRIPT_DIR/chiptune"

CMD="${1:-start}"
shift || true

# Parse options
VOLUME=0.15

while [[ $# -gt 0 ]]; do
  case "$1" in
    --volume) VOLUME="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Pick random .ck theme from chiptune/ directory
pick_theme() {
  local themes=()
  for f in "$THEMES_DIR"/*.ck; do
    [[ -f "$f" ]] && themes+=("$f")
  done
  if [[ ${#themes[@]} -eq 0 ]]; then
    echo ""
    return
  fi
  local idx=$(( RANDOM % ${#themes[@]} ))
  echo "${themes[$idx]}"
}

case "$CMD" in
  start)
    # Stop existing
    if [[ -f "$PIDFILE" ]]; then
      OLD_PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
      if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Chiptune already playing (pid $OLD_PID). Use: solo-chiptune.sh stop"
        exit 0
      fi
      rm -f "$PIDFILE"
    fi

    # Try ChucK first
    if command -v chuck &>/dev/null; then
      THEME=$(pick_theme)
      if [[ -n "$THEME" ]]; then
        THEME_NAME=$(basename "$THEME" .ck)
        # Pass volume as ChucK argument (parsed via me.arg(0) in .ck files)
        chuck "$THEME":"$VOLUME" &>/dev/null &
        PLAY_PID=$!
        echo "$PLAY_PID" > "$PIDFILE"
        echo "Chiptune started: $THEME_NAME (pid $PLAY_PID, chuck)"
        exit 0
      fi
    fi

    # Fallback: Python wave + afplay
    WAVFILE="/tmp/solo-chiptune.wav"
    python3 - "$VOLUME" "$WAVFILE" << 'PYEOF'
import wave, struct, math, random, sys, os

volume = float(sys.argv[1]) if len(sys.argv) > 1 else 0.15
wav_path = sys.argv[2] if len(sys.argv) > 2 else "/tmp/solo-chiptune.wav"
sample_rate = 22050
bpm = 140
beat = 60.0 / bpm

NOTES = {
    'C3': 131, 'D3': 147, 'E3': 165, 'G3': 196, 'A3': 220,
    'C4': 262, 'D4': 294, 'E4': 330, 'G4': 392, 'A4': 440,
    'C5': 523, 'D5': 587, 'E5': 659, 'G5': 784, 'A5': 880,
    '_': 0,
}

def square_wave(freq, duration, vol=1.0, duty=0.5):
    samples = []
    n = int(sample_rate * duration)
    for i in range(n):
        if freq == 0:
            samples.append(0)
        else:
            t = i / sample_rate
            phase = (t * freq) % 1.0
            val = vol if phase < duty else -vol
            env = min(1.0, i / (sample_rate * 0.005))
            tail = max(0.0, 1.0 - (i / n) * 0.3)
            samples.append(val * env * tail)
    return samples

def noise_hit(duration, vol=0.5):
    samples = []
    n = int(sample_rate * duration)
    for i in range(n):
        env = max(0, 1.0 - (i / n) * 4)
        samples.append(random.uniform(-vol, vol) * env)
    return samples

patterns = [
    ['C4','E4','G4','C5', 'A4','E4','G4','_', 'D4','G4','A4','D5', 'C5','G4','E4','_'],
    ['E4','G4','A4','G4', 'E4','C4','D4','_', 'G4','A4','C5','A4', 'G4','E4','D4','_'],
    ['C4','C4','E4','G4', 'A4','G4','E4','D4', 'C4','D4','E4','G4', 'A4','C5','A4','G4'],
]
bass_patterns = [
    ['C3','_','C3','_', 'G3','_','G3','_', 'A3','_','A3','_', 'E3','_','E3','_'],
    ['C3','C3','_','C3', 'G3','G3','_','G3', 'A3','A3','_','A3', 'E3','E3','_','E3'],
]
drum_pattern = [1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0]

melody = random.choice(patterns)
bass = random.choice(bass_patterns)
note_dur = beat * 0.25
all_samples = []

for bar in range(8):
    for i, note_name in enumerate(melody):
        idx = i % len(melody)
        freq = NOTES.get(note_name, 0)
        mel = square_wave(freq, note_dur, vol=volume * 0.6, duty=0.25)
        bass_freq = NOTES.get(bass[idx % len(bass)], 0)
        bas = square_wave(bass_freq, note_dur, vol=volume * 0.4, duty=0.5)
        drm = noise_hit(note_dur, vol=volume * 0.2) if drum_pattern[idx % len(drum_pattern)] else [0] * len(mel)
        for j in range(len(mel)):
            mixed = mel[j] + (bas[j] if j < len(bas) else 0) + (drm[j] if j < len(drm) else 0)
            all_samples.append(max(-0.95, min(0.95, mixed)))

with wave.open(wav_path, 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sample_rate)
    for s in all_samples:
        w.writeframes(struct.pack('<h', int(s * 32767)))
print(f"Generated {len(all_samples)/sample_rate:.1f}s chiptune -> {wav_path}")
PYEOF

    set -m
    (while true; do afplay -v "$VOLUME" "$WAVFILE" 2>/dev/null; done) &
    PLAY_PID=$!
    echo "$PLAY_PID" > "$PIDFILE"
    echo "Chiptune started: fallback (pid $PLAY_PID, afplay)"
    ;;

  stop)
    if [[ -f "$PIDFILE" ]]; then
      PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
      if [[ -n "$PID" ]]; then
        # Kill ChucK or afplay process group
        kill -- -"$PID" 2>/dev/null || kill "$PID" 2>/dev/null || true
      fi
      rm -f "$PIDFILE"
    fi
    # Sweep orphans
    pkill -f "chuck.*chiptune/.*\\.ck" 2>/dev/null || true
    pkill -f "afplay.*solo-chiptune" 2>/dev/null || true
    echo "Chiptune stopped"
    ;;

  status)
    if [[ -f "$PIDFILE" ]]; then
      PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
      if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        echo "Playing (pid $PID)"
      else
        rm -f "$PIDFILE"
        echo "Not playing"
      fi
    else
      echo "Not playing"
    fi
    ;;

  *)
    echo "Usage: solo-chiptune.sh {start|stop|status} [--volume 0.15]"
    exit 1
    ;;
esac
