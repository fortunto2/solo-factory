# The catalogue, and seeing it without driving the app

Loaded on demand: read this when building the component gallery or wiring the
visual loop.

A design system nobody can look at is a set of constants. The catalogue is what
makes it a system — the type scale beside itself, the twelve columns over a real
control, every surface at once, so a step that does not belong is *visible*
rather than merely present in a file.

## Two doors, two questions

| Want to know | Use | Cost |
|---|---|---|
| do the numbers line up | `ImageRenderer` sheets from a test | ~3s, no launch, no taps |
| does the glass look right | the gallery on a simulator/device | a build + install |
| do two real screens agree | the grid overlay over the app | a relaunch |

## The whole storybook is one test

No external dependency needed — `ImageRenderer` inside XCTest writes PNGs:

```swift
@MainActor
enum SnapshotWriter {
    static let outputDir = URL(fileURLWithPath: #filePath)   // NOT the cwd:
        .deletingLastPathComponent()                          // a test host's
        .deletingLastPathComponent()                          // working dir is
        .deletingLastPathComponent()                          // not the project
        .appendingPathComponent("docs/previews", isDirectory: true)

    @discardableResult
    static func write(_ view: some View, named name: String,
                      size: CGSize, scale: CGFloat = 2) throws -> URL? {
        let renderer = ImageRenderer(content: view.frame(width: size.width)
                                                  .frame(minHeight: size.height, alignment: .top)
                                                  .background(Color.black))
        renderer.scale = scale
        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("ImageRenderer produced no image for \(name)"); return nil
        }
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let url = outputDir.appendingPathComponent("\(name).png")
        try data.write(to: url)
        print("SNAPSHOT \(url.path) — \(data.count) bytes")
        XCTAssertGreaterThan(data.count, 1_000, "\(name).png looks empty")
        return url
    }
}
```

**`ImageRenderer` does not draw materials.** `.ultraThinMaterial` and
`glassEffect` come out empty, so a glass panel reads flat there. Everything that
is geometry — grid, type, radii, spacing — is exact, and that is what the sheets
are for. For glass, launch the gallery.

**One writer, not one per suite.** Two test files each grew their own copy of
this in one project: same renderer, same three `deletingLastPathComponent()`
calls, different scales. Two copies of a path is how one of them ends up writing
somewhere nobody looks.

Make it one command:

```make
design: ## Render the design system to docs/previews/*.png
	@$(BOOTED_SIM) \
	xcodebuild test -project App.xcodeproj -scheme App \
		-destination "id=$$SIM" -only-testing:AppTests/DesignSheetTests 2>&1 \
		| grep -E "SNAPSHOT|error:|\*\* TEST"
```

## The gallery in the app, behind a launch argument

```swift
@State private var showGallery = DebugFlag.designGallery.isOn   // false in Release
```

`simctl launch <udid> <bundle> -designGallery YES` writes the pair into the
argument domain, so a launch argument *is* a `UserDefaults` key for that launch
— one `bool(forKey:)` read covers both. Wrap it in a small injectable type
(store + arguments as values) so the decision is testable and cannot ship on.

Reuse the existing run recipe rather than copying its boot/install/launch
sequence:

```make
design-app: ; @$(MAKE) run-ios LAUNCH_ARGS="-designGallery YES"
```

## Two traps in the gallery itself

- **Its strings will end up in your localisation catalogue.** Five token names
  ("micro", "aspect · 9:16", a picker's "Sheet") landed in a 36-language
  catalogue as *awaiting translation* on the first run. Use `Text(verbatim:)`
  throughout and pass a `String` variable where an API takes a
  `LocalizedStringKey`.
- **Name properties so your own guards do not fire.** A lint that catches
  untranslated UI text keys on property names like `title` — call the gallery's
  tab label `tab`, and say in a comment which of the two it is.

## The grid overlay is the only proof two screens agree

```swift
func gridOverlay(_ show: Bool = GridOverlay.isOn) -> some View {
    overlay { if show { GridOverlay().allowsHitTesting(false) } }
}
```

Twelve translucent columns plus the margins, drawn over the live app. A gallery
proves one screen is tidy; the overlay over two different screens is what shows
that a chip row and a tab row land on the same vertical lines.

## When to reach for the real libraries

- **swift-snapshot-testing** (Point-Free) — when you want *failing tests* on
  visual regression rather than files to look at. The `ImageRenderer` sheet is
  a document; a snapshot test is a gate. Both is fine; start with the document.
- **Inject + InjectionIII** — hot reload while iterating on layout. Saves real
  time on a big app; adds a build-setting to explain to everyone else.
- **figma-export** (RedMadRobot) if the designer lives in Figma and there is one
  platform; **Style Dictionary** if there are two or more and tokens should be
  generated from one JSON.
