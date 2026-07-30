# Screenshots — capture, frame, upload

Upload goes through the official API, which finalizes the multipart commit correctly. **Never upload
screenshots through an automation browser** — see the finalize trap in [browser.md](browser.md).

## Contents
- [Upload (the part you always need)](#upload-the-part-you-always-need)
- [Sizes](#sizes)
- [Capture from a simulator](#capture-from-a-simulator)
- [Framing](#framing)
- [Multi-locale](#multi-locale)

---

## Upload (the part you always need)

```bash
asc localizations list --version "VERSION_ID" --output table       # → LOC_ID per locale
asc screenshots validate --path "./screenshots/iphone" --device-type "IPHONE_65" --output table
asc screenshots upload --version-localization "LOC_ID" \
  --path "./screenshots/iphone" --device-type "IPHONE_65" --output json
asc screenshots list --version-localization "LOC_ID" --output table   # verify
```

App + version shorthand instead of the localization ID:

```bash
asc screenshots upload --app "APP_ID" --version "1.0" --path "./screenshots" --device-type "IPHONE_65"
```

For reviewed multi-locale batches, `plan`/`apply` accounts for screenshots already on the remote
side (append limits):

```bash
asc screenshots plan  --app "APP_ID" --version "1.0" --review-output-dir "./screenshots/review" --output json
asc screenshots apply --app "APP_ID" --version "1.0" --review-output-dir "./screenshots/review" --confirm
```

Delete: `asc screenshots delete --id "SCREENSHOT_ID" --confirm`.

---

## Sizes

One iPhone set is enough — ASC reuses it for the other iPhone sizes. Add an iPad set only if the app
supports iPad.

| Slot | Pixels |
|---|---|
| `IPHONE_65` | 1284×2778 (also accepts 1242×2688) |
| `IPHONE_69` | 1320×2868 |
| `IPAD_PRO_3GEN_129` | 2048×2732 |

`asc screenshots sizes --all --output table` for the full matrix.

Requirements: PNG or JPEG, RGB, **no alpha channel**. A stray alpha channel makes ASC reject or hang
on the asset. Flatten with `sips -s format jpeg in.png --out out.jpg`.

---

## Capture from a simulator

Plain AppleScript tapping does **not** work — System Events `click at` is TCC-blocked; only
`key code` gets through. Everything below is the way around that, in the order to try it.

### 1. Pick the device — it decides the pixel size

```bash
xcrun simctl list devices available | grep "iPhone 17"
xcrun simctl boot "$UDID"
xcrun simctl io "$UDID" screenshot out.png
sips -g pixelWidth -g pixelHeight out.png       # verify before uploading
```

**iPhone 17 Pro Max renders exactly 1320×2868 = the 6.9" App Store slot.** No resizing needed.

### 2. Grant permissions instead of tapping the system dialog

```bash
xcrun simctl privacy "$UDID" grant photos com.example.app     # also: microphone, location, contacts, all
xcrun simctl addmedia "$UDID" ./clip1.mp4 ./photo.jpg         # fill the photo library
xcrun simctl location "$UDID" set 36.5,32.1                   # realistic "near you" distances
```

⚠️ **There is no `camera` service** — run `xcrun simctl privacy` with no args and read the list:
calendar, contacts, location, photos, media-library, microphone, motion, reminders, `all`. And
`grant all` writes a single `kTCCServiceAll` row that the camera check does **not** consult, so a
camera app still shows the permission alert in every frame. Write the row yourself:

```bash
TCC=~/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db
sqlite3 "$TCC" "INSERT OR REPLACE INTO access
  (service,client,client_type,auth_value,auth_reason,auth_version,indirect_object_identifier)
  VALUES ('kTCCServiceCamera','com.example.app',0,2,2,1,'UNUSED');"
```

`grant` kills the system prompt entirely. ⚠️ But it does **not** dismiss an app's *own* onboarding
screen — many apps render "Allow Access" themselves and only check the real status after you tap it.
If the app only reads the status at launch (common), a **cold relaunch after granting** is enough and
saves you AXe: `simctl terminate` + `simctl launch` — a process that was already running cached the
pre-grant status. Confirm the grant actually landed in the sim's TCC.db (`~/Library/Developer/
CoreSimulator/Devices/<udid>/data/Library/TCC/TCC.db` → `SELECT service,client,auth_value FROM access`,
`auth_value=2` = allowed) before blaming the app. Only if the app re-checks live (not at launch) do you
need AXe. ⚠️ `addmedia`-injected images are **not** flagged as *Screenshots* — they never land in the
Screenshots smart album, so a screenshot-cleaner feature reads empty no matter how many you add.

### 3. AXe — real taps via the Accessibility API

[AXe](https://github.com/cameroncooke/AXe) drives the simulator through accessibility, so it clicks
what `simctl` can't. This is also what `asc screenshots run` uses under the hood.

```bash
brew install cameroncooke/axe/axe
axe describe-ui --udid "$UDID"                  # full UI tree as JSON
axe tap --id "search_field" --udid "$UDID"
axe tap -x 660 -y 1790 --udid "$UDID"           # coordinates in POINTS, not pixels
axe type "wwdc" --udid "$UDID"
axe swipe --start-x 660 --start-y 2000 --end-x 660 --end-y 800 --udid "$UDID"
```

The tree is deep — filter it down to the tappable things:

```bash
axe describe-ui --udid "$UDID" | jq -r '[.. | objects
  | select(.AXLabel != null and .AXLabel != "")
  | {label: .AXLabel, type, frame: .AXFrame}] | unique | .[]
  | "\(.type)\t\(.label)\t\(.frame)"'
```

⚠️ `AXFrame` is in **points** (a 1320-px-wide screen reports 440), and elements with **negative X are
off-screen** — a sidebar or an adjacent page, not something you can tap. Screenshot after each tap;
the accessibility tree updates faster than the rendered UI, so a tree that already shows the next
screen doesn't prove the screenshot will.

### 4. State injection (when the app cooperates)

- Skip onboarding by editing the sim container's state JSON:
  `xcrun simctl get_app_container "$UDID" <bundle> data` → `…/Documents/<state>.json`, set
  `profile.onboarded=true`.
- Preselect a screen via a launch env var the app reads — e.g. `AppRouter.init` reads
  `ProcessInfo…environment["CF_TAB"]`, so launch with
  `SIMCTL_CHILD_CF_TAB=beaches xcrun simctl launch …`. A plain `TabView` with no router takes the same
  hook: `TabView(selection:)` + `.tag(n)` seeded from `Int(ProcessInfo…environment["SS_TAB"] ?? "")` —
  guarded, no prod effect.
- Fix number/date formatting to the **target store's** locale on a single-language shot without
  reconfiguring the sim: pass `-AppleLocale en_US -AppleLanguages "(en)"` as launch args (turns
  `675,52 GB` into `675.52 GB` for the US store). Launch args take effect even where the
  `SIMCTL_CHILD_AppleLanguages` env route does not (see Multi-locale).

### 4b. Camera apps — feed the viewfinder a video instead of a camera

The Simulator has no camera, so `AVCaptureVideoPreviewLayer` renders a black rectangle and every
screenshot of a camera app looks broken. You cannot fix that from the outside — the layer only
shows what the capture session produces. Add a DEBUG-only stand-in **inside the app**:

```swift
// StubCamera.swift — the whole file wrapped in #if DEBUG
private func tick() {                       // AVAssetReader over a file, on a Timer
    guard let sample = output.copyNextSampleBuffer() else { reopenReader(); return }  // loop at EOF
    guard let pixel = CMSampleBufferGetImageBuffer(sample) else { return }
    let img = CIImage(cvPixelBuffer: pixel)
    if let cg = ci.createCGImage(img, from: img.extent) { layer.contents = cg }
}
```

```swift
// at the viewfinder call site
if let stub = stubCameraURL { StubCameraView(url: stub) }   // env var → URL, nil in Release
else if cam.authorized { CameraPreview(session: cam.session) }
```

Push the clip into the sandbox and point the app at it:

```bash
DATA=$(xcrun simctl get_app_container "$UDID" com.example.app data)
cp clip.mov "$DATA/Documents/"
SIMCTL_CHILD_UITEST_CAMERA_VIDEO="$DATA/Documents/clip.mov" xcrun simctl launch "$UDID" com.example.app
```

Three things that decide whether the result looks real:

- **Pad the clip to the device's aspect ratio first.** `resizeAspectFill` crops the sides of a
  1080×1920 clip on a 1320×2868 screen (~9% each side) and slices through anything near the edges —
  a burnt-in HUD comes out cut mid-word, which reads as a rendering bug.
  `ffmpeg -vf "pad=1080:2346:0:213:black"` makes it 0.4603 and nothing is cropped; the bars land
  under the app's own top and bottom chrome.
- **Cut a short loop around a good moment** (`-ss 19.5 -t 5`) so any frame is usable — otherwise the
  frame you get depends on how long the settle delay happened to be.
- **Decide whether to also feed the tracker.** Feeding the same `CMSampleBuffer` to a Vision entry
  point makes overlays genuinely computed from the footage. But if the clip is the app's own
  recording with the HUD already burnt in, that draws a *second* skeleton on top of the first —
  display-only is correct there. Same for any live panel the recording already contains: turn the
  app's own copy off (a `@AppStorage` flag flipped via `simctl spawn … defaults write`).

### 4c. App Preview video — composite it, don't screen-record it

App Previews must be a screen recording of the app, 15-30 s (a 10 s file is rejected on
ingest). But `simctl io recordVideo` drops frames whenever the app is doing per-frame work,
and AXe cannot drive it either — `axe tap` and `axe describe-ui` both time out while a busy
app starves the accessibility server. Compositing avoids both problems.

Lift the UI as a real alpha matte by **difference matting** — capture the same screen twice,
over a black plate and a white plate:

```
over black:  cb = C·a            over white:  cw = C·a + (1-a)
a = 1 - (cw - cb)                C = cb / a
```

That reproduces translucency exactly — blurred pills, frosted panels, antialiased text —
where a chroma key leaves fringing. Then let ffmpeg lay it over the footage at a clean 30 fps:

```bash
ffmpeg -ss "$START" -t 16 -i source.mov -i ui_overlay.png \
  -filter_complex "[0:v]scale=1320:2868,setsar=1[bg];[bg][1:v]overlay=0:0:format=auto[v]" \
  -map "[v]" -map 0:a -c:v libx264 -crf 21 -pix_fmt yuv420p -r 30 -c:a aac out.mov
```

Three traps:
- **zsh eats the filter string.** `"color=c=$C:s=1280x720:..."` — `$C:s=` is a parameter
  *modifier* in zsh, so the colour silently becomes `black20` and ffmpeg fails. Brace it:
  `${C}`. The symptom is indistinguishable from "the app ignores my file".
- **Plates must outlast the capture settle delay** if the app's video loop is at all fragile.
- **`APP_IPHONE_69` is not a valid preview type** even though it is a valid *screenshot*
  type; use `APP_IPHONE_67`. Upload with `asc video-previews upload --replace`.

### 5. `ImageRenderer` — render views to PNG with no app at all

The fastest loop by far, and the one to reach for when iterating on a single screen. A unit test
renders a SwiftUI view straight to PNG: no app launch, no navigation, no permissions, deterministic.
**Two views rendered in 0.8 s** on a real project.

```swift
@MainActor
final class SnapshotRenderTests: XCTestCase {
    private static let outputDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/previews", isDirectory: true)

    func testRenderLaunchView() throws {
        let renderer = ImageRenderer(content: LaunchView().frame(width: 440, height: 956))
        renderer.scale = 3                                   // 440×956 @3x = 1320×2868 = 6.9" slot
        let data = try XCTUnwrap(renderer.uiImage?.pngData())
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        try data.write(to: Self.outputDir.appendingPathComponent("LaunchView.png"))
    }
}
```

```bash
xcodebuild test -project App.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,id=UDID' \
  -only-testing:AppTests/SnapshotRenderTests ARCHS=arm64 CODE_SIGNING_ALLOWED=NO
```

Points × scale = pixels, so pick the frame to land on an App Store slot exactly. `#filePath`
resolves to the source tree and the simulator writes to host paths, so the PNGs appear right in the
repo — no container spelunking.

Two prerequisites bite on first run:
- A test target that does `@testable import App` inherits **none** of the app's build settings.
  Anything the app needs to find its modules (`SWIFT_INCLUDE_PATHS` for a uniffi/clang module map,
  custom `OTHER_SWIFT_FLAGS`) must be repeated on the test target, or the build dies with
  `Unable to resolve module dependency`.
- The whole test target must compile. A stale broken test elsewhere blocks yours — including ones
  that never compiled because the target was already unbuildable.

### 6. Xcode Canvas (`#Preview`)

Interactive, good for live tweaking, poor for automation: Canvas compiles with the same toolchain as
a real build (plus any Rust/C static libs), so it is minutes, not seconds. Requires `#Preview` blocks
to exist in the project at all — plenty of codebases have none.

Drivable via GUI automation when needed (verified): `open -a Xcode File.swift`, then
`Editor ▸ Canvas` through the menu — the ⌘⌥↩ shortcut is unreliable. ⚠️ **Do not send ⌘⌥P to
"resume"** — in current Xcode that opens the *Add Files* picker, and a blind Return would add
whatever is selected to the project. Click the Canvas resume button instead (or press Escape first
if a sheet appeared: `key code 53`, then verify with `count of sheets of window 1` = 0). Requires
Accessibility permission (`osascript -e 'tell application "System Events" to return (UI elements enabled)'`
→ `true`) and Screen Recording for `screencapture`. Note the Canvas device is chosen by the scheme's
**destination**: with a physical iPhone selected, Canvas won't render a simulator preview.

### 7. Framing real device screenshots

The best store screenshots are shot on the user's own phone with their own footage, not staged in a
simulator. Ask for raw device screenshots and frame them yourself:

```python
STATUS_BAR = 132        # iOS status bar at 3x — crop it, the clock and battery add nothing
shot = shot.crop((0, STATUS_BAR, shot.width, shot.height))
shot = shot.resize((1040, round(shot.height * 1040 / shot.width)), Image.LANCZOS)
# then paste onto a 1284x2778 canvas under a two-line caption
```

Rules that matter:
- **Caption first, screenshot second.** Most people decide from the first two cards in search
  results, and they read the caption, not the UI.
- Burn captions into the store images (Apple has no text layer), but on a website keep them in HTML
  so they localise — same source screenshots, two treatments.
- Match the site's typography and put a thin brand-gradient rule under the caption; the set then
  reads as one system with the landing page.
- Order by distinctiveness, not by app navigation: lead with the screen no competitor has.
- Device screenshots are 1290×2796 on current iPhones but the slot may be 1284×2778 — scale, never
  stretch, and verify with `sips -g pixelWidth -g pixelHeight`.
- Screenshots pasted into a chat are downscaled copies. Always work from the original file.

Verify the whole set before uploading — it reports per-file readiness, not just the first error:

```bash
asc screenshots validate --path ./store-shots --device-type "IPHONE_65" --output table
```

A successful upload reports `"state": "COMPLETE"` for every file. Anything else means the asset did
not finalise, and submission will fail later with a misleading message (see [browser.md](browser.md)).

### 8. Checking the iPad layout without a rebuild

An `iphonesimulator` build installs and runs on an **iPad simulator** as-is, which is enough to see
whether the iPad layout is presentable before committing to iPad screenshots:

```bash
xcrun simctl boot "$IPAD_UDID"
xcrun simctl install "$IPAD_UDID" path/to/App.app
xcrun simctl launch "$IPAD_UDID" com.example.app
xcrun simctl io "$IPAD_UDID" screenshot ipad.png     # 2064x2752 on iPad Pro 13"
```

A stretched iPhone layout (full-width buttons, oceans of empty space) is a rejection risk. Either
adapt the UI or ship iPhone-only — see the screenshots section in [readiness.md](readiness.md).

### 9. Content matters more than mechanics

The simulator's stock library is a handful of Apple stock photos; `ffmpeg` test patterns are SMPTE
colour bars. Both make technically valid, commercially useless screenshots. Load **real** footage
with `addmedia` before capturing anything you intend to ship.

Icon: the 1024×1024 `AppIcon` (`icon_1024.png`) is the App Store icon — no separate export needed.

### Plan-driven capture

```bash
asc screenshots capture --bundle-id "com.example.app" --name home --udid "$UDID" \
  --output-dir "./screenshots/raw" --output json
asc screenshots run --plan ".asc/screenshots.json" --udid "$UDID" --output json
```

Minimal `.asc/screenshots.json`:

```json
{
  "version": 1,
  "app": { "bundle_id": "com.example.app", "udid": "booted", "output_dir": "./screenshots/raw" },
  "steps": [
    { "action": "launch" },
    { "action": "wait", "duration_ms": 800 },
    { "action": "screenshot", "name": "home" }
  ]
}
```

---

## Framing

Framing is pinned to Koubou `0.18.1` for deterministic output:

```bash
pip install koubou==0.18.1 && kou --version
kou setup-frames                      # once, needs network — downloads device frames
asc screenshots list-frame-devices --output json
asc screenshots frame --input "./screenshots/raw/home.png" \
  --output-dir "./screenshots/framed" --device "iphone-air" --output json
```

Devices: `iphone-air` (default), `iphone-17-pro`, `iphone-17-pro-max`, `iphone-16e`, `iphone-17`, `mac`.

Review before uploading a batch:

```bash
asc screenshots review-generate --framed-dir "./screenshots/framed" --output-dir "./screenshots/review"
asc screenshots review-open --output-dir "./screenshots/review"
asc screenshots review-approve --all-ready --output-dir "./screenshots/review"
```

For captioned marketing frames beyond what Koubou does, a custom compositor works fine — e.g.
`docs/store/compose_ios.py` in caretta-friends. Resize to the exact slot spec and flatten alpha.

---

## Multi-locale

**Do not** use `xcrun simctl launch -e AppleLanguages` — the `-e` env pattern doesn't reliably switch
app language. Use one simulator UDID per locale with simulator-wide defaults:

```bash
xcrun simctl boot "$UDID" || true
xcrun simctl spawn "$UDID" defaults write NSGlobalDomain AppleLanguages -array "de"
xcrun simctl spawn "$UDID" defaults write NSGlobalDomain AppleLocale -string "de_DE"
xcrun simctl terminate "$UDID" "com.example.app" || true
asc screenshots capture --bundle-id "com.example.app" --name home --udid "$UDID" \
  --output-dir "./screenshots/raw/de-DE" --output json
```

Run locales in parallel (one background job per UDID), then frame in parallel, then upload per
locale with that locale's `LOC_ID`. Launching manually outside `asc screenshots capture` does accept
launch arguments: `xcrun simctl launch "$UDID" "com.example.app" -AppleLanguages "(de)" -AppleLocale "de_DE"`.

---

*`capture`, `frame`, `run`, `plan`, `apply` are experimental in asc — verify paths with
`asc screenshots --help` and flag the experimental status in handoff notes. `upload`, `list`,
`validate`, `sizes`, `delete` are stable API commands.*
