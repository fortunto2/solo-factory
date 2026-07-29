---
name: ios-release
description: Ship an iPhone/iOS app to testers (TestFlight) or to the App Store. Use when the user says "make the iOS app available to testers", "TestFlight link", "publish to the App Store", "upload the build", or "App Store Connect". Leads with the MINIMAL TestFlight workflow, then the FULL App Store submission. Carries the upload paths (API key vs browser), tester setup, required assets, and the gotchas (BETA_CONTRACT_MISSING, encryption, screenshot capture without taps). Pair with the `ios-app` skill for the build/signing/archive checklist.
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🍎"
---

# ios-release — ship iPhone to TestFlight, then the App Store

**Start with MINIMAL** (TestFlight — the tester-link equivalent). Do FULL only for the public store.
There is **no APK-style sideload** on iOS — testers install via TestFlight (or ad-hoc with each
device UDID, which doesn't scale). Sibling skill: **`android-release`**. Build/signing/archive
details + App-Store gotchas live in the **`ios-app`** skill — read it before the first upload.

Golden rules:
- **Never "Submit for review" without the user's OK** — outward-facing. TestFlight internal-tester
  rollout is low-risk (no review) — a prior "set it up" covers it; state what you did.
- Browser work: **the user logs in** to App Store Connect (never touch their password/2FA).

---

## A. MINIMAL — TestFlight

1. **Archive a Release build** and upload to App Store Connect. Three ways:
   - **API key (best for CLI/headless)**: ASC → Users and Access → Integrations → **App Store
     Connect API** → create key (Issuer ID + Key ID + `.p8`). Then
     `xcrun altool --upload-app -f App.ipa --type ios --apiKey <KeyID> --apiIssuer <IssuerID>`
     (or `notarytool`/`Transporter`). Export the `.ipa` first with `xcodebuild -exportArchive`.
   - **Xcode Organizer** (GUI): Product → Archive → Distribute App → App Store Connect.
   - **Transporter.app**: drag the `.ipa`.
2. Wait for **processing** (a few min–1 h) in ASC → your app → **TestFlight**.
3. Add testers:
   - **Internal testers** (≤100, must be Users on the ASC team) — **no review**, instant.
   - **External testers / Public link** — needs a short **Beta App Review** + the export-compliance
     answer; then anyone with the public link can join.
4. Testers install the **TestFlight** app and open the invite / public link.

⚠️ **BETA_CONTRACT_MISSING (422)** on upload = Apple backend bug. Check ASC → **Agreements** are all
**Active** (Paid + Free Apps). If they are and it still fails, it's Apple-side — contact support; no
self-fix, don't just wait.

---

## B. FULL — App Store submission

- **App record**: bundle id, SKU, name (unique), primary language.
- **Screenshots**: 6.9" **1320×2868** (iPhone 16/17 Pro Max) required; add other sizes as needed.
- **Metadata**: description, keywords, support + marketing URLs, category, age rating.
- **App Privacy**: answer the data-collection questionnaire (Privacy → App Privacy). Privacy policy
  URL required.
- **Encryption**: set `ITSAppUsesNonExemptEncryption=false` in Info.plist to skip the per-upload prompt.
- Attach the processed build to the version → **Submit for review** (confirm with the user first).

---

## Assets — capture without a physical device
The iOS **simulator can't be tapped from CLI** (System Events `click at` is TCC-blocked; only
`key code` works — Return dismisses the location alert). To get clean screens headlessly:
1. Skip onboarding: set `profile.onboarded=true` in the sim container's state JSON
   (`xcrun simctl get_app_container booted <bundle> data` → `…/Documents/<state>.json`).
2. Preselect a tab via a launch env the app reads, e.g. `AppRouter.init` reads
   `ProcessInfo…environment["CF_TAB"]`; launch with `SIMCTL_CHILD_CF_TAB=beaches xcrun simctl launch …`.
3. `xcrun simctl location booted set <lat>,<lng>` for realistic "near you" distances.
4. `xcrun simctl io booted screenshot out.png` (iPhone 17 Pro Max sim = 1320×2868 = App Store 6.9").
5. Frame with captions: template `docs/store/compose_ios.py` (caretta-friends).

Icon: the 1024×1024 `AppIcon` (`icon_1024.png`) is the App Store icon — no separate export.

## Missing `iosApp` Xcode scheme?
If `xcodebuild -scheme iosApp …` fails with "does not contain a scheme named iosApp", a shared
scheme for another target (e.g. a widget) disabled autogen. Create a shared
`xcshareddata/xcschemes/iosApp.xcscheme` pointing at the app target's BlueprintIdentifier
(from `project.pbxproj`) — see the caretta-friends repo for a working file.
