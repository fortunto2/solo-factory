#!/bin/bash

# Solo Chiptune — 8-bit background music for pipeline runs
# Zero deps: Python stdlib (wave) + macOS afplay
#
# Usage:
#   solo-chiptune.sh start [--volume 0.3] [--bpm 140]   # start background music
#   solo-chiptune.sh stop                                 # stop music
#   solo-chiptune.sh status                               # check if playing

set -euo pipefail

PIDFILE="/tmp/solo-chiptune.pid"
WAVFILE="/tmp/solo-chiptune.wav"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CMD="${1:-start}"
shift || true

# Parse options
VOLUME=0.15
BPM=140

while [[ $# -gt 0 ]]; do
  case "$1" in
    --volume) VOLUME="$2"; shift 2 ;;
    --bpm) BPM="$2"; shift 2 ;;
    *) shift ;;
  esac
done

generate_wav() {
  python3 << 'PYEOF'
import wave, struct, math, random, sys, os

sample_rate = 22050
volume = float(os.environ.get("CHIPTUNE_VOLUME", "0.3"))
bpm = int(os.environ.get("CHIPTUNE_BPM", "140"))
beat = 60.0 / bpm

# Note frequencies (Hz)
NOTES = {
    'C3': 131, 'D3': 147, 'E3': 165, 'G3': 196, 'A3': 220,
    'C4': 262, 'D4': 294, 'E4': 330, 'G4': 392, 'A4': 440,
    'C5': 523, 'D5': 587, 'E5': 659, 'G5': 784, 'A5': 880,
    '_': 0,  # rest
}

def square_wave(freq, duration, vol=1.0, duty=0.5):
    """Generate square wave samples."""
    samples = []
    n = int(sample_rate * duration)
    for i in range(n):
        if freq == 0:
            samples.append(0)
        else:
            t = i / sample_rate
            phase = (t * freq) % 1.0
            val = vol if phase < duty else -vol
            # Envelope: quick attack, gentle decay
            env = min(1.0, i / (sample_rate * 0.005))  # 5ms attack
            tail = max(0.0, 1.0 - (i / n) * 0.3)       # gentle fade
            samples.append(val * env * tail)
    return samples

def noise_hit(duration, vol=0.5):
    """Percussive noise for rhythm."""
    samples = []
    n = int(sample_rate * duration)
    for i in range(n):
        env = max(0, 1.0 - (i / n) * 4)  # fast decay
        samples.append(random.uniform(-vol, vol) * env)
    return samples

# ── Melodic patterns (pentatonic, chiptune-style) ──
patterns = [
    # Pattern 1: Uplifting arpeggio
    ['C4','E4','G4','C5', 'A4','E4','G4','_',
     'D4','G4','A4','D5', 'C5','G4','E4','_'],
    # Pattern 2: Bouncy
    ['E4','G4','A4','G4', 'E4','C4','D4','_',
     'G4','A4','C5','A4', 'G4','E4','D4','_'],
    # Pattern 3: Driving
    ['C4','C4','E4','G4', 'A4','G4','E4','D4',
     'C4','D4','E4','G4', 'A4','C5','A4','G4'],
]

# ── Bass patterns ──
bass_patterns = [
    ['C3','_','C3','_', 'G3','_','G3','_',
     'A3','_','A3','_', 'E3','_','E3','_'],
    ['C3','C3','_','C3', 'G3','G3','_','G3',
     'A3','A3','_','A3', 'E3','E3','_','E3'],
]

# ── Drum pattern (noise hits on beats) ──
drum_pattern = [1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0]

# Pick random patterns
melody = random.choice(patterns)
bass = random.choice(bass_patterns)

# Generate 4 bars (loop will repeat this)
note_dur = beat * 0.25  # 16th notes
all_samples = []
bars = 8

for bar in range(bars):
    for i, note_name in enumerate(melody):
        idx = i % len(melody)
        # Melody
        freq = NOTES.get(note_name, 0)
        mel = square_wave(freq, note_dur, vol=volume * 0.6, duty=0.25)

        # Bass
        bass_name = bass[idx % len(bass)]
        bass_freq = NOTES.get(bass_name, 0)
        bas = square_wave(bass_freq, note_dur, vol=volume * 0.4, duty=0.5)

        # Drums
        drm = noise_hit(note_dur, vol=volume * 0.2) if drum_pattern[idx % len(drum_pattern)] else [0] * len(mel)

        # Mix
        for j in range(len(mel)):
            mixed = mel[j]
            if j < len(bas):
                mixed += bas[j]
            if j < len(drm):
                mixed += drm[j]
            mixed = max(-0.95, min(0.95, mixed))
            all_samples.append(mixed)

# Write WAV
wav_path = os.environ.get("CHIPTUNE_WAV", "/tmp/solo-chiptune.wav")
with wave.open(wav_path, 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sample_rate)
    for s in all_samples:
        w.writeframes(struct.pack('<h', int(s * 32767)))

dur = len(all_samples) / sample_rate
print(f"Generated {dur:.1f}s chiptune at {bpm} BPM -> {wav_path}")
PYEOF
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

    # Generate new WAV
    CHIPTUNE_VOLUME="$VOLUME" CHIPTUNE_BPM="$BPM" CHIPTUNE_WAV="$WAVFILE" generate_wav

    # Play in background (bash loop — afplay has no --loops flag)
    set -m  # enable job control for process groups
    (while true; do afplay -v "$VOLUME" "$WAVFILE" 2>/dev/null; done) &
    PLAY_PID=$!
    echo "$PLAY_PID" > "$PIDFILE"
    echo "🎵 Chiptune started (pid $PLAY_PID, volume $VOLUME, $BPM bpm)"
    ;;

  stop)
    if [[ -f "$PIDFILE" ]]; then
      PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
      if [[ -n "$PID" ]]; then
        # Kill process group (subshell + afplay children)
        kill -- -"$PID" 2>/dev/null || kill "$PID" 2>/dev/null || true
      fi
      rm -f "$PIDFILE"
    fi
    # Always sweep orphaned afplay on solo-chiptune.wav
    pkill -f "afplay.*solo-chiptune" 2>/dev/null || true
    echo "🔇 Chiptune stopped"
    ;;

  status)
    if [[ -f "$PIDFILE" ]]; then
      PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
      if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        echo "🎵 Playing (pid $PID)"
      else
        rm -f "$PIDFILE"
        echo "🔇 Not playing"
      fi
    else
      echo "🔇 Not playing"
    fi
    ;;

  *)
    echo "Usage: solo-chiptune.sh {start|stop|status} [--volume 0.3] [--bpm 140]"
    exit 1
    ;;
esac
