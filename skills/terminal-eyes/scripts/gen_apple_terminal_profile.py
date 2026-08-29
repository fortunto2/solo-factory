#!/usr/bin/env python3
"""Build an Apple Terminal .terminal profile from a kitty-style palette file.

    python3 gen_apple_terminal_profile.py \
        --palette ../references/configs/kitty-theme-light.conf \
        --name "Warm Light" --out "Warm Light.terminal"

Then import it — do NOT write the plist directly, Terminal.app rewrites its
settings on quit and your change is lost:

    open "Warm Light.terminal"
    osascript -e 'tell application "Terminal" to set default settings to settings set "Warm Light"'

Apple Terminal stores each color as an embedded NSKeyedArchiver blob, which is
why this needs a script rather than a text config.
"""

import argparse
import plistlib
import re
import sys

ANSI = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]


def archived_color(hex_color):
    h = hex_color.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = (int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return plistlib.dumps(
        {
            "$version": 100000,
            "$archiver": "NSKeyedArchiver",
            "$top": {"root": plistlib.UID(1)},
            "$objects": [
                "$null",
                {
                    "NSRGB": f"{r:.8g} {g:.8g} {b:.8g}".encode() + b"\x00",
                    "NSColorSpace": 2,
                    "$class": plistlib.UID(2),
                },
                {"$classname": "NSColor", "$classes": ["NSColor", "NSObject"]},
            ],
        },
        fmt=plistlib.FMT_BINARY,
    )


def archived_font(name, size):
    return plistlib.dumps(
        {
            "$version": 100000,
            "$archiver": "NSKeyedArchiver",
            "$top": {"root": plistlib.UID(1)},
            "$objects": [
                "$null",
                {
                    "NSSize": float(size),
                    "NSfFlags": 16,
                    "NSName": plistlib.UID(2),
                    "$class": plistlib.UID(3),
                },
                name,
                {"$classname": "NSFont", "$classes": ["NSFont", "NSObject"]},
            ],
        },
        fmt=plistlib.FMT_BINARY,
    )


def read_palette(path):
    """Parse background/foreground/cursor/selection_background/color0..15."""
    out = {}
    for line in open(path):
        line = line.strip()
        if line.startswith("#"):
            continue
        m = re.match(r"^(\w+)\s+(#[0-9a-fA-F]{3,6})$", line)
        if m:
            out[m.group(1)] = m.group(2)
    missing = [k for k in ("background", "foreground") if k not in out]
    if missing or any(f"color{i}" not in out for i in range(16)):
        sys.exit(f"{path}: need background, foreground and color0..color15")
    return out


def build(pal, name, font, size, cols, rows):
    fg, bg = pal["foreground"], pal["background"]
    p = {
        "name": name,
        "type": "Window Settings",
        "ProfileCurrentVersion": 2.09,
        "BackgroundColor": archived_color(bg),
        "TextColor": archived_color(fg),
        "TextBoldColor": archived_color(pal.get("color15", fg)),
        "CursorColor": archived_color(pal.get("cursor", fg)),
        "SelectionColor": archived_color(
            pal.get("selection_background", pal["color8"])
        ),
        "Font": archived_font(font, size),
        "FontAntialias": True,
        "FontHeightSpacing": 1.2,
        "FontWidthSpacing": 1.0,
        # nothing moves
        "BlinkText": False,
        "CursorBlink": False,
        "CursorType": 0,
        # a bell that marks the tab and bounces the Dock icon, silently
        "Bell": False,
        "VisualBell": False,
        "VisualBellOnlyWhenMuted": False,
        "BellBadge": True,
        "BellBounce": True,
        # without this, Option-key shortcuts in TUIs are dead
        "useOptionAsMetaKey": True,
        "ShouldLimitScrollback": 0,
        "ScrollbackLines": 20000,
        "ShowWindowSettingsNameInTitle": False,
        "ShowActivityIndicatorInTab": True,
        "columnCount": cols,
        "rowCount": rows,
        # bold via font weight, not via bright colors — those burn contrast
        "UseBrightBold": False,
    }
    for i, key in enumerate(ANSI):
        p[f"ANSI{key}Color"] = archived_color(pal[f"color{i}"])
        p[f"ANSIBright{key}Color"] = archived_color(pal[f"color{i + 8}"])
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--palette", required=True, help="kitty-style .conf")
    ap.add_argument("--name", required=True, help="profile name shown in Terminal")
    ap.add_argument("--out", help="output path (default: <name>.terminal)")
    ap.add_argument(
        "--font", default="JetBrainsMono-Regular", help="PostScript font name"
    )
    ap.add_argument("--size", type=float, default=14)
    ap.add_argument("--cols", type=int, default=132)
    ap.add_argument("--rows", type=int, default=40)
    a = ap.parse_args()

    prof = build(read_palette(a.palette), a.name, a.font, a.size, a.cols, a.rows)
    out = a.out or f"{a.name}.terminal"
    with open(out, "wb") as f:
        plistlib.dump(prof, f, fmt=plistlib.FMT_XML)
    print(f"wrote {out}\nimport it:  open '{out}'")


if __name__ == "__main__":
    main()
