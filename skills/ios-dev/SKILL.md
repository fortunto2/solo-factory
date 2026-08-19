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

**Xcode's own bridge** (`xcrun mcpbridge`, Xcode 26.3+) — advertised as 20
tools over XPC, including rendering a SwiftUI Preview without building and
running the whole app, plus a Swift REPL. It needs **Xcode running with the
project open**, so it is no use in a background or CI run.

Verify it answers before planning around it. On Xcode 26.6 with the project
open, `initialize` replies (`serverInfo: {name: xcode-tools}`) and then
`tools/list` never answers and the pipe closes — nothing usable. Probe it in
ten seconds rather than assuming either way:

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | xcrun mcpbridge
```

**Keep one MCP config, not two.** A project `.mcp.json` and `~/.mcp.json` that
both define XcodeBuildMCP start two servers, and the project copy usually
lacks the workflow filter — so the session carries a second, differently
configured set of the same tools. Pick one file, or keep them byte-identical
and say so in a comment.

**Apple RAG MCP** (official Swift docs and HIG over RAG) is a nice-to-have —
context7 already answers most API questions, and HIG comes up once a day, not
once a minute.

## Driving the Simulator, and trusting the numbers

Learned the hard way on a video app; the traps are not app-specific.

**Pick the reader by where the code runs, not by benchmark.** Measured on one
screen (Xcode 26.6, iOS 26 simulator, Aug 2026):

| Reader | Returned | Use it |
|--------|----------|--------|
| MCP `snapshot_ui` (XcodeBuildMCP) | **442 nodes**, each with `elementRef`, role, label, available action | inside an agent session — tap by `elementRef`, no coordinates, and `batch` several taps on one screen |
| `axe describe-ui --udid` | 48 nodes, 21 labelled, with frames | shell scripts, which cannot reach MCP |
| `idb ui describe-all` | **1 empty element**; every tap answers `Mach port invalid, device disconnected` | nothing, currently |

`idb` was the fast one and is now broken against current simulators — `idb kill
&& idb connect` does not revive it. Its "0.27s tap" is the speed of the error,
not of a tap; it does at least exit non-zero, so a `idb … || axe …` fallback
still works and merely wastes a call. **Re-measure before trusting any of these
three, including this table** — the tool that was right last release is the one
most likely to be quietly wrong now.

`axe` **requires `--udid`**. Without it, it prints usage to stderr and returns
nothing, so a script that does not check will read every screen as empty and
report the app as broken. Find it yourself rather than requiring an argument:

```bash
xcrun simctl list devices booted -j    # → udid of the booted simulator
axe describe-ui --udid <UDID>
axe tap -x 200 -y 60 --udid <UDID>     # points, not pixels
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

## A Rust core linked into the app (uniffi)

Three traps, each of which reads as "my change did nothing" or "the bridge is
broken", and none of which is either.

**The app may be linking yesterday's core.** `CARGO_TARGET_DIR` (commonly set
to a shared directory in a shell profile) means cargo does *not* write to
`./target` — while the Xcode project points its linker at `$(SRCROOT)/../target/…`.
Everything builds, everything runs, and none of the day's work is in the app.
Add a pre-build script phase that copies the newer `.a` across, and leave
`ENABLE_USER_SCRIPT_SANDBOXING` off (it denies that phase access to the
directory). If a change appears to have no effect, check the `.a` timestamp
*before* re-reading the code.

**Pin the deployment target in `.cargo/config.toml`, not in a build command.**

```toml
[env]
IPHONEOS_DEPLOYMENT_TARGET = "17.0"
```

Left unset, every object is stamped with the SDK's own version and the linker
emits one warning per object — hundreds of them, all identical, hiding whatever
real warning arrives next. Pinning it in the Makefile fixes only that one door;
`build-ios-sim.sh`, `make deploy` and a bare `cargo build` keep the problem. And
a `link-arg` does **not** work: a staticlib is an archive and is never linked.
Changing this env var does not enter cargo's hash either, so the dependency
objects keep their old stamp — delete the target dir once when you set it.

**Build for one concrete simulator.** `-destination 'generic/platform=iOS
Simulator'` asks for a universal build, which includes x86_64; an arm64-only
Rust core then fails to link with a page of missing uniffi symbols that reads
exactly like a broken bridge. Use `-destination "id=$UDID"`.

**Logging levels are a performance decision, not a style one.** A `tracing::info!`
on a per-frame path wrote 11,752 records of one montage into a JSONL file on the
device — 30,577 lines and 10 MB in a day, inside the loop the user is waiting
on. Anything per-frame or per-item belongs at `debug!`/`trace!`, and whatever
you do write needs a retention sweep at startup; nothing else will ever delete
those files.

