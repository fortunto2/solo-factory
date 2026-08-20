#!/usr/bin/env python3
"""Put every literal gap, corner and font in the views onto the design scale.

Counted before this ran: 27 distinct padding values, 19 spacings, 23 corner
radii and 48 font spellings across 17 900 lines of SwiftUI. None of them was
chosen against the others — each was chosen once, on its own screen.

This script does the mechanical half of the move, and only the mechanical half:

  .padding(9)            -> .padding(Space.sm)
  spacing: 14            -> spacing: Space.lg
  cornerRadius: 18       -> cornerRadius: Radii.lg
  .font(.system(size: 13, weight: .semibold))  -> .font(TypeScale.callout)…

Rounding is to the nearest 4-point step, with 2 kept as the one half step (a
hairline, or the gap inside a single object). A value that rounds to something
a person would notice — a 40-point frame becoming 48 — is left alone: this only
ever touches padding, spacing and corner radius, never `frame`, `offset`,
`lineWidth` or a shadow's radius.

  python3 scripts/design_migrate.py            # report what would change
  python3 scripts/design_migrate.py --write    # change it

Read the report before writing. The fonts in particular are a judgement — a
13-point label that was deliberately smaller than its neighbour becomes the
same step as that neighbour, which is usually the point and occasionally not.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from collections import Counter

# Where the views live. Given on the command line, because this script belongs
# to the skill rather than to any one app.
VIEWS = pathlib.Path()

# Files this must not touch, and why.
SKIP = {
    "Design",  # the scale itself
    "Generated",  # uniffi output
    "Cylinder",  # Metal geometry — points here are vertex coordinates
    "L2FIcons.swift",  # Canvas paths drawn to a 24-unit design grid
    "MakeMark.swift",  # the mark's own 52-point canvas, every number relative
}

# 4-point steps, and the one half step at 2.
SPACE = [
    (2, "Space.hair"),
    (4, "Space.xs"),
    (8, "Space.sm"),
    (12, "Space.md"),
    (16, "Space.lg"),
    (20, "Space.xl"),
    (24, "Space.xxl"),
    (32, "Space.xxxl"),
    (48, "Space.huge"),
]
RADII = [
    (2, "Radii.hair"),
    (4, "Radii.xs"),
    (8, "Radii.sm"),
    (12, "Radii.md"),
    (16, "Radii.lg"),
    (24, "Radii.xl"),
    (36, "Radii.xxl"),
]


def nearest(value: float, table) -> str | None:
    """The step closest to `value`, or None when nothing is close enough.

    Past 48 the scale stops and the number is a size rather than a gap — a
    300-point sheet height is not a padding that drifted."""
    if value > 56:
        return None
    # Ties go **up**: 6 is equidistant from 4 and 8, and 10 from 8 and 12.
    # Rounding down there would tighten a third of the app by two points at
    # once, and a layout that was already snug is the one that breaks. Air is
    # the safer direction — `-pair[0]` makes the larger step win a tie.
    step, name = min(table, key=lambda pair: (abs(pair[0] - value), -pair[0]))
    # More than a step and a half away means this was not a gap on any scale —
    # leave it and let a person look at it.
    return name if abs(step - value) <= 6 else None


NUM = r"(\d+(?:\.\d+)?)"

PADDING = re.compile(r"\.padding\((\.\w+,\s*)?" + NUM + r"\)")
SPACING = re.compile(r"\bspacing:\s*" + NUM + r"\b")
CORNER = re.compile(r"\bcornerRadius:\s*" + NUM + r"\b")

# `.spring(response: 0.34, dampingFraction: 0.78)` and friends. 21 distinct
# spellings across 12 files before this ran — nobody chose twenty-one springs.
SPRING = re.compile(
    r"\.spring\(response: " + NUM + r", dampingFraction: " + NUM + r"\)"
)
# The easing curves that are one of the two named ones. Anything longer than a
# third of a second is doing something specific (a decorative drift, a 60s
# turn) and is left alone.
EASING = re.compile(r"\.(easeOut|easeInOut)\(duration: " + NUM + r"\)")
LINEAR = re.compile(r"\.linear\(duration: " + NUM + r"\)")
# `RoundedRectangle(cornerRadius: X, style: .continuous)` — 41 spellings in 12
# files. `Radii.shape(_:)` is the same thing and is always `.continuous`.
ROUNDED = re.compile(
    r"RoundedRectangle\(cornerRadius: ([A-Za-z0-9_.]+)(, style: \.continuous)?\)"
)

# .font(.system(size: 13, weight: .semibold, design: .rounded))
FONT_SIZED = re.compile(
    r"\.font\(\.system\(size:\s*"
    + NUM
    + r"(?:,\s*weight:\s*\.(\w+))?(?:,\s*design:\s*\.(\w+))?\)\)"
)
# .font(.caption) and friends
FONT_STYLE = re.compile(
    r"\.font\(\.(caption2|caption|footnote|subheadline|headline|body|callout|title3|title2|title|largeTitle)\)"
)

STYLE_MAP = {
    "caption2": "caption",
    "caption": "caption",
    "footnote": "callout",
    "subheadline": "body",
    "body": "body",
    "callout": "callout",
    "headline": "headline",
    "title3": "title",
    "title2": "title",
    "title": "title",
    "largeTitle": "display",
}

HEAVY = {"semibold", "bold", "heavy", "black"}


def font_step(size: float, weight: str | None) -> str | None:
    """Which step a fixed size belongs to, or None to leave it alone.

    Weight decides between the two steps that share a size: 12 semibold is a
    control's name (`label`), 11 regular is a caption under a thumbnail.

    **Only 9…26 is text.** Below nine the number is a mark rather than a word —
    a day number on the calendar ring, a tick's label — and the scale's
    smallest step would double it. Above twenty-six it is almost always an
    `Image(systemName:)` standing in for an illustration: the permission
    screen's 64-point photo glyph, the launch screen's 72-point ring. Both ends
    are sizes, not type, and neither belongs on a text scale."""
    if size < 9 or size > 26:
        return None
    strong = weight in HEAVY
    if size <= 10:
        return "caption"
    if size <= 12.5:
        return "label" if strong else "caption"
    if size <= 14.5:
        return "callout"
    if size <= 16.5:
        return "bodyStrong" if strong else "body"
    if size <= 19:
        return "headline"
    return "title"


def convert(text: str, tally: Counter) -> str:
    def pad(m: re.Match) -> str:
        edge, raw = m.group(1) or "", float(m.group(2))
        name = nearest(raw, SPACE)
        if not name:
            return m.group(0)
        tally[f"padding {raw:g} -> {name}"] += 1
        return f".padding({edge}{name})"

    def space(m: re.Match) -> str:
        raw = float(m.group(1))
        if raw == 0:
            return m.group(0)
        name = nearest(raw, SPACE)
        if not name:
            return m.group(0)
        tally[f"spacing {raw:g} -> {name}"] += 1
        return f"spacing: {name}"

    def corner(m: re.Match) -> str:
        raw = float(m.group(1))
        name = nearest(raw, RADII)
        if not name:
            return m.group(0)
        tally[f"radius {raw:g} -> {name}"] += 1
        return f"cornerRadius: {name}"

    def sized(m: re.Match) -> str:
        raw, weight = float(m.group(1)), m.group(2)
        # A size computed from something else (`size * 0.28`) never matches
        # this pattern, so anything here is a literal.
        step = font_step(raw, weight)
        if step is None:
            tally[f"font {raw:g} — left alone (a size, not type)"] += 1
            return m.group(0)
        tally[f"font {raw:g}{'/' + weight if weight else ''} -> {step}"] += 1
        return f".font(TypeScale.{step})"

    def styled(m: re.Match) -> str:
        step = STYLE_MAP[m.group(1)]
        tally[f"font .{m.group(1)} -> {step}"] += 1
        return f".font(TypeScale.{step})"

    def spring(m: re.Match) -> str:
        response, damping = float(m.group(1)), float(m.group(2))
        # Three questions, in order. A loose spring is a *release* whatever its
        # response — that bounce is the whole character of it. A slow one is a
        # panel arriving at a stop. Everything else is a small thing moving.
        if damping < 0.7:
            name = "release"
        elif response >= 0.38:
            name = "settle"
        else:
            name = "slide"
        tally[f"spring {response:g}/{damping:g} -> Motion.{name}"] += 1
        return f"Motion.{name}"

    def easing(m: re.Match) -> str:
        seconds = float(m.group(2))
        # Only the short ones. Past 0.3s an ease is doing something particular
        # — a wheel settling, a colour drifting — and a named "fade" would be
        # a lie about what it is.
        if not 0.12 <= seconds <= 0.26:
            return m.group(0)
        tally[f"{m.group(1)} {seconds:g}s -> Motion.fade"] += 1
        return "Motion.fade"

    def linear(m: re.Match) -> str:
        seconds = float(m.group(1))
        if not 0.25 <= seconds <= 0.35:
            return m.group(0)
        tally[f"linear {seconds:g}s -> Motion.progress"] += 1
        return "Motion.progress"

    def rounded(m: re.Match) -> str:
        radius = m.group(1)
        # A computed radius (`radius * 0.5`) never matches — the pattern takes
        # one identifier or number, so what is rewritten is always a token.
        tally[f"RoundedRectangle({radius}) -> Radii.shape"] += 1
        return f"Radii.shape({radius})"

    text = PADDING.sub(pad, text)
    text = SPACING.sub(space, text)
    text = CORNER.sub(corner, text)
    text = FONT_SIZED.sub(sized, text)
    text = FONT_STYLE.sub(styled, text)
    text = SPRING.sub(spring, text)
    text = EASING.sub(easing, text)
    text = LINEAR.sub(linear, text)
    text = ROUNDED.sub(rounded, text)
    return text


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "--views", required=True, help="the directory of SwiftUI views to migrate"
    )
    ap.add_argument("--write", action="store_true", help="apply the changes")
    ap.add_argument("paths", nargs="*", help="limit to these files")
    args = ap.parse_args()
    global VIEWS
    VIEWS = pathlib.Path(args.views)

    files = (
        [pathlib.Path(p) for p in args.paths]
        if args.paths
        else sorted(VIEWS.rglob("*.swift"))
    )
    tally: Counter = Counter()
    touched = 0

    for path in files:
        if any(part in SKIP for part in path.parts):
            continue
        before = path.read_text()
        after = convert(before, tally)
        if after == before:
            continue
        touched += 1
        if args.write:
            path.write_text(after)

    for change, count in sorted(tally.items(), key=lambda kv: -kv[1]):
        print(f"{count:4}  {change}")
    print(
        f"\n{sum(tally.values())} substitutions in {touched} files"
        f"{'' if args.write else ' (dry run — pass --write)'}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
