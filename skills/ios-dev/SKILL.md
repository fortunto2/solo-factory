---
name: solo-ios-dev
description: Build iPhone/iOS apps — native SwiftUI or Kotlin-Multiplatform hybrid. Use when scaffolding an iOS app, writing SwiftUI/ARKit/MapLibre features, wiring the Claude Code ↔ Xcode workflow, building or installing on a physical device, or setting up a project so it survives its first App Store upload (product name, orientations, encryption, dSYM, xcodeproj tracking). For TestFlight, submission, screenshots and store metadata use solo-ios-release instead.
license: MIT
metadata:
  author: fortunto2
  version: "2.0.0"
  openclaw:
    emoji: "📱"
---

# iOS / iPhone app

Reference + checklist for building and shipping iPhone apps. Read the stack, copy the example's
patterns, and run the publishing checklist BEFORE the first App Store upload — it prevents the
rejections below that each cost a re-archive.

## Stack (solopreneur templates)

- **Native Swift:** `~/startups/solopreneur/solo-factory/templates/stacks/ios-swift.yaml`
  — Swift 6 + SwiftUI, SPM, **xcodegen** (`project.yml` → generated `.xcodeproj`, **do not commit the `.xcodeproj`**),
  SwiftData (not Core Data), StoreKit 2, `.xcstrings` string catalogs, SwiftLint + swift-format, lefthook,
  App Store Connect CLI `asc` (`brew install asc`).
- **KMP hybrid (shared logic, cross-platform):** `~/startups/solopreneur/solo-factory/templates/stacks/kotlin-multiplatform.yaml`
  — Kotlin Multiplatform + Compose Multiplatform, Gradle version catalog, expect/actual for platform code.

Pick native Swift for iOS-only; KMP when Android shares the domain/UI. The `ios-swift.yaml` carries the
full detail (house patterns, `asc` CLI commands, Xcode MCP tools, on-device-AI packages) — read it when
scaffolding; the sections below promote the highest-leverage bits.

## House conventions (native Swift, Swift 6)

Match these so generated code fits the codebase (from `ios-swift.yaml` patterns, learned via SoloGraph):

- **`@Observable @MainActor final class`** view models — NOT `ObservableObject`. `@State private var vm = MyVM()` in the view; inject services via init (DI).
- **`actor`** for heavy/ML/data services (own isolation); `@Observable @MainActor final class` for UI-facing services (recording, audio). **A protocol for every service** (`Services/Protocols/FooServiceProtocol.swift`) → mocking + swapping.
- **SwiftData `@Model`** for persistence (NOT Core Data, NOT Firebase). Plain structs for transient data/config/API responses. **Local-first.**
- **async/await everywhere, no Combine** for new code. Timer callbacks → `Task { @MainActor in … }`.
- **Permissions:** `requestPermission() async -> Bool` in the protocol; request before use; "Open Settings" alert on denied; `#if os(iOS)` around `AVAudioSession`/`UIApplication` for macOS compat.
- **Dir layout:** `App/` `Models/` `Views/` `ViewModels/` `Services/` `Services/Protocols/` `Extensions/` `Resources/`. MVVM.
- i18n: **String Catalog** (`.xcstrings`, Xcode 16). Lint: **SwiftLint** + **swift-format**; hooks via **lefthook**. Tests: **Swift Testing** (`@Test`) new, XCTest legacy. IAP: **StoreKit 2**. Analytics: **PostHog** (EU).

## Claude Code ↔ Xcode workflow

- **Xcode MCP bridge** (Xcode 26.3+, `xcrun mcpbridge`; enable in Xcode → Settings → Intelligence → MCP Server):
  Claude Code can build/test/render **natively** — `BuildProject`, `RunAllTests`/`RunSomeTests`,
  **`RenderPreview`** (SwiftUI preview → image, visual verification without a full run), `DocumentationSearch`
  (Apple docs + WWDC), `ExecuteSnippet` (Swift REPL), `GetBuildLog`. Prefer these when available.
