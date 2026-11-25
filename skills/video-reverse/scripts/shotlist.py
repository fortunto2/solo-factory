#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""VIDEO.md timeline -> a shot-list table in the solo:ad-video format.

Reads <breakdown>/video/timeline.md (the ```videomd-timeline block) and prints a
markdown table: shot, seconds, source (real / render / generated), what is seen,
camera, overlays, flags. Direction and Caption are left blank: they are the
remaker's decisions, not the original's.

Usage: shotlist.py out/ref [--beats-bpm 100]
"""

import argparse
import re
import sys
from pathlib import Path

SOURCE = {
    "live action": "real",
    "live_action": "real",
    "screen recording": "real",
    "3d render": "render",
    "code / template render": "render",
    "2d animation": "render",
    "ai-generated video": "generated",
    "avatar": "generated",
}


def parse(text: str) -> list[dict]:
    m = re.search(r"```videomd-timeline\n(.*?)```", text, re.S)
    if not m:
        sys.exit("no videomd-timeline block: is this a rea-video output directory?")
    rows = []
    for line in m.group(1).splitlines():
        head = re.match(r"#(\d+)\s+([\d.]+)-([\d.]+)\s*(.*)", line.strip())
        if not head:
            continue
        row = {
            "n": int(head.group(1)),
            "start": float(head.group(2)),
            "end": float(head.group(3)),
        }
        for part in head.group(4).split("|"):
            part = part.strip()
            if part:
                key, _, val = part.partition(" ")
                row[key.rstrip("~")] = val.strip()
        rows.append(row)
    return rows


def source_of(made: str) -> str:
    label = re.split(r"\s+\d+%", made)[0].strip().lower()
    return SOURCE.get(label, label or "?")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("out_dir", help="rea-video output directory (holds VIDEO.md)")
    ap.add_argument(
        "--beats-bpm", type=float, help="fill the Beats column at this tempo"
    )
    args = ap.parse_args()
    rows = parse((Path(args.out_dir) / "video" / "timeline.md").read_text())
    print(
        "| # | Beats | Seconds | Source | Direction | What the viewer sees | Caption | Note |"
    )
    print("|---|---|---|---|---|---|---|---|")
    for r in rows:
        secs = r["end"] - r["start"]
        beats = f"{secs / (60 / args.beats_bpm):.1f}" if args.beats_bpm else ""
        seen = r.get("seen", r.get("story", ""))
        note = " ".join(
            x
            for x in (r.get("camera", ""), r.get("overlay", ""), r.get("flag", ""))
            if x
        )
        print(
            f"| {r['n']} | {beats} | {secs:.1f} | {source_of(r.get('made', ''))} | | {seen} | | {note} |"
        )


if __name__ == "__main__":
    main()
