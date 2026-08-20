---
name: solo-swiftui-design-system
description: Build and hold a SwiftUI design system — a 12-column grid, spacing/type/radius/motion scales, surface levels, a component gallery, and the guards that stop it drifting back. Use when the user says "сделай по сетке", "дизайн-система", "разъезжается вёрстка", "магические числа в padding", "design tokens", "grid 12", "нужен storybook/каталог компонентов", or when a screen's spacing and fonts were each chosen once and never against each other. Do NOT use for SwiftUI correctness, state flow or Instruments profiling (that is the swiftui-expert skill), or for shipping to TestFlight (solo-ios-release).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "📐"
---

# swiftui-design-system — one scale, and the guards that keep it

A design system is not a colour file. It is **four scales, one grid, one
catalogue and one tripwire** — and the tripwire is what makes it survive the
next feature. Everything here is native SwiftUI: no design-system framework is
worth taking on, because the platform is already built for this (Environment +
style protocols + `containerRelativeFrame`).

Reach for this when the symptom is *"the screens look related and never line
up"*. Measure before you believe it — see step 1.

## Workflow

### 1. Count what is actually there

Never start from taste. Start from the inventory, because the number is the
argument:

```bash
V=path/to/Views
grep -rhoE '\.padding\((\.[a-z]+, )?[0-9]+(\.[0-9])?\)' $V | grep -oE '[0-9.]+' | sort -n | uniq -c | sort -rn
grep -rhoE 'spacing: [0-9]+(\.[0-9])?' $V | sort | uniq -c | sort -rn
grep -rhoE 'cornerRadius: [0-9]+(\.[0-9])?' $V | sort | uniq -c | sort -rn
grep -rhoE '\.font\(\.[a-zA-Z0-9]+\)|\.font\(\.system\([^)]*\)\)' $V | sort | uniq -c | sort -rn
grep -rhoE '\.spring\(response: [0-9.]+, dampingFraction: [0-9.]+\)' $V | sort -u | wc -l
```

A real app measured this way: **27 padding values, 19 spacings, 23 radii, 48
font spellings, 21 springs** — including `.system(size: 17.5)`, `13.5`, `12.5`.
Half a point is invisible alone and lethal in a set: it is exactly the amount by
which two labels fail to look like the same label.

### 2. Write the scales — namespace enums, one file each

```
Views/Design/
  Space.swift       4-point steps: hair(2) xs sm md lg xl xxl xxxl huge + touchTarget(44)
  Grid.swift        12 columns, gutter, margin, gridSpan(_:), gridMargins(), GridOverlay
  Typography.swift  8 steps, each a platform TextStyle + Metric for sizes a font can't set
  Radii.swift       5 radii + shape(_:) — .continuous, always
  Motion.swift      6 curves + the never-repeatForever rule
  Surface.swift     3–4 levels (console/panel/inset/field), one recipe each
```