- **Simulator visual smoke test** (no device needed for non-AR/non-camera screens):
  ```bash
  xcrun simctl boot 'iPhone 16' 2>/dev/null || true
  xcrun simctl install booted <App.app>; xcrun simctl launch booted <bundle.id>
  xcrun simctl io booted screenshot /tmp/sim.png
  xcrun simctl spawn booted log stream --style compact --timeout 10
  ```
- ARKit/camera/real-GPS features can't be tested in the Simulator — build to verify compile, test on device.

## The feedback loop: XcodeBuildMCP (install this first)

Without a loop the agent writes blind. In the browser it opens a page; on iOS
it needs the simulator. Two MCP servers cover it, and they complement rather
than overlap.

**XcodeBuildMCP** (`npx -y xcodebuildmcp@latest mcp`) — headless build, run,
test and UI automation. The part that matters most: `snapshot_ui` returns a
semantic tree with **element references**, and `tap` takes a reference rather
than a coordinate:

```
e244|tap|button|Make a montage from the selected period
e189|tap|button|Days     e247|tap|button|Audio
```

That removes the whole class of failure a coordinate-driven walker suffers —
`describe-ui`-style dumps include views belonging to sheets *underneath*, off
to the side of the screen, and a tap aimed there dismisses whatever is on top.
Also worth having: `wait_for_ui` with a predicate instead of polling loops,
`record_sim_video`, coverage straight out of `xcresult`, and `launch_app_sim`
capturing runtime + os_log to files on its own.

**Enable the workflows you need — the default is only 24 tools.** UI
automation and the device workflow are off unless you ask:

```json
"xcodebuild": {
  "command": "npx",
  "args": ["-y", "xcodebuildmcp@latest", "mcp"],
  "env": {
    "XCODEBUILDMCP_ENABLED_WORKFLOWS":
      "session-management,simulator,simulator-management,ui-automation,device,utilities,project-discovery"
  }
}
```

With that it registers 44 tools instead of 24. The variable is not in `--help`;
it is `XCODEBUILDMCP_ENABLED_WORKFLOWS`, found by grepping the package.

Call `session_set_defaults` once (project, scheme, simulator id, bundle id,
`persist: true`) — it writes `.xcodebuildmcp/config.yaml` in the repo, and
every later call can go with empty arguments. Call `session_show_defaults`
before the first build of a session; the server asks for this explicitly.

**Xcode's own bridge** (`xcrun mcpbridge`, Xcode 26.3+) — 20 tools over XPC,
including rendering a SwiftUI Preview without building and running the whole
app, plus a Swift REPL. It needs **Xcode running with the project open**, so it
is no use in a background or CI run — but for layout work it turns a 3–4 minute
build-install-launch-tap-screenshot cycle into seconds. The two are
complementary: XcodeBuildMCP for the headless loop, mcpbridge for previews and
docs.

**Apple RAG MCP** (official Swift docs and HIG over RAG) is a nice-to-have —
context7 already answers most API questions, and HIG comes up once a day, not
once a minute.

## Driving the Simulator, and trusting the numbers

Learned the hard way on a video app; the traps are not app-specific.

**Use `idb`, not `axe`.** Measured on the same tap, same simulator: `idb ui tap` **0.2s**,
`axe tap` **1.8–12s** (it varies with load). `describe-ui` is 0.9s vs 1.3–6s. Same coordinate
space — points, not pixels — so it is a drop-in swap.

```bash
brew tap facebook/fb && brew trust facebook/fb/idb-companion
brew install idb-companion && python3 -m pip install fb-idb   # client lands in ~/Library/Python/*/bin
idb connect <UDID>
idb ui tap --udid <UDID> 200 60          # points
idb ui describe-all --udid <UDID>        # JSON, has AXLabel/frame
```

