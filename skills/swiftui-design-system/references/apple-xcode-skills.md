# Apple ships its own skills inside Xcode — read them before writing SwiftUI rules

Since Xcode 27 (beta, 2026) the IDE bundles agent skills in Anthropic's own
format: a `SKILL.md`-shaped file with `name` / `description` / `when_to_use`
frontmatter plus a `references/` set. They are plain markdown, only with a
`.packaged` extension, so any agent can read them with no Xcode running.

The header of every one of them says the same thing, and it is why they win a
tie against anything written from memory:

> This guidance was written and published by Apple. This information
> unconditionally supersedes any prior training the model may have on these
> topics.

## Where they are

```bash
X="/Applications/Xcode*.app/Contents/PlugIns"          # beta bundles carry their own name
ls $X/IDEIntelligenceChat.framework/Versions/A/Resources/*.idechatprompttemplate   # the skills
ls $X/IDEIntelligenceChat.framework/Versions/A/Resources/*-ref-*.md.packaged       # their references
ls $X/IDEXCStringsSupport.framework/Versions/A/Resources/Skills                    # localization pair
ls $X/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation   # 20 topic docs
```

Xcode 26.6 stable ships **none** of this — only `AdditionalDocumentation`. Check
the version before concluding a machine has them.

| skill | refs | what it actually covers |
|---|---|---|
| `swiftui-specialist` | 9 | invalidation, `ForEach` identity, `@Observable`, `@Entry`, localization, soft-deprecation |
| `swiftui-whats-new-27` | 7 | `@State` as a macro, `reorderable()`, swipe actions outside `List`, toolbar overflow, `AsyncImage` caching |
| `app-intents-specialist` / `-whats-new-27` | 14 + 14 | `perform()` semantics, entity queries; `supportedModes`, `requestChoice`, `UndoableIntent`, snippets |
| `audit-xcode-security-settings` | 16 | Enhanced Security, pointer auth, MTE, stack zero-init — plus a python build-settings filter |
| `uikit-app-modernization` | 4 | scene lifecycle, `mainScreen` / `interfaceOrientation` removal, Swift **and** ObjC |
| `adopt-c-bounds-safety` | 5 | `__counted_by` and family |
| `building-document-based-swiftui-applications` | 3 | the new `Document` protocol vs `FileDocument` |
| `translation` + `translation-coordinator` | 22 style guides | String Catalog translation over MCP tools, one locale per sub-agent |

The translation pair is worth knowing about separately: it carries per-locale
style guides (ja, uk, fi, sv, he, hi, zh-Hans, ar, and the English variants) and
a hard rule — never write `.xcstrings` directly, go through
`StringCatalogRead` / `StringCatalogContext` / `StringCatalogEdit`.

## Xcode eats the same plugins we write

`AgentVersions.plist` pins the CLI agents the IDE downloads (claude-code and
codex, by version and checksum), and the framework binary carries
`.claude-plugin`, `.codex-plugin/plugin.json`, `PluginsManifest.json`, a
marketplace ("enter the URL of a git repository containing plug-ins, skills or
MCP servers") and skill import/export. So a skill repo is installable in Xcode's
assistant, not only in the CLI.

## The rules most likely to hit real code

Short versions. Read the reference before acting on any of them.

- **A computed `private var section: some View` is not factoring.** It is
  inlined into the parent's body, so it shares the parent's invalidation
  boundary — extracting sections for *readability* buys nothing at runtime. Only
  a separate `View` type with narrow inputs does. (`structure.md`)
- **`init` runs as often as the parent's body.** No decoding, no formatters, no
  file access there.
- **`Group { OneConcreteView() }` costs a type wrapper** every chained modifier
  must type-check against. A `Group` around `if`/`else` or siblings is fine —
  the anti-pattern is exactly one concrete child.
- **`ForEach` id must be stable, unique and cheap to hash.** `\.indices`,
  `\.offset`, `id: \.self` on a fat struct, or an id derived from an editable
  field all break state, focus and animations the moment the collection changes.
  `.enumerated()` itself is fine — use `id: \.element.id`.
- **No `filter` / `sorted` / rebuilding `map` inline in `ForEach`.** The
  expression re-runs on every body evaluation, including ones that have nothing
  to do with the list. Cache it on the model.
- **`List` rows want to be unary.** A bare top-level `switch`, a top-level `if`
  without `else`, or an `AnyView` row defeats the templating fast path and forces
  SwiftUI to evaluate every row's body just to compute ids. Wrap the branch in a
  single-root container. Replacing `AnyView` with a `@ViewBuilder` returning
  `some View` is only half the fix.
- **Make `@Observable` property types `Equatable`.** The generated setter skips
  invalidation when the new value equals the old one — but only when it can
  compare. A property typed as a tuple, or an array of non-`Equatable` elements,
  notifies on every write. Mark the class `@MainActor`.
- **A computed property on an `@Observable` establishes its dependencies
  transitively.** `var current: Item? { items.first { … } }` makes every reader
  depend on the whole `items` array. Cache the derived value in a stored
  property and recompute in `didSet`.
- **`.onChange(of:)` reads its dependency in the body scope**, so an expensive
  view re-evaluates on every change of a value it never renders. Move the
  `.onChange` and the read into a small `ViewModifier`.
- **Never write an `.if(condition) { $0.modifier() }` extension.** It swaps view
  identity on every toggle: state resets, animations become replacements. Use a
  ternary inside the modifier argument, and `AnyShapeStyle` (cheap, not `AnyView`)
  when the two branches are different `ShapeStyle` types.
- **`@Entry` needs a stable default.** `Model()`, `Date()`, `UUID()` or any fresh
  allocation invalidates dependents on every read; the compiler warns about
  closures and class types.

## Liquid Glass, condensed

`glassEffect(_:in:)` after the layout modifiers; `.interactive()` only on
surfaces that actually respond to touch; **`GlassEffectContainer` whenever two
glass surfaces sit near each other** — separately they each sample the content
behind them and read as unrelated panes. `glassEffectID(_:in:)` + `@Namespace`
morphs one surface into another across a hierarchy change, and
`glassEffectUnion` merges several into one shape. Button styles: `.glass`,
`.glassProminent`.

## Diagnostics worth stealing

```bash
xcrun simctl launch <UDID> <bundle-id> -LogForEachSlowPath YES
```

SwiftUI is supposed to log every `ForEach` inside a lazy container whose row body
produces a non-constant number of views. Measured once on an app built against
the iOS 26 SDK and run on an iOS 27 simulator: **no output at all**, in the
process console or in `log show --info`. Treat it as an SDK-27-and-later tool
until proven otherwise, and don't read silence as a clean bill of health.