Enums over structs: compile-time names, zero runtime, no instance to thread.
**Reach for `@Entry var theme` in the Environment only when there is a second
theme** (white-label, per-brand, light/dark that is not the system's). Until
then a theme object is one indirection buying nothing.

Two rules that decide the arguments in step 3:

- **Every type step is a platform text style** — `Font.system(.subheadline,
  weight:)`, not `.system(size: 15)`. Fixed sizes never grow with Dynamic Type;
  in the measured app 78 of them didn't. For sizes a font cannot set (an icon's
  box, a ring's diameter) use `@ScaledMetric(relativeTo:)` over a `Metric`
  constant.
- **The unit of layout is the column, not the point.** `containerRelativeFrame(
  .horizontal, count: 12, span: 4, spacing: gutter)` is iOS 17+ and is the
  platform's own grid arithmetic — no `GeometryReader`, no percentages.

### 3. Migrate mechanically, with the rounding rule written down

Hand-editing hundreds of literals is where a migration dies — half done, half
not, and nobody can say which half. Write a codemod, keep it in the repo, and
let it carry the rule:

```python
# nearest 4-point step, TIES GO UP (6→8, not 4): rounding down tightens a
# third of the app by two points at once, and a snug layout is the one that
# breaks. Only padding / spacing / cornerRadius / fonts in 9…26pt —
# never frame, offset, lineWidth or a shadow radius.
step, name = min(SCALE, key=lambda p: (abs(p[0] - value), -p[0]))
```

**Full rule, the skip list, the spring and font tables: `references/codemod.md`.**
Read it when actually migrating; one measured run was 991 substitutions in 31
files, dry-run first, build after each family.

### 4. Style protocols, not modifiers sprinkled per call site

SwiftUI's extension points are the system's spine — use them before inventing
`.myButton()`:

```swift
struct PressableStyle: ButtonStyle {           // one feel for every control
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.release,
                       value: configuration.isPressed)
    }
}
```

`LabelStyle`, `ToggleStyle`, `ProgressViewStyle`, `MenuStyle` the same way; a
`ViewModifier` + `extension View` for what has no protocol (`.surface(.inset)`).

### 5. Build the catalogue — and make it cheap to look at

Two doors, answering different questions:

```bash
make design       # ImageRenderer → PNG sheets from a test: no launch, no taps, ~3s
make design-app   # the same gallery in the simulator: glass, blur, motion
… launch <app> -designGrid YES   # the 12 columns over the REAL screens
```

`ImageRenderer` inside an XCTest is the whole storybook you need — a gallery
view rendered to `docs/previews/*.png`, one file per sheet, no navigation and no
external dependency. **It does not draw materials**: `.ultraThinMaterial` and
`glassEffect` come out empty, so glass reads flat there. Geometry is exact,
which is what the sheets are for.

The grid overlay over the *real* app is the only thing that proves two screens
agree; a gallery only proves one screen is tidy.

**The writer, the debug flag, the localisation trap and when to reach for
swift-snapshot-testing: `references/catalogue.md`.**

### 6. Guard it, or it comes back

Three layers, cheapest first:

1. **pre-commit grep on added lines** (warn, not fail): a numeric
   `.padding(12)`, `spacing: 6`, `cornerRadius: 18`, `.font(.system(size: 13))`.
   Diff-scoped and warning-only is the right calibration — a whole-tree lint at
   fail severity breaks on inherited debt and gets bypassed, and a bypassed hook
   checks nothing.
2. **tests on the arithmetic**: 12 columns + 11 gutters + 2 margins == the
   screen; `span(6) * 2 + gutter == width`; every space step divisible by 4
   except the one deliberate half step.
3. **snapshot sheets in the repo** — a reviewer sees the scale change as an
   image diff.

## Gotchas

- **`containerRelativeFrame` measures the container, not its content.** Apply
  `gridMargins()` first, or every span is a margin too wide and nothing lines
  up with anything.
- **A `Sendable` warning on `static let` tokens** in Swift 6: an enum of
  `static let CGFloat` is fine; a struct holding `UserDefaults` needs
  `@unchecked Sendable` with a one-line reason.
- **Glass cannot sample glass.** Two blurred surfaces side by side each sample
  what is behind them and read as unrelated panes. On iOS 26 wrap a row of them
  in `GlassEffectContainer(spacing:)` and give morphing pairs a
  `.glassEffectID(_:in:)`; below 26 fall back to `.ultraThinMaterial` in one
  place, not per screen.
- **`compositingGroup()` + a zero shadow is still an offscreen pass.** Apply
  the lift only where there is a shadow to draw.
- **Never `repeatForever`.** A UI that never goes idle hangs everything that
  waits for idle: accessibility snapshots, UI automation, VoiceOver. Use
  `.repeatCount(n)` and honour `\.accessibilityReduceMotion`.
- **A debug surface needs a testable flag.** `-designGallery YES` from `simctl`
  lands in the argument domain, so one `UserDefaults.bool(forKey:)` read covers
  it — but wrap it in a small injectable type that is false in Release, or the
  flag ships.
- **A scalar threaded by hand through call sites is invisible to grep.** In the
  measured app a wheel's vertical offset was written in three places; two moved
  onto the shared centre and the third did not, so the drawing and the single-tap
  hit test disagreed by 20 points with nothing on screen to say so. Pass one
  geometry *value* — then a call site that forgets it does not compile.

## What is coming (and what already works)

- **iOS 26 / Swift 6.2 — today.** Liquid Glass (`glassEffect`,
  `GlassEffectContainer`, `.buttonStyle(.glass)`), `@Entry` for environment
  tokens with no `EnvironmentKey` boilerplate, `ToolbarSpacer`,
  `backgroundExtensionEffect()`, `scrollEdgeEffectStyle`.
- **iOS 27 / Swift 6.4 (WWDC26 → 2027).** `ContentBuilder` collapses the
  container overloads that cause *"unable to type-check this expression in
  reasonable time"* — and it helps when built with the new Xcode regardless of
  deployment target. `.reorderable()` in any container (not just `List`), swipe
  actions outside `List`, toolbar overflow priorities, `@State` as a macro with
  lazy `@Observable` init (back-deployed to iOS 17). **Resizable iPhone apps** is
  the one that touches a design system directly: baked-in sizes stop being safe,
  so snapshot at several widths.
## Apple's own skills, and the rest of the field

Xcode ships agent skills in the toolchain — plain `SKILL.md` folders, so they
work in any agent, not only Xcode's assistant.

```bash
make apple-skills          # solo-factory: export into ~/.agents/skills, diffed
make apple-skills-check    # what it would bring, without writing
```

**Xcode 26.6 exports nothing** — the `agent` tool is there and answers *"No
skills available to export"*, so the script says that plainly rather than look
broken. **Xcode 27.0 beta 2 exports ten**: `swiftui-specialist`,
`swiftui-whats-new-27`, `uikit-app-modernization`, `modernize-tests`,
`audit-xcode-security-settings`, `adopt-c-bounds-safety`, `device-interaction`,
`app-intents-specialist`, `app-intents-whats-new-27` and
`building-document-based-swiftui-applications`. The names are not stable across
versions — four of the seven guessed from the 26.6 release notes came back
spelled differently — so read the export rather than a list.

Re-run after every Xcode update: these track the SDK, and a stale "what's new"
skill is worse than none. A beta installed alongside the release is not the
active toolchain, and `xcode-select` is machine-wide — scope one run instead:
`DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" make apple-skills`.
If the export names the toolchain instead, Xcode → Settings → Locations →
Command Line Tools points at the wrong Xcode.

`device-interaction` is the one that matters for a design system: it drives a
real device or simulator — screenshots, view hierarchy, synthesised taps — which
closes the loop a build tool alone cannot (write layout → build → look at it →
correct it) without a human running the walk.

Community skills worth reading **before** installing — a skill is injected into
the assistant's context and changes how it writes your code:

| Where | Why |
|---|---|
| `twostraws/Swift-Agent-Skills` | curated index; start here |
| `twostraws/SwiftUI-Agent-Skill` (`swiftui-pro`) | aimed at the mistakes LLMs actually make: navigation, layout, state, VoiceOver, deprecated APIs |
| `AvdLee/SwiftUI-Agent-Skill` | the architecture to copy — references loaded on demand, so deep context costs nothing until asked for. Also a maintenance skill that refreshes the deprecated-API list after each release |
| `Dimillian/Skills` | `swiftui-liquid-glass`, `swiftui-view-refactor`, `swiftui-performance-audit` |
| `dpearson2699/swift-ios-skills` | 86 skills on iOS 26+ — **PolyForm Perimeter licence, not MIT**; read it before commercial use |

Design-system repos worth reading rather than depending on: **DSKit** (organised
for agents — generated docs link every component to its source, snapshots and
usage), **OversizeUI** (semantic colours, Dynamic Type, spacing scale),
**design-foundation** (MIT, Swift 6 concurrency-safe), **ouds-ios** (corporate
scale, strong accessibility).

## Don't

- **Don't add a design-system framework.** Environment + style protocols + the
  grid API cover it; a framework on top mostly fights the layout system.
- **Don't name colours `blue500`.** Semantic names (`surfaceElevated`,
  `textSecondary`) survive a re-skin; a palette index turns one into a
  find-and-replace across the app.
- **Don't fold weight into the type scale.** `isSelected ? .semibold : .regular`
  is a step plus `.fontWeight()` on top — folding it in is how a scale of eight
  becomes a scale of sixteen.
- **Don't chase the photo grid onto the interface gutter.** A wall of images
  wants 1–2pt between tiles; keep it *on* the twelve columns (a tile is a third
  of the width) and let the spacing be its own.
- **Don't ship aliases.** `Brand.tabRadius = Radii.lg` reads as tidy and puts
  two spellings of 16pt in one file within a week.
- **Don't measure a render or a build on a loaded machine.** Check `vm.loadavg`
  first; three "regressions" in one project were the laptop.