**Calibrate the harness or your timings are fiction.** A walk-the-path script reported a 108s
user journey; the real figure was ~10s and the rest was the automation tool's own latency —
seven taps at 5–12s each. Measure one probe at startup, subtract it from every step, and print
"user waits" and "harness overhead" as two separate numbers. A stopwatch heavier than the thing
it times will send you hunting regressions that do not exist.

**Wait on facts, not on accessibility.** Modal screens report nothing to `describe-ui`, so a
finished job looks like a timeout. Wait on the artefact instead: the file on disk, the row in the
database, the count from a debug endpoint. And a stalled encode stops growing just like a finished
one — check the file is *playable* (`ffprobe`), not merely still.

## CPU traps worth checking in any SwiftUI app

- **A dead `@EnvironmentObject` still subscribes.** One unused declaration in the root view
  invalidates the whole tree on every `@Published` change. `grep` each injected object for a
  second mention; if there is none, delete the declaration.
- **Publishing progress per item redraws per item.** A field containing a changing path always
  compares unequal, so a tight loop invalidates ~20×/s for as long as it runs. Throttle to ~4/s —
  no screen shows more.
- **Nothing asks about heat or battery by default.** `grep -rn "thermalState\|isLowPowerMode" Sources/`
  returning zero in an app that decodes video or runs Vision means it runs flat out on a hot phone.
  Back off at `.serious`, stop in Low Power Mode.
- **Background work restarting on every launch is a development tax.** A debug build is launched
  dozens of times an hour; gate the auto-start behind an env var and turn it on deliberately.
- **The Simulator window losing focus is not backgrounding.** An app keeps decoding while you work
  in another macOS app — measured 51–89% CPU. Pressing Home *inside* iOS drops it to 0%. When the
  machine feels hot, background the app in iOS or terminate it; do not go looking for a leak.

## Concurrency traps in export/render paths

- **A one-second timestamp is not a unique filename.** Two exports started in the same second
  resolve to the same path and `AVAssetExportSession` fails the second with "Cannot Save" /
  "Cannot create file". Checking `fileExists` first does *not* fix it — both find the name free.
  Use an atomic counter. Reproduce with two concurrent exports before and after.

## Debugging a stall on a real device (no screenshots there)

`idevicescreenshot` needs the developer disk image, and on a modern iOS it
often refuses to mount — the same reason `xcodebuild -destination 'id=…'`
fails with "developer disk image could not be mounted". So the simulator
playbook (tap, screenshot, look) does not transfer. Make the app report
instead:

- **A status endpoint.** If the app already runs a local HTTP server (MCP,
  debug bridge), add `GET /status` returning what it is doing: stage, percent,
  items done/total, which file is in hand, seconds elapsed, and a short list
  of completed steps with per-step timings. Two `curl`s a few seconds apart
  separate "slow" from "stuck" and name the culprit. This turned a multi-hour
  guessing game into a two-minute diagnosis.
- **A step trace.** One `os_log` line per step with the gap since the previous
  one (`▶︎ collected 50 clips +0.1s`). Feed the same marks into the status
  payload so the log and the endpoint cannot disagree.
- **Console when you need everything:** `xcrun devicectl device process launch
  --device <udid> --console --terminate-existing <bundle>`. It restarts the
  app, so it cannot observe a run already in progress — start it first.

**Install without Xcode's device destination** (works while the DDI does not):

```bash
xcodebuild -destination 'generic/platform=iOS' -configuration Debug \
  -allowProvisioningUpdates -derivedDataPath /tmp/dd-device build
xcrun devicectl device install app --device <udid> \
  /tmp/dd-device/Build/Products/Debug-iphoneos/App.app
xcrun devicectl device process launch --device <udid> --terminate-existing <bundle>
```

The phone must be **unlocked** for the install, and the developer certificate
trusted once under Settings → General → VPN & Device Management (it needs
network to verify). And note: **install does not relaunch the app** — a new
build with new logging looks like it changed nothing until you launch it.

## Timeouts: the ones that do not work