**The first HTTP request a fresh process makes can hang.** Not slow — no answer
at all until something cuts it off, with the retry succeeding in ~2s. Any client
built with `reqwest::Client::new()` has no timeout of any kind, and library
defaults can be worse than none (`openai-oxide` defaults to 600s). Set
`connect_timeout`, `timeout` and a `pool_idle_timeout` shorter than the minute a
mobile network takes to forget an idle connection, and let retry treat a timeout
as transient. Measured: 120s of nothing → 40s with an answer.

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

  Three things make the difference between a trace that answers and one that
  looks like it does — each cost a session to learn:

  - **Log at `.default`, not `.info`.** `.info` is held in memory and never
    written down, so `log show --predicate 'category == "trace"'` returns
    nothing after the fact and the walk can only be watched live, if you
    thought to attach a stream first. On a phone, after the fact is usually the
    only chance there is. Twenty lines per run costs nothing.
  - **Keep the finished walk.** "Why was that slow" is asked once the result is
    on screen, and clearing the marks when the next run starts throws away the
    answer. Hand the account over on the *next* start, not on finish — a mark
    delivered via a hop to the main actor lands just after the code that ends
    the run, so freezing at finish drops the last step, which is the one people
    ask about.
  - **Do not bill the app for the user's thinking.** A step recorded at a tap
    carries everything since the previous mark, including however long somebody
    stared at the screen. Mark taps separately (`👆 preview requested`), reset
    the clock there, and charge them nothing. Before this a walk read 13.0s of
    app time with one step at 7.4s that looked like the thing to fix; with taps
    marked it read 5.6s and that step was 0.0s. The 7.4s was the test harness
    looking at the screen.
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
- **Ask where a clip is before queueing it.** `isNetworkAccessAllowed = false`
  turns a request into a cheap probe: a local asset comes back almost at once,
  one in iCloud comes back empty with `PHImageResultIsInCloudKey` set and
  starts no download. Measured at 14ms per clip — 0.7s for 50.

  It matters because worker slots are few. With four slots and no ordering,
  all four filled with cloud clips while clips already on the device — a
  second's work each — queued behind them: 2% for a long time and nothing on
  screen. Read what is here first, the cloud after, and put a deadline on the
  probe so the worst case is the order you had anyway.

## Where the reference comes from

Do not invent a screen from scratch when a convention already exists for it —
people arrive already knowing how a length picker, a paywall or an onboarding
step behaves, and a fresh idea in that slot costs them the knowledge.

**Mobbin publishes `https://mobbin.com/llms.txt`** — 66 KB, no key, ~272
mobile links organised four ways: by app category, by *flow*
(`/explore/mobile/flows/…` — onboarding, adding-to-cart, editing-profile), by
screen pattern, and by UI element. Fetch it, pick the two or three links that
match the screen being built, and look at those rather than describing a
layout from memory.

```bash
curl -s https://mobbin.com/llms.txt | grep -i 'flows/'      # 60+ named flows
curl -s https://mobbin.com/llms.txt | grep -i 'ui-elements' # by component
```

Also worth having in the same slot: Apple's HIG for the platform rule, and a
design the user already made — a Claude Design project can be read with the
`DesignSync` MCP (`list_files` then `get_file`), which is how a `.dc.html`
mockup becomes tokens (`Brand.swift`) and components rather than a screenshot
someone eyeballs. Pull the palette, the radii and the blur values out of the
markup instead of guessing them:

```bash
grep -o 'linear-gradient([^)]*)' mock.html | sort | uniq -c | sort -rn | head
grep -oE '#[0-9A-Fa-f]{6}' mock.html | sort | uniq -c | sort -rn | head
grep -o 'border-radius:[^;]*'   mock.html | sort | uniq -c | sort -rn | head
```

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

**`onTapGesture` is invisible to the tree — and to VoiceOver.** A tile built
as a ZStack with `.contentShape(Rectangle()).onTapGesture` offers no action at
all: the snapshot listed 17 actionable elements on a gallery screen and not
one of them was a clip. Same cause, two consequences — the automation cannot
drive it and a person using VoiceOver cannot use the feature. Fix once:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel(label)                       // "Video, 30 seconds, analysed"
.accessibilityValue(isSelected ? "Selected" : "")
.accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
.accessibilityAction(.default, onTap)
```

The reverse failure is a row that exposes *too much*: artwork, title, source
and duration as four separate elements, none of which is the one that selects.
Collapse it with `children: .ignore` and one label. Afterwards the tree is
also a usable test surface — you can tap a specific clip by name, which is
impossible when everything is called "Song, Play".

**A check with no time budget is not a check.** A smoke script that only asks
"did it answer" reported PASS on a 124-second reply. Give each step what it
should cost warm, report over-budget, fail on wildly over — slow is a
regression, and it is the one that silently arrives.

**A checker must never blame the app for its own failure.** Count "could not
reach the screen" separately from "the screen has unnamed controls" and print
both. An audit whose reader was misconfigured reported *7 screens with unnamed
controls* in an app that had none — same exit code as a real defect, and a day
of work aimed at nothing. Same rule for a walker: if the library count does not
move after Save, ask the app whether it *attempted* the save, so "the tap
missed the button" and "the system refused the write" stop looking alike.

**Never grep away a category of output to make a run look clean.** 375 linker
warnings stayed invisible for a day because the check filtered the line they
were on, and the filter was written by the same person who then reported "no
warnings".

**A measurement from a busy or sleeping machine is not a measurement.** Three
separate "regressions" — 909s, 1139s, 120s — were the laptop, not the code.
Re-run before believing a number, and `caffeinate -dimsu` anything long.

**Ask a repeated question and you may be timing a cache.** An LLM turn behind
a gateway answered a fresh question in 9s and a repeat of an earlier one in
1.0s. Vary the prompt when timing, or the check passes with the model
unplugged.

**A permanently red test hides the real ones.** Three PhotoKit tests had
asserted the opposite of what was actually true for long enough that four
genuine failures went unnoticed in the same run. If an environment cannot
answer the question (a test runner is regularly refused library resources the
app itself reads fine), `XCTSkip` with the reason — and note `wait(for:)`
records a failure the moment it times out, so use `XCTWaiter().wait(...)` when
the timeout is a decision rather than a verdict.

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
