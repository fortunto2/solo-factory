# The codemod — moving an existing app onto the scale

Loaded on demand: read this when actually migrating literals, not when writing
a new component.

Hand-editing hundreds of call sites is where a design-system migration dies —
half done, half not, and no one can say which half. Write the codemod, keep it
in the repo, and let it carry the rounding rule so the rule is readable instead
of folklore. One real run: **991 substitutions across 31 files**, in one pass,
with the app building after each family.

## What it may touch, and what it must not

| Rewritten | Left alone |
|---|---|
| `.padding(12)`, `.padding(.horizontal, 6)` | `.frame(width: 240)` — a size, not a gap |
| `spacing: 14` | `.offset(x: 3)` |
| `cornerRadius: 18` | `lineWidth: 1.5` |
| `.font(.system(size: 13, weight: .semibold))`, `.font(.caption)` | `.shadow(radius: 16)` |
| `.spring(response:dampingFraction:)`, short `.easeOut/.easeInOut/.linear` | decorative/long curves (0.35s+, 60s turns) |
| `RoundedRectangle(cornerRadius: X, style: .continuous)` | a computed radius (`radius * 0.5`) |

A `frame` is the size of a thing; a `padding` is the space around it. Rounding
the first changes the design, rounding the second aligns it.

## The rounding rule

```python
SPACE = [(2,"Space.hair"),(4,"Space.xs"),(8,"Space.sm"),(12,"Space.md"),
         (16,"Space.lg"),(20,"Space.xl"),(24,"Space.xxl"),(32,"Space.xxxl"),
         (48,"Space.huge")]

def nearest(value, table):
    if value > 56:            # past the scale it is a size, not a gap
        return None
    # TIES GO UP: 6 is equidistant from 4 and 8, 10 from 8 and 12. Rounding
    # down tightens a third of the app by two points at once, and the layout
    # that was already snug is the one that breaks. Air is the safe direction.
    step, name = min(table, key=lambda p: (abs(p[0] - value), -p[0]))
    return name if abs(step - value) <= 6 else None
```

## Font bounds are 9…26, deliberately

```python
def font_step(size, weight):
    if size < 9 or size > 26:
        return None          # a mark, or an illustration glyph — not type
    strong = weight in {"semibold","bold","heavy","black"}
    if size <= 10:   return "caption"
    if size <= 12.5: return "label" if strong else "caption"
    if size <= 14.5: return "calloutStrong" if strong else "callout"
    if size <= 16.5: return "bodyStrong" if strong else "body"
    if size <= 19:   return "headline"
    return "title"
```

Below nine points the number is a *mark*: a day number on a calendar ring, a
tick's label inside a `Canvas`. The scale's smallest step would double it.
Above ~26 it is nearly always `Image(systemName:)` standing in for an
illustration — a 64pt permission glyph, a 72pt launch ring.

**Have a `*Strong` step for every tier the app actually bolds.** Without one the
script picks the nearest step and a human bolts `.fontWeight(.semibold)` on top
— a step followed immediately by an override of the step. Three of those
appeared in one file the first time this ran.

## Springs by shape, not by number

```python
if damping < 0.7:      name = "release"   # that bounce is its character
elif response >= 0.38: name = "settle"    # a panel arriving at a stop
else:                  name = "slide"     # something small changing place
```

Twenty-one distinct spring spellings existed before this; nobody chose
twenty-one springs. Easing folds the same way: 0.12–0.26s → `fade`, a
0.25–0.35s `linear` → `progress`, everything longer is doing something specific
and stays.

## How to run it

```bash
python3 scripts/design_migrate.py            # report only
python3 scripts/design_migrate.py --write    # apply
```

Read the report before writing — the font lines especially, since a 13pt label
that was deliberately smaller than its neighbour becomes the same step as that
neighbour. Usually that is the point. Occasionally it is not.

Build after each family, and **keep the script**: the pre-commit guard's
warning should name it, which makes it live tooling rather than an orphan.

## Skip list

Exclude by path, and say why in the code:

- the design system's own directory (it defines the scale)
- generated bindings (uniffi/protobuf output)
- anything whose points are geometry, not layout — Metal vertex code, `Canvas`
  paths drawn to their own design grid, a logo mark built on a 52-point canvas
  where every number is relative
