#!/usr/bin/env python3
"""Build a layered `.icon` (Icon Composer) from a designer's SVG artboard.

An app icon on iOS 26+ is no longer a flattened PNG: it is a small bundle of
layers the system lights, tints and renders as Liquid Glass. Icon Composer
draws them by hand; this writes the same document from the artwork, so the icon
is regenerated rather than redrawn when the brand changes.

    make_icon.py --source brand/logo/mark-on-gradient.svg --icon App.icon --render

What the source has to be: **one artboard, already composed** — the mark laid
out on its tile, as outlines (not strokes), with the background gradient in a
`<linearGradient>`. Everything else is read from it: the stops, the viewBox,
the paths.

Rendering needs `ictool`, which ships inside Xcode:
`Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool`

The format's rules — all measured against `ictool`, none documented — are in
`references/icon-json.md`. Read that before changing anything here.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys

ICTOOL = pathlib.Path(
    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app"
    "/Contents/Executables/ictool"
)

CANVAS = 1024.0  # what an icon is drawn on

# The artwork is a **finished tile**, 1080 square: the designer already decided
# how much of it the mark takes and how much air is around it. Shrinking it to
# 72% was the obvious-looking mistake — that number is for a mark handed over on
# its own, and applying it to a laid-out tile shrinks the mark twice.
#
# 0.9 rather than 1.0 for one reason: **watchOS masks the tile to a circle**,
# and a circle eats the corners of a square's margin. At 1:1 the outer arcs ran
# to the very edge of the round preview. Nine tenths keeps the square generous
# and gives the circle the room it needs — the same proportion the brand deck
# itself uses when it puts the mark inside a round form
# (`brand/presentation/slide2-4.pdf`).
MARK_SPAN = 0.9

# Set from the command line in `main`; the drawing functions read them.
SOURCE = pathlib.Path()
ICON = pathlib.Path()

# Which of the source's five paths is which: the ring, the three arcs around
# it, the play triangle. `brand/mark/mark-rings.svg` is the mark alone — no
# background rectangle, because the layered format draws the background itself.
PATHS = {"ring": [0], "arcs": [1, 2, 3], "play": [4]}

# The source gradient, read from its own `<linearGradient>`: blue at the top
# right through pink and orange to yellow at the bottom left.
#
# **A layered icon's background takes exactly two colours** — ictool refuses
# more ("Linear gradients require exactly 2 colors"). Blue to yellow is a
# straight line through grey, so the pair has to be chosen rather than taken
# from the ends.
# Nothing here is chosen. The background gradient is read out of the source
# file's own `<linearGradient>` — see `source_gradient()`. Three stops, and the
# layered format takes two, so it is drawn as the **bottom layer** rather than
# as the document's `fill`: the middle stop is the whole point, because blue
# interpolated straight to orange passes through grey and pink is what the
# brand is remembered by. The two-colour `fill` beneath it is only what the
# system falls back to when it re-colours the icon (tinted, clear).


def colour(hex_string: str, alpha: float = 1.0) -> str:
    """`icon.json` wants `display-p3:r,g,b,a`, all four components.

    Undocumented; `ictool` was asked directly (`scripts/probe_icon_colour.py`).
    Three components fail with "Expected four comma separated color
    components", a bare hex with "missing ':' delimiter" — which names the
    delimiter and not the prefix.
    """
    h = hex_string.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return f"display-p3:{r:.4f},{g:.4f},{b:.4f},{alpha:.1f}"


def source_paths() -> list[str]:
    """The `d` attribute of every path in the artwork, in file order."""
    return re.findall(r'<path d="([^"]+)"', SOURCE.read_text())


def source_box() -> tuple[float, float]:
    """The artwork's own viewBox, read rather than assumed.

    The brand mark is 431×429 — not square, and not the 512 the first source
    happened to be. Hard-coding either is how a mark ends up a few points off
    centre with nothing on screen to say why.
    """
    box = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', SOURCE.read_text())
    return (float(box.group(1)), float(box.group(2))) if box else (CANVAS, CANVAS)


def layer_svg(indices: list[int], paths: list[str]) -> str:
    """One layer: the named paths, scaled and centred on the icon canvas.

    Filled white and nothing else. Icon Composer rasterises an SVG by filling
    its contours — a stroked path arrives as a filled disc, which is how the
    first build of this came out as a white blob — and the source is already
    outlines, so nothing has to be converted.
    """
    width, height = source_box()
    scale = CANVAS * MARK_SPAN / max(width, height)
    dx = (CANVAS - width * scale) / 2
    dy = (CANVAS - height * scale) / 2
    body = "".join(f'<path d="{paths[i]}"/>' for i in indices)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS:g}" '
        f'height="{CANVAS:g}" viewBox="0 0 {CANVAS:g} {CANVAS:g}">'
        f'<g transform="translate({dx:.2f} {dy:.2f}) scale({scale:.4f})" '
        f'fill="#FFFFFF" fill-rule="evenodd">{body}</g></svg>\n'
    )


def source_gradient() -> list[tuple[float, str]]:
    """The background gradient's stops, read out of the source file.

    The source is the designer's own artboard — white mark on the brand
    gradient — so the colours are in it and there is nothing to choose.
    Reading them beats copying them: a hex retyped into this file is a second
    source of truth that drifts the first time the artwork is re-exported.
    """
    text = SOURCE.read_text()
    block = re.search(r"<linearGradient[^>]*>(.*?)</linearGradient>", text, re.S)
    if not block:
        return []
    stops = []
    for stop in re.finditer(r"<stop([^>]*)/>", block.group(1)):
        attrs = stop.group(1)
        offset = re.search(r'offset="([\d.]+)"', attrs)
        colour_hex = re.search(r'stop-color="(#[0-9A-Fa-f]{6})"', attrs)
        if colour_hex:
            stops.append(
                (float(offset.group(1)) if offset else 0.0, colour_hex.group(1))
            )
    return stops


def background_svg() -> str:
    """The gradient as a full-bleed layer, with the artwork's own direction.

    `x1=1080 y1=0 → x2=0 y2=1080` in the source: top-right to bottom-left. The
    diagonal is what lets all three stops show on a square.
    """
    stops = "".join(
        f'<stop offset="{at:.4f}" stop-color="{hexcode}"/>'
        for at, hexcode in source_gradient()
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS:g}" '
        f'height="{CANVAS:g}" viewBox="0 0 {CANVAS:g} {CANVAS:g}">'
        f'<defs><linearGradient id="bg" x1="1" y1="0" x2="0" y2="1">{stops}'
        f"</linearGradient></defs>"
        f'<rect width="{CANVAS:g}" height="{CANVAS:g}" fill="url(#bg)"/></svg>\n'
    )


def document(flat_background: bool) -> dict:
    """`icon.json` — the layer stack, and how much glass is applied to it.

    **Translucency is off.** With it on (0.4–0.5, which is what the format
    suggests) the three arcs, the ring and the triangle all became milky and
    ran together: at 60 points the mark read as one soft blob rather than as
    two rings around a play button. The whole point of this mark is thin white
    lines with dark gaps between them, and translucency fills exactly those
    gaps. Specular and the shadow stay — they are what make it sit in Liquid
    Glass — but the ink stays opaque.

    Three groups rather than one, so each is lit separately and the highlight
    travels across the mark as the phone tilts.
    """
    stops = source_gradient()
    ends = (stops[0][1], stops[-1][1]) if len(stops) >= 2 else ("#008FFF", "#FF9A12")
    white = colour("#FFFFFF")

    def group(
        image: str, name: str, shadow: float, lit: bool = True, fill: dict | None = None
    ) -> dict:
        # **`fill` belongs to the layer, not the group** — measured by filling a
        # white circle red: on the layer it came back red, on the group white,
        # and `ictool` returned 0 both times. An accepted key that does nothing
        # is worse than a rejected one.
        #
        # **`fill-specializations` does nothing at all here.** On a group it is
        # accepted and ignored (dark stayed the system's own colouring, not the
        # red asked for); on a layer the document stops parsing entirely — "the
        # data couldn't be read". Per-appearance colours are a thing the app's
        # own UI writes and this file format, at Icon Composer 1.6, does not
        # take from JSON. So: one fill, and it holds everywhere.
        layer: dict = {"image-name": image, "name": name}
        if fill:
            layer["fill"] = fill
        return {
            "layers": [layer],
            "shadow": {"kind": "neutral", "opacity": shadow},
            "specular": lit,
            "translucency": {"enabled": False, "value": 0.0},
        }

    # White on the gradient, which is most brands' main lock-up.
    #
    # In the **dark** appearance the system re-colours the mark from the
    # background gradient by itself, and a white fill declared for dark does not
    # stop it — measured, twice. That turned out to be the right answer rather
    # than a fight: a brand set that carries a white-on-gradient lock-up almost
    # always carries the coloured-mark-on-black one too. So the fix is not to
    # keep the mark white but to take the gradient off the background, which is
    # what the specialisation below does.
    ink = {"solid": white}

    groups = [
        group("play.svg", "Play", 0.4, fill=ink),
        group("ring.svg", "Ring", 0.35, fill=ink),
        group("arcs.svg", "Arcs", 0.3, fill=ink),
    ]
    if not flat_background:
        groups.append(group("background.svg", "Background", 0.0, lit=False))

    return {
        # Two ends only — the format takes no more. With `flat_background` this
        # *is* the background; otherwise it is what the tinted and clear
        # appearances fall back to.
        "fill": {"linear-gradient": [colour(ends[0]), colour(ends[1])]},
        # **Last is furthest back.** The list is drawn front to back — the
        # background written first covered the whole mark, and the icon came
        # out as a bare gradient square.
        "groups": groups,
        "supported-platforms": {"circles": ["watchOS"], "squares": ["iOS", "macOS"]},
    }


def build(flat_background: bool) -> None:
    paths = source_paths()
    if len(paths) < 5:
        print(f"{SOURCE.name} has {len(paths)} paths, expected 5", file=sys.stderr)
        raise SystemExit(1)
    assets = ICON / "Assets"
    if ICON.exists():
        shutil.rmtree(ICON)
    assets.mkdir(parents=True)
    if not flat_background:
        (assets / "background.svg").write_text(background_svg())
    for name, indices in PATHS.items():
        (assets / f"{name}.svg").write_text(layer_svg(indices, paths))
    (ICON / "icon.json").write_text(
        json.dumps(document(flat_background), indent=2) + "\n"
    )
    stops = " → ".join(hexcode for _, hexcode in source_gradient())
    print(
        f"wrote {ICON} — background {stops}, "
        f"{len(PATHS)} mark layers from {SOURCE.name}, mark {MARK_SPAN:.0%} of the canvas"
    )


# Every appearance the system can put the icon in. Rendering all of them is the
# only way to see what tinting does to a mark made of separate white shapes.
RENDITIONS = ["Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"]


def render(out_dir: pathlib.Path) -> int:
    if not ICTOOL.exists():
        print(f"ictool not found at {ICTOOL}", file=sys.stderr)
        return 1
    out_dir.mkdir(parents=True, exist_ok=True)
    failed = 0
    for rendition in RENDITIONS:
        out = out_dir / f"icon-{rendition.lower()}.png"
        result = subprocess.run(
            [
                str(ICTOOL),
                str(ICON),
                "--export-image",
                "--output-file",
                str(out),
                "--platform",
                "iOS",
                "--rendition",
                rendition,
                "--width",
                "512",
                "--height",
                "512",
                "--scale",
                "1",
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0 or not out.exists():
            failed += 1
            print(f"  ✗ {rendition}: {result.stderr.strip() or result.stdout.strip()}")
        else:
            print(f"  ✓ {rendition}: {out}")
    return failed


def main() -> int:
    global SOURCE, ICON, MARK_SPAN
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "--source",
        required=True,
        help="the designer's SVG artboard: mark on its tile, outlines",
    )
    ap.add_argument("--icon", required=True, help="the .icon bundle to write")
    ap.add_argument(
        "--mark-span",
        type=float,
        default=MARK_SPAN,
        help="how much of the canvas the artboard takes (0.9 leaves "
        "the room watchOS's circular mask needs)",
    )
    ap.add_argument(
        "--flat-background",
        action="store_true",
        help="drop the three-stop layer; let the two-colour fill be the "
        "background, which is the only form dark and tinted can dim",
    )
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    SOURCE = pathlib.Path(args.source)
    ICON = pathlib.Path(args.icon)
    MARK_SPAN = args.mark_span
    if not SOURCE.exists():
        print(f"no artwork at {SOURCE}", file=sys.stderr)
        return 1
    build(args.flat_background)
    if not args.render:
        return 0
    return render(pathlib.Path(args.out or ICON.parent / "icon-previews"))


if __name__ == "__main__":
    sys.exit(main())