- **A semaphore with no deadline is a hang.** `sema.wait()` around a PhotoKit
  or network callback parks that thread forever when the callback never comes.
  Use `sema.wait(timeout:)`, log which item you gave up on, and carry on —
  losing one item beats losing the job.
- **Racing inside a task group does not time anything out.** A group awaits its
  children on the way out, and cancellation is cooperative: a synchronous call
  ignores it, so the group waits for exactly the task you were escaping.
  Measured: 1 of 50 items after 226s with a "75s deadline" in place. Race
  through a continuation instead, resumed once under a lock by whichever side
  finishes first; the stuck work keeps running on its own thread and is
  dropped from the result.
- **Bound `URLSession`.** The shared session waits 60s per request by default;
  an agent loop of three turns is three minutes of silence. Set
  `timeoutInterval`, and log the status and first bytes of any non-200 —
  otherwise "the provider refused" is indistinguishable from "the feature is
  broken".

## PhotoKit costs, and where they hide

- **`deliveryMode` decides whether you download.** `.highQualityFormat` means
  the original, and for anything in iCloud that is a full download before your
  code runs. If the work is analysis on small frames, ask for `.fastFormat`
  and let Photos hand over whatever it has closest. Measured on a real
  library: 19.5s → 3.1s per clip, six times faster.
- **Split any asset cache by that intent**, or the cheap path and the original
  path shadow each other. Getting this wrong made previews re-fetch every
  original three times over.
- **A synchronous `requestImage` can return nil where the async one works.**
  40 of 40 thumbnails came back empty synchronously and all 40 arrived through
  `requestImage` with a continuation. If thumbnails are mysteriously missing,
  this is the first thing to check.
- **`progressHandler` is the only way to see an iCloud download.** Without it
  the UI claims to be analysing while it is really waiting on the network —
  and add it to *every* path that resolves assets, not just the obvious one.

## SwiftUI layout traps that cost a screenshot to find

- **`GeometryReader` inside a stack takes the whole height** and leaves its
  siblings at zero, drawing them under whatever comes next. Use a plain
  `ProgressView` or a fixed frame instead of measuring.
- **A bare `LazyVGrid` lays out every item** and overflows its frame. Put it in
  a `ScrollView` with a fixed height when the count is unbounded.
- **`^[\(n) item](inflect: true)` only expands in a localised string.** Built
  as a plain `String` it reaches the screen as markup — a user reported seeing
  "1 conflict true and some brackets".
- **`.sheet` modifiers do not stack.** Several on one view and only the last
  works; use one `.sheet(item:)` with an enum.
- **Dismissing a sheet destroys its `@State`.** If work continues behind it,
  keep the run's state in an `@Observable` outside the view, or coming back
  offers to start over while the first run is still going.

## Accessibility-tree automation on the simulator

`describe-ui` returns the whole hierarchy, **including views of sheets
underneath**. Those sit off to the side — x=478 on a 402pt screen — so a tap
aimed at the topmost match by y can land on nothing and dismiss what is on
top. Filter candidates to the visible width, and clamp a centre that falls
past the edge (a long label has a frame wider than the phone). Chips inside a
horizontal `ScrollView` are not exposed at all — assert on their container
instead.

## Example project — Caretta Friends (KMP + hybrid iOS)

`~/startups/active/caretta-friends` — real shipped app. Study it for the **hybrid pattern**:

- **iOS = native SwiftUI shell hosting shared Compose screens.** `iosApp/iosApp/ContentView.swift`
  is a SwiftUI `TabView` + per-tab `NavigationStack`; each content screen is a shared Compose
  `UIViewController` from `IosEntry.kt` (`ComposeUIViewController { ... }`). Native Swift owns the
  chrome (tab bar, nav), camera (`Camera/CameraCaptureView.swift`), map (`Map/MapLibreView.swift`,
  MapLibre + OSM), and AR (`AR/ARNestView.swift`, ARKit).
