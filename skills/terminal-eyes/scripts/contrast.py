#!/usr/bin/env python3
"""Check a terminal palette against its own background (WCAG contrast ratio).

    python3 contrast.py --palette theme-light.conf
    python3 contrast.py --bg '#dfdbc3' --palette theme.conf
    python3 contrast.py --bg '#dfdbc3' '#7d5209' '#1f6a6a'

Reads kitty-style `.conf` (background / color0..color15) or bare hex arguments.
Normal colors want >=4.5:1, bright ones >=3.5:1 (they carry bold text).
"""

import argparse
import re
import sys


def lum(hex_color):
    h = hex_color.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    parts = []
    for i in (0, 2, 4):
        c = int(h[i : i + 2], 16) / 255
        parts.append(c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4)
    r, g, b = parts
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def parse_conf(path):
    bg, colors = None, {}
    for line in open(path):
        line = line.strip()
        if line.startswith("#"):  # kitty comments are whole lines; colors start with #
            continue
        m = re.match(
            r"^(background|foreground|color(\d+))\s+(#[0-9a-fA-F]{3,6})$", line
        )
        if not m:
            continue
        if m.group(1) == "background":
            bg = m.group(3)
        else:
            colors[m.group(1)] = m.group(3)
    return bg, colors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bg")
    ap.add_argument("--palette")
    ap.add_argument("colors", nargs="*")
    a = ap.parse_args()

    colors = {}
    bg = a.bg
    if a.palette:
        conf_bg, colors = parse_conf(a.palette)
        bg = bg or conf_bg
    for i, c in enumerate(a.colors):
        colors[f"arg{i}"] = c
    if not bg or not colors:
        ap.error("need a background and at least one color")

    print(f"background {bg}\n")
    worst = []
    for name, c in colors.items():
        r = ratio(bg, c)
        # bright colors (8-15) carry bold text and get a lower floor
        m = re.fullmatch(r"color(\d+)", name)
        idx = int(m.group(1)) if m else None
        # color0 is the theme's own "background" shade by design — it is never text
        if idx == 0:
            print(f"  bg   {name:9} {c}  {r:5.2f}:1  (background shade, not checked)")
            continue
        floor = 3.5 if idx is not None and idx >= 8 else 4.5
        ok = r >= floor
        mark = "ok  " if ok else "LOW "
        print(f"  {mark} {name:9} {c}  {r:5.2f}:1  (floor {floor})")
        if not ok:
            worst.append((name, c, r, floor))

    if worst:
        print(f"\n{len(worst)} below floor:")
        for name, c, r, floor in worst:
            print(
                f"  {name} {c} is {r:.2f}:1, wants {floor}:1 — darken it on a light "
                f"ground, lighten it on a dark one"
            )
        sys.exit(1)
    print("\nall colors clear their floor")


if __name__ == "__main__":
    main()
