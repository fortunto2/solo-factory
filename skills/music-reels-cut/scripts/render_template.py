#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""music-reels-cut render template — beat-synced reels/shorts cut.

Pipeline (see SKILL.md for full recipe):
  1. node beats.mjs <audio> > beats.json   (scripts/beats.mjs in this skill; npm i life2film-engine)
  2. Probe source video, extract preview frames, classify into INTIMATE/WIDE/TEXTURE
  3. Edit `# EDIT:` lines below
  4. Run: ./render.py
  5. Sample output frames at section boundaries

Density presets: chill (1s/0.5s) | medium (0.5s/0.25s, default) | wild (0.25s/0.125s)
"""

import json
import subprocess
import sys
from pathlib import Path

# EDIT: paths
HERE = Path(__file__).resolve().parent
SRC_VIDEO = "/path/to/source-video.mov"  # any aspect; will be scaled to 1080x1920
SRC_AUDIO = "/path/to/audio-track.mp3"
OUT = HERE / "output_clip.mp4"
FILTER_FILE = HERE / "filter.txt"
BEATS_JSON = HERE / "beats.json"  # produced by beats.mjs

beats_data = json.loads(BEATS_JSON.read_text())
DOWNBEATS = beats_data["downbeats"]
SECTIONS = beats_data["sections"]
print(
    f"loaded {len(beats_data['beats'])} beats, {len(DOWNBEATS)} downbeats, bpm={beats_data['bpm']:.1f}"
)
for s in SECTIONS:
    print(
        f"  {s['start']:6.2f} - {s['end']:6.2f}  {s['label']:8s}  E={s['mean_energy']:.2f}"
    )

# EDIT: source frame pools — timestamps (seconds) inside SRC_VIDEO, grouped by mood.
# Extract previews first: for t in 5 20 40 60 80 100; do
#   ffmpeg -y -ss $t -i "$SRC_VIDEO" -vframes 1 -vf scale=320:-1 /tmp/probe_${t}s.jpg
# done — then Read each and assign timestamps to the right pool.
INTIMATE = [3.0, 5.0, 7.0, 33.0, 35.0, 37.0, 39.0, 41.0, 43.0]
WIDE = [14.0, 16.0, 22.0, 50.0, 55.0, 60.0, 70.0, 78.0, 82.0]
TEXTURE = [88.0, 92.0, 96.0, 100.0, 104.0]

# Backwards-compat aliases for the section-assembly loop below
INTERIOR = INTIMATE
BEACH = WIDE
WAVES = TEXTURE

VERSE_INTIMATE_FX = [
    "MIRROR_H",
    "INTIMATE_DARK",
    "MIRROR_H",
    "DBL_MIRROR",
    "INTIMATE_DARK",
    "MIRROR_H",
]
VERSE_SOFT_FX = [
    "WATER",
    "WATER_HUE",
    "MIRROR_H",
    "DBL_MIRROR_HUE",
    "WATER",
    "DBL_MIRROR",
    "WATER_HUE",
]
CHORUS_FX = [
    "KALEIDO_RGB",
    "KALEIDO",
    "TILE3X3",
    "CHROMA",
    "INVERT",
    "KALEIDO_RGB",
    "TILE3X3",
    "KALEIDO",
]
PEAK_FX = [
    "KALEIDO_RGB",
    "TILE3X3",
    "INVERT",
    "KALEIDO_RGB",
    "KALEIDO",
    "CHROMA",
    "KALEIDO_RGB",
    "TILE3X3",
]
BUILD_FX = ["CHROMA", "FLASH_WHITE", "PIXEL_CHROMA", "CHROMA", "KALEIDO_RGB"]


def near_downbeat(t: float, eps: float = 0.12) -> bool:
    return any(abs(t - db) < eps for db in DOWNBEATS)


def gen_section(start: float, end: float, cut_dur: float, fx_pool, src_pool, snap=True):
    """Yield (out_s, dur, src_s, fx) tiles covering [start, end). Last tile may be short."""
    t = start
    idx = 0
    out = []
    while t < end - 0.001:
        dur = min(cut_dur, end - t)
        if dur < 0.12:
            break
        fx = fx_pool[idx % len(fx_pool)]
        if snap and near_downbeat(t):
            fx = "FLASH_WHITE"  # snap accent on downbeat
        src = src_pool[(idx * 7) % len(src_pool)]  # shuffle via stride
        out.append((round(t, 3), round(dur, 3), src, fx))
        t += cut_dur
        idx += 1
    return out


# EDIT: density preset
DENSITY = "medium"  # "chill" | "medium" | "wild"
DURS = {
    "chill": {"verse": 1.0, "chorus": 0.5, "peak": 0.5},
    "medium": {"verse": 0.5, "chorus": 0.25, "peak": 0.25},
    "wild": {"verse": 0.25, "chorus": 0.25, "peak": 0.125},  # near subliminal
}[DENSITY]

# Reserve intro (first ~2 beats) and outro (last 2s) for fades
intro_end = min(2.020, SECTIONS[0]["end"]) if SECTIONS else 2.0
outro_start = round(max(s["end"] for s in SECTIONS) - 2.035, 3)

cuts = []
cuts.append((0.0, intro_end, INTIMATE[0], "INTRO_FADE"))

# Auto-assemble cuts from detected SECTIONS (verse=mirror/water; chorus=kaleido;
# peak=max chaos; energy > 0.99 → peak treatment)
for sec in SECTIONS:
    s_start = max(sec["start"], intro_end)
    s_end = min(sec["end"], outro_start)
    if s_end <= s_start + 0.1:
        continue
    if sec["label"] == "verse":
        # E<0.45 → soft (water); E≥0.45 → intimate (mirror)
        soft = sec["mean_energy"] < 0.45
        pool = VERSE_SOFT_FX if soft else VERSE_INTIMATE_FX
        src_pool = (WIDE + INTIMATE) if soft else INTIMATE
        cuts += gen_section(s_start, s_end, DURS["verse"], pool, src_pool, snap=True)
    else:  # chorus
        is_peak = sec["mean_energy"] >= 0.99
        cut_dur = DURS["peak"] if is_peak else DURS["chorus"]
        pool = PEAK_FX if is_peak else CHORUS_FX
        src_pool = (WIDE + TEXTURE + INTIMATE[3:]) if is_peak else (WIDE + TEXTURE)
        cuts += gen_section(s_start, s_end, cut_dur, pool, src_pool, snap=True)

cuts.append((outro_start, 2.035, INTIMATE[0], "OUTRO_FADE"))

# Re-tile so cuts join exactly (next start - this start = this dur)
fixed = []
for i, (_s, d, src, fx) in enumerate(cuts):
    next_s = cuts[i + 1][0] if i + 1 < len(cuts) else s + d
    real_dur = round(next_s - s, 3) if i + 1 < len(cuts) else d
    if real_dur < 0.08:
        continue  # skip impossibly short
    fixed.append((s, real_dur, src, fx))
cuts = fixed

total = cuts[-1][0] + cuts[-1][1]
print(f"# cuts: {len(cuts)}, total: {total:.3f}s")


# ---- Effect chain templates (port of render_v3.sh emit_chain) ----
def chain(idx: int, ss: float, dur: float, fx: str) -> str:
    end = round(ss + dur, 4)
    trim = f"[0:v]trim={ss}:{end},setpts=PTS-STARTPTS,scale=1080:1920,fps=30"
    common_end = f",setsar=1,format=yuv420p[c{idx}];\n"
    if fx == "INTRO_FADE":
        return f"{trim},fade=t=in:st=0:d=1.2:color=black,eq=brightness=-0.12:saturation=0.55:contrast=1.15{common_end}"
    if fx == "OUTRO_FADE":
        fade_d = round(dur - 0.5, 3)
        return f"{trim},rgbashift=rh=30:gh=-24:bv=20,fade=t=out:st=0.5:d={fade_d}:color=black{common_end}"
    if fx == "INTIMATE_DARK":
        return f"{trim},eq=brightness=-0.10:saturation=0.7:contrast=1.18{common_end}"
    if fx == "FLASH_WHITE":
        return f"{trim},eq=brightness=0.4:saturation=0.3:contrast=0.8{common_end}"
    if fx == "MIRROR_H":
        return (
            f"{trim},crop=iw/2:ih:0:0,split[Lm{idx}][Rm{idx}];"
            f"[Rm{idx}]hflip[Rmf{idx}];"
            f"[Lm{idx}][Rmf{idx}]hstack=inputs=2,scale=1080:1920,"
            f"eq=brightness=-0.05:saturation=0.75:contrast=1.2{common_end}"
        )
    if fx == "DBL_MIRROR":
        return (
            f"{trim},split[Da{idx}][Db{idx}];"
            f"[Db{idx}]hflip,vflip,format=yuva420p,colorchannelmixer=aa=0.48[Dov{idx}];"
            f"[Da{idx}][Dov{idx}]overlay=0:0,eq=contrast=1.2:saturation=1.15{common_end}"
        )
    if fx == "DBL_MIRROR_HUE":
        return (
            f"{trim},split[DHa{idx}][DHb{idx}];"
            f"[DHb{idx}]hflip,vflip,format=yuva420p,colorchannelmixer=aa=0.50[DHov{idx}];"
            f"[DHa{idx}][DHov{idx}]overlay=0:0,hue=h=195:s=1.35,eq=contrast=1.2:saturation=1.15{common_end}"
        )
    if fx == "KALEIDO":
        return (
            f"{trim},scale=540:960,split=4[K1{idx}][K2{idx}][K3{idx}][K4{idx}];"
            f"[K2{idx}]hflip[K2h{idx}];[K3{idx}]vflip[K3v{idx}];[K4{idx}]hflip,vflip[K4hv{idx}];"
            f"[K1{idx}][K2h{idx}]hstack=inputs=2[Kt{idx}];"
            f"[K3v{idx}][K4hv{idx}]hstack=inputs=2[Kb{idx}];"
            f"[Kt{idx}][Kb{idx}]vstack=inputs=2,scale=1080:1920,"
            f"eq=saturation=1.25:contrast=1.2{common_end}"
        )
    if fx == "KALEIDO_RGB":
        return (
            f"{trim},scale=540:960,split=4[KR1{idx}][KR2{idx}][KR3{idx}][KR4{idx}];"
            f"[KR2{idx}]hflip[KR2h{idx}];[KR3{idx}]vflip[KR3v{idx}];[KR4{idx}]hflip,vflip[KR4hv{idx}];"
            f"[KR1{idx}][KR2h{idx}]hstack=inputs=2[KRt{idx}];"
            f"[KR3v{idx}][KR4hv{idx}]hstack=inputs=2[KRb{idx}];"
            f"[KRt{idx}][KRb{idx}]vstack=inputs=2,scale=1080:1920,"
            f"rgbashift=rh=14:gh=-10:bv=8,noise=c0s=22:c0f=t+u,"
            f"eq=saturation=1.3:contrast=1.3{common_end}"
        )
    if fx == "TILE3X3":
        return (
            f"{trim},scale=360:640,split=9[T1{idx}][T2{idx}][T3{idx}][T4{idx}][T5{idx}][T6{idx}][T7{idx}][T8{idx}][T9{idx}];"
            f"[T1{idx}][T2{idx}][T3{idx}]hstack=inputs=3[TR1{idx}];"
            f"[T4{idx}][T5{idx}][T6{idx}]hstack=inputs=3[TR2{idx}];"
            f"[T7{idx}][T8{idx}][T9{idx}]hstack=inputs=3[TR3{idx}];"
            f"[TR1{idx}][TR2{idx}][TR3{idx}]vstack=inputs=3,scale=1080:1920,"
            f"eq=saturation=1.2:contrast=1.25,rgbashift=rh=8:gh=-6:bv=4{common_end}"
        )
    if fx == "CHROMA":
        return f"{trim},rgbashift=rh=20:gh=-15:bv=12,eq=saturation=1.1:contrast=1.15{common_end}"
    if fx == "INVERT":
        return f"{trim},negate,eq=saturation=0.85:contrast=1.05{common_end}"
    if fx == "WATER":
        return (
            f"{trim},scale=1080:1920,crop=1080:960:0:480,split[Wt{idx}][Wb{idx}];"
            f"[Wb{idx}]vflip,gblur=sigma=4,eq=brightness=-0.10:saturation=0.85[Wr{idx}];"
            f"[Wt{idx}][Wr{idx}]vstack=inputs=2,scale=1080:1920,eq=contrast=1.10{common_end}"
        )
    if fx == "WATER_HUE":
        return (
            f"{trim},scale=1080:1920,crop=1080:960:0:480,split[WHt{idx}][WHb{idx}];"
            f"[WHb{idx}]vflip,gblur=sigma=5,eq=brightness=-0.12:saturation=0.80[WHr{idx}];"
            f"[WHt{idx}][WHr{idx}]vstack=inputs=2,scale=1080:1920,"
            f"hue=h=210:s=1.1,eq=contrast=1.10{common_end}"
        )
    if fx == "PIXEL_CHROMA":
        return (
            f"{trim},rgbashift=rh=18:gh=-14:bv=10,scale=iw/8:ih/8,scale=1080:1920:flags=neighbor,"
            f"tmix=frames=4:weights='1 0.6 0.4 0.3',"
            f"eq=brightness=-0.05:contrast=1.4:saturation=0.9{common_end}"
        )
    raise SystemExit(f"unknown fx: {fx}")


# Write filter file
lines = []
for i, (_s, d, src, fx) in enumerate(cuts):
    lines.append(chain(i, src, d, fx))
labels = "".join(f"[c{i}]" for i in range(len(cuts)))
lines.append(f"{labels}concat=n={len(cuts)}:v=1:a=0[vout]\n")
FILTER_FILE.write_text("".join(lines))
print(f"→ filter: {FILTER_FILE.name}, {len(lines)} lines")

# Run ffmpeg
cmd = [
    "ffmpeg",
    "-y",
    "-i",
    SRC_VIDEO,
    "-i",
    SRC_AUDIO,
    "-filter_complex_script",
    str(FILTER_FILE),
    "-map",
    "[vout]",
    "-map",
    "1:a",
    "-c:v",
    "libx264",
    "-preset",
    "medium",
    "-crf",
    "21",
    "-pix_fmt",
    "yuv420p",
    "-c:a",
    "aac",
    "-b:a",
    "192k",
    "-t",
    str(round(total, 3)),
    "-movflags",
    "+faststart",
    str(OUT),
]
print("running ffmpeg...")
result = subprocess.run(cmd, stderr=subprocess.PIPE, stdout=subprocess.DEVNULL)
if result.returncode != 0:
    sys.stderr.write(result.stderr.decode()[-2000:])
    raise SystemExit(result.returncode)
print(f"✓ {OUT} ({OUT.stat().st_size / 1024 / 1024:.1f} MB)")