- **Bridge:** `composeApp/src/iosMain/.../IosEntry.kt` exposes VC factories + plain functions
  (`mapPoints()`, `takeMapFocus()`, `currentStrings()`). Swift calls `IosEntryKt.*`.
- **Gotchas file:** the project's `docs/plan.md` + `CLAUDE.md` list KMP-specific traps
  (Map-backed i18n to dodge an ART VerifyError; `topmostViewController()` because `keyWindow` is nil on
  iOS 15+; the Kotlin-2.3 iosArm64 ABI trap — don't add libs built with a newer Kotlin to commonMain).
- **ARKit geo-AR:** `ARGeoAnchor` (Apple location anchors) only works in select cities — for anywhere
  else use `ARWorldTrackingConfiguration` + `.gravityAndHeading`, take one GPS fix as origin, place
  each point at its East/North (ENU) offset (`world = (east, 0, -north)`), and project world→screen
  each frame for SwiftUI overlays. LiDAR (`sceneReconstruction = .mesh` + `.occlusion`) is a free
  upgrade on Pro devices, degrades silently elsewhere. ARKit does NOT run in the Simulator — build to
  verify compile, test on a device. If markers land in the mirrored direction, flip the north/east sign.

## Example projects — native SwiftUI (xcodegen stack)

These follow the `ios-swift.yaml` stack: SwiftUI + SPM + **xcodegen** (`project.yml` is the source of
truth; the `.xcodeproj` is generated and NOT committed). Copy their `project.yml`, folder layout, and
lefthook/SwiftLint setup for a new native app. All under `~/startups/active/`:

- **FaceAlarm** (`FaceAlarm/ios-app`, also a `kotlin-app`) — alarm app; the "FaceAlarm pattern" for
  baked-in localized Markdown content (per-language `.md` files in resources) is reused elsewhere.
- **life2film** (`life2film/app`) — video/photo → film.
- **photo-cleaner**, **photosweep** — Photos-library cleanup (PhotoKit).
- **reelcam** — camera/reels capture. **receiptbrain** — receipt OCR (Vision). **currencypal** —
  currency. **thinkoud** — notes/AI.

Each has `project.yml` + a generated `.xcodeproj` (regenerate with `xcodegen`). Contrast with Caretta,
which is hand-maintained (no `project.yml`) → its `.xcodeproj` IS tracked.

## App Store publishing checklist (run before first upload)

Each item below was a real upload rejection or a recurring prompt. Fix in the project up front.

1. **Product name ≠ "iosApp".** The template default `PRODUCT_NAME = $(TARGET_NAME) = iosApp` is a
   globally-taken App Store name → *"App Record Creation failed… name already in use."* Set a unique
   `PRODUCT_NAME` (e.g. `CarettaFriends`, no spaces) in the app target's Debug+Release configs; keep the
   pretty home-screen name in `Info.plist` `CFBundleDisplayName` ("Caretta Friends").
2. **Orientations vs device family (error 90474).** A portrait-only app that targets iPad
   (`TARGETED_DEVICE_FAMILY = "1,2"`) must declare all four orientations for iPad multitasking. For a
   portrait phone app, set **iPhone-only** `TARGETED_DEVICE_FAMILY = "1"` instead.
3. **Encryption prompt every submission.** HTTPS/OS-only crypto is exempt → add
   `ITSAppUsesNonExemptEncryption = false` (Boolean) to `Info.plist`. App Store Connect stops asking.
4. **"Upload Symbols Failed — dSYM for X.framework".** Prebuilt SPM/binary frameworks (e.g. MapLibre
   `maplibre-gl-native-distribution`) ship no dSYM — this is a **harmless warning**, the upload
   succeeds. Only that framework's internal crash frames won't symbolicate. Ignore it.
5. **xcodeproj tracking.** If the project uses **xcodegen** (has `project.yml`) → commit `project.yml`,
   gitignore the `.xcodeproj`. If it's **hand-maintained** (no generator) → **track `project.pbxproj`**
   (ignore only `**/xcuserdata/`); otherwise name/orientation/source-file changes vanish on a fresh clone.
   Adding a Swift file to a hand-maintained project means editing the pbxproj: a `PBXFileReference`, a
   `PBXBuildFile`, a group child, and the `PBXSourcesBuildPhase` entry (use fresh 24-hex IDs).

## Device build / install / connection

```bash
# Build for a physical device (signs with automatic provisioning)
xcodebuild -project iosApp/iosApp.xcodeproj -scheme iosApp -configuration Debug \
  -destination generic/platform=iOS -derivedDataPath iosApp/build-device -allowProvisioningUpdates build
# → product is <PRODUCT_NAME>.app under build-device/Build/Products/Debug-iphoneos/

# Install + launch (modern CoreDevice)
xcrun devicectl device info details --device <CoreDeviceUUID>   # raises the tunnel / mounts DDI
xcrun devicectl device install app --device <CoreDeviceUUID> <path>/<PRODUCT_NAME>.app
xcrun devicectl device process launch --device <CoreDeviceUUID> <bundle.id>
```

**Connection troubleshooting** (`CoreDeviceError 1011 "unable to locate device"` / `ddiServicesAvailable: false`):
the device shows `unavailable` when it's **locked/asleep** — the wireless dev link drops. Wi-Fi is fine
*if the phone stays awake and unlocked*; USB is the reliable fallback. `xcrun devicectl list devices`
shows state; `xcrun xctrace list devices` shows it by hardware UDID. If `devicectl` still can't reach it,
open **Xcode → Window → Devices and Simulators** once to re-mount the DDI. `timeout` is not on macOS zsh.

- KMP: the framework is embedded by a Run Script phase (`./gradlew :composeApp:embedAndSignAppleFrameworkForXcode`).
- Fast Kotlin checks: `./gradlew :composeApp:compileKotlinIosSimulatorArm64`.
- Simulator build (validates Swift without a device): `-destination 'generic/platform=iOS Simulator'`.

## Shipping it

Everything past the build — TestFlight, App Store submission, screenshots, store metadata, signing
certificates, notarising a macOS build — lives in **`solo-ios-release`**. Use that skill; it carries
verified `asc` commands and the gotchas behind them.

Two things worth knowing here, because they are decided in the *project*, not at upload time:

- `TARGETED_DEVICE_FAMILY` decides which screenshot slots Apple demands. A universal build (`"1,2"`)
  cannot be submitted without an iPad set, no matter what pre-submission validation reports.
- `ITSAppUsesNonExemptEncryption = false` in Info.plist is not just about skipping a prompt: without
  it Apple expires the uploaded build roughly 24 h later, while it still reads as VALID.

## Shared building blocks

- **SharedAuth** — reusable auth Swift Package (Supabase Auth + Google OAuth): `~/startups/shared/superduperai-auth/` (see its `packages/` + `CLAUDE.md`). Use instead of re-rolling auth.
- **On-device / private AI** (add only when needed): FoundationModelsKit (Apple Foundation Models, iOS 26+, `@Generable`), VecturaKit (on-device vector DB), LumoKit (local RAG over PDF/Markdown), MLX-Outil (tool calling via MLX). Privacy-first local search/AI — matches the offline-first ethos.
- Reference: **rudrank.com** — iOS / MLX / Foundation Models / Xcode-MCP guides (the stack's upstream source).

## Marketing screenshots

Capture clean app screens (`xcrun simctl io booted screenshot`, or `adb exec-out screencap` on
Android), then compose with PIL/ImageMagick: caption above, screenshot with rounded corners below.
`caretta-friends/docs/store/compose.py` is a working composer.

⚠️ Do not hardcode a slot size. Which ones Apple accepts depends on the *app*, not on the device you
shot with — ask `asc screenshots sizes`. A listing may take only 1284×2778 even though modern iPhones
render 1290×2796. Framing, captions and upload: `solo-ios-release`.

---
_Living skill — add new App Store rejections / device-connection tricks / stack changes as you hit them._
