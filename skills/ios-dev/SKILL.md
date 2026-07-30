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
