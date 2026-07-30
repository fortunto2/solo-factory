---
name: android-release
description: Ship an Android app to testers or to Google Play, or push an update to an app already listed there. Use when the user says "make the Android app available to testers", "internal/open testing link", "publish to Play", "release the APK/AAB", "Play Console", "upload a new version", or hits a Play policy deadline ("app doesn't meet target API level requirements"). Leads with the MINIMAL tester-link workflow (fastest), then the FULL production listing, then UPDATE for an existing app. Carries the exact Play Console browser steps, signing/keystore setup, the testing-track comparison, required assets, and the gotchas (lintVitalRelease crash, 16 KB alignment, target API deadline) so you don't re-learn them.
license: MIT
metadata:
  author: fortunto2
  version: "1.1.0"
  openclaw:
    emoji: "🤖"
---

# android-release — ship Android to testers, then to Play

**Start with MINIMAL** (a working tester link in minutes). Do FULL only when the user wants the
public Play listing. Sibling skill: **`ios-release`** for iPhone/TestFlight.

Golden rules:
- **Never hit final publish/"Send for review" without the user's OK** — it's outward-facing. Filling
  drafts is fine; an internal-testing rollout is low-risk + reversible, so a prior "set it all up"
  covers it — but state what you did.
- **Back up the keystore + password** — losing it = can't update the same Play listing.
- Browser work: **the user logs in** (never touch their password/2FA); you drive the forms after.
  Playwright MCP runs its **own persistent Chromium profile**, NOT the user's Chrome — a Chrome that
  is "already logged in" is invisible to it, and you can't attach unless it was started with
  `--remote-debugging-port` (check `curl -s localhost:9222/json/version` before promising anything).
  So: open the Google sign-in page, hand the window over, wait. The login then sticks for later sessions.
- **The app may live in someone else's developer account** (client/agency who granted you access).
  `play.google.com/console/developers` shows a **"Choose developer account"** list — one Google login
  can hold several. Before concluding "the app isn't here", check every developer account in that list,
  not just the app list of the first one. Newly granted access appears there after a reload.

---

## Which track? (who can use the link)

| Track | Who can install via link | Setup needed |
|-------|--------------------------|--------------|
| **Internal testing** | only Google accounts on your list (≤100) | almost none — no review |
| **Closed testing** | accounts on a list or a Google Group | + content rating, data safety |
| **Open testing** | **anyone with the link** | + full store listing, content rating, target audience, data safety, **review** |
| **GitHub APK (sideload)** | **literally anyone**, no Google account | none — but "unknown sources" prompt |

Most "available to testers" asks → **Internal testing** (fast) or the **GitHub APK link** (instant,
zero-restriction). "Anyone with a link, via Play" → **Open testing** (heavier: listing + review).

---

## A. MINIMAL — get a tester link

**A1. Fastest: sideload APK via a GitHub Release** (no Play account, ~2 min, works for anyone)
```bash
JAVA_HOME=<jdk17> ./gradlew :composeApp:assembleRelease   # universal signed APK
cp composeApp/build/outputs/apk/release/*-release.apk app-<ver>.apk
gh release create v<ver> app-<ver>.apk --repo <owner>/<repo> \
  --title "<App> <ver> — Android tester build" --notes-file notes.md
# testers download the .apk from the release page → tap → allow "install from this source"
```

**A2. Play Internal Testing** (opt-in link, installs via Play, no review). Signed **AAB** required
(`:composeApp:bundleRelease`). Browser steps (Playwright — user logs in first):
1. `play.google.com/console` → **Create app**: name (≤30), package `com.…`, **Check availability**,
   App, Free, tick both declarations (Program Policies + US export laws) → **Create app**.
2. **Testing → Internal testing** → **Create new release**.
3. Leave Play App Signing on ("Releases are signed by Google Play").
4. **Upload** the `.aab` (click Upload → `browser_file_upload` with the absolute path). Wait for
   "optimized for distribution". Release name auto-fills; add notes inside `<en-US>…</en-US>`.
5. **Next → Save and publish** (confirm dialog). Benign warnings: "no deobfuscation file", "no
   native debug symbols", "no testers yet".
6. **Testers** tab → tick an email list (or **Create email list** + paste emails) → **Save** →
   track flips to **Active**. Copy the link: `https://play.google.com/apps/internaltest/<trackId>`.
   Testers open it signed into a listed Google account, tap "Become a tester", install from Play.

**A3. Upgrade internal → open** later: **Testing → Open testing → Promote release** (or create a new
open release). Requires the FULL section below (listing + content rating) + review before it goes live.

---

## B. FULL — production / open-testing listing

Complete before "Send for review":
- **Store listing**: app name, short desc (≤80), full desc (≤4000), **app icon 512×512**,
  **feature graphic 1024×500**, ≥2 phone screenshots (1080×1920..2160; longer side ≤ 2× shorter).
- **App content** (all required): Privacy policy URL, Ads, App access, Content rating
  (questionnaire), Target audience & children, Data safety, plus Government/Financial/Health if relevant.
- **Countries/regions** + Free/Paid.
- Production (or Open testing) track → create release → upload AAB → **Send for review** (confirm first).
- New personal accounts: Google may require **≥12 testers for 14 days** on closed testing before
  production access — plan for that.

### Order that actually unblocks "Send app for review" (Publishing overview)
The **Send app for review** button stays locked until the **Dashboard "Set up your app" checklist is
100%**. Complete, in this order:
1. **Store listing** (Grow users → Store presence → Store listings): name, short/full desc, upload
   icon 512 + feature 1024×500 + ≥2 phone screenshots. (Tablet-screenshot slots show `*` but are NOT
   required for a phone app.)
2. **Store settings** (Store presence → **Store settings**) — EASY TO MISS, it's a separate checklist
   item "Select an app category and provide contact details" that needs THREE things, all required to
   mark it complete: **App category** + **≥1 Tag** (Manage tags — NOT optional; a missing tag silently
   keeps the whole task incomplete and "Send app for review" locked, with no obvious error) + a
   **contact Email**. Verify each value persists after save (a filled-looking field can save blank).
3. **App content** (Policy and programs → **App content → overview**) — do every "Start declaration":
   Privacy policy URL · App access (Sign-in details) · Ads · **Content ratings** (IARC questionnaire) ·
   **Target audience** · **Data safety** · Advertising ID · Government apps · Financial features · Health.
   Yes/No order is NOT consistent across pages — read each before clicking.
4. **Open testing track**: Countries/regions (select all → Save) → **Create release** → Add bundle
   **from library** (reuse the internal AAB) → notes → Next → **Publishing overview → Send app for review**.

### Content rating (IARC) — for a utility/"All Other App Types" app
Category "All Other App Types"; email for the certificate. Answer content questions **No** (violence/
sex/language/drugs/gambling). If the app has user-posted content (photos/notes shared with others),
"User Content Sharing" = **Yes** → then the sub-questions (nudity/violence/block/report/moderation)
are all **No** for a benign app; rating stays Everyone/PEGI 3.

### Data safety — the long one
Q1 collects data? **Yes** → encrypted in transit **Yes** → account creation method (anonymous app =
"My app does not allow users to create an account") → external login **No** → data-deletion request:
**Yes** needs a "Delete data URL" (use the privacy-policy URL) or answer **No** (it's Optional).
Pick **data types** (Location→Precise, Photos, Personal info→Name/Email/User IDs, App activity→Other
UGC), then per type open its modal: **Collected** (your backend is not "Shared" with third parties) →
not ephemeral → **optional** ("users can choose") → purpose **App functionality** → Save.

### Browser-automation gotchas (Playwright on Play Console)
- **Angular Material radios/checkboxes ignore JS `.click()`** — must use a real `browser_click`. Target
  them by the accessibility ref, or `question:has-text("<unique question text>") >> role=radio[name="No"]`.
  Radio labels ("Yes"/"No") are sibling text, so `role=radio[name=...]` often has an EMPTY name — click
  by the visible label text or the ref instead.
- **Sticky footer / overlay panes intercept clicks** on library-Upload / "Add" / "Create release"
  buttons → click via `page.evaluate(() => document.querySelector('button[debug-id="..."]').click())`
  (debug-ids: `upload-button`, `add-to-content-button`, `create-android-release-button`).
- **File upload**: side-panel Upload button → `browser_file_upload` with the absolute path → the asset
  lands in the library → select it → click **Add** (footer-intercepted; JS-click it).
- **Text fields**: type with `slowly`/pressSequentially and VERIFY `input.value` before Save — a filled-
  looking field can be empty (wrong element), leaving "Save" disabled or saving blank (bit me on the
  contact email — took two tries).
- **Direct URLs to `/app-content/*` sub-pages redirect to Home** on hard-navigation; reach them by
  clicking the in-app "App content → overview" link (SPA nav), or navigate to `/app-content/overview`.
  Deep track URLs (`/tracks/app-bundle-explorer`, `/tracks/<id>/releases/…`) are worse — a cold load
  dies with **"An unexpected error has occurred (64146155)"**. Land on `/app-dashboard` or
  `/test-and-release`, then click through the SPA nav. Handy trick: `document.querySelectorAll('a[href]')`
  on `/test-and-release` dumps every track URL incl. the numeric closed-testing track id.
- **Read the page with `browser_evaluate`, not full snapshots** — Console pages are enormous. Grab
  `document.body.innerText` sliced around an anchor phrase, or map `[role="row"]` → `innerText`, and
  wrap it in `new Promise(res => setTimeout(…, 4000-6000))` because the SPA renders after navigation
  reports done. Cheap, and it survives the re-renders that invalidate accessibility refs.
- **Refs go stale constantly** (Console re-renders, plus `?pli=1` redirects on first load). Prefer
  text-based selectors (`button:has-text("Save")`) or find-by-innerText + `.click()` inside
  `browser_evaluate` over refs captured more than one action ago.
- **"Send app for review" locked with everything seemingly filled?** It's almost never a UI lag —
  a required sub-field is silently blank. The dashboard task name understates its requirements (e.g.
  "Select an app category…" also needs **Tags**). When a checklist item won't turn green, open it and
  fill EVERY field, including the ones that look optional, before assuming it's a glitch.

---

## C. UPDATE — new version of an app already on Play

The common ask (policy deadline, bugfix, new build). Nothing from section B is re-done — listing and
declarations are already approved. Order:

1. **Bump `versionCode`** (strictly greater than anything ever uploaded to ANY track — Play rejects
   duplicates permanently, even for a track you never rolled out) + `versionName`. Rebuild the signed
   AAB with the **same upload key**, or the update won't install over the existing app.
2. Find the live track first: **Dashboard** tells you what's actually active (e.g. "Production —
   Inactive" means the app has never gone to prod, no matter what the repo history suggests). Ship into
   the track that's Active; **Test and release → Latest releases and bundles** lists them all.
3. Track page → **Create new release** → **Upload** the AAB → wait ~40 s for "optimized for
   distribution" → the table then shows **Version / API levels / Target SDK** for the new bundle next
   to the previous one. **Read that row** — it's the cheapest proof the build is the one you meant
   (right versionCode, right targetSdk).
4. Release name auto-fills as `<code> (<name>)`; notes go inside `<en-US>…</en-US>`. Verify both
   `input.value`s before continuing.
5. **Next** → review screen: check the **device-support diff** ("Devices no longer supported" must be
   0 unless you intended it) and the warnings. Benign: *"contains native code, no debug symbols"*,
   *"no deobfuscation file"*. Staged roll-out defaults to 100%.
6. **Save** — this does NOT publish. It parks the change in **Publishing overview** ("Your change has
   been saved… go to Publishing overview"). Draft stage, safe to reach without asking.
7. **Publishing overview → "Submit N changes for review" → "Send changes for review"** (confirm dialog).
   ← **outward-facing: needs the user's explicit OK.** Quick checks run first (up to ~14 min), then the
   status becomes **"Changes in review"**. Review is typically ≤7 days.
8. **Managed publishing off** = it goes live to that track's audience the moment review passes. If the
   user wants to gate the moment, turn managed publishing ON *before* submitting.

**Production may be locked** even for a long-lived app: personal accounts must run a closed test with
**≥12 opted-in testers for 14 days** before "Apply for production" unlocks. The Dashboard shows the
live counter ("N testers currently opted-in"). Until it's met, updates can only go to testing tracks —
say so early instead of hunting for a missing button.

---

## Assets — generate what's missing
- **Play icon 512** — resize the app's 1024 icon (e.g. the iOS `AppIcon` `icon_1024.png`) → 512.
- **Feature graphic 1024×500** — brand gradient + icon + wordmark (PIL). Keep emoji OUT of Arial
  captions (they render as tofu boxes).
- **Framed screenshots** — compose raw device captures onto a caption band; template:
  `docs/store/compose_play.py` (caretta-friends). Play phone size 1080×2160 (longer ≤ 2× shorter).

## Signing (once per app)
```bash
keytool -genkeypair -v -keystore keystore/upload.jks -alias <a> -keyalg RSA -keysize 2048 \
  -validity 10000 -storepass … -keypass … -dname "CN=…, O=…, C=…"
```
`build.gradle.kts`: `signingConfigs { create("release") { … read keystore.properties … } }` +
`buildTypes.release.signingConfig`. **Gitignore** `*.jks`, `keystore/`, `keystore.properties`, `*.aab`, `*.apk`.
Play App Signing (on by default) re-signs with Google's key; your keystore is the **upload** key.

## Gotchas
- **`lintVitalRelease` crashes** on KMP/Compose ("Unexpected failure during lint analysis of
  MainActivity.kt") and fails `assembleRelease` though the APK/AAB packaged fine →
  `android { lint { checkReleaseBuilds = false; abortOnError = false } }`.
- **16 KB page alignment** — Play requirement for `targetSdk 35+`. Native `.so` LOAD segments must
  have `p_align = 0x4000`. For MapLibre use **11.13.x** + force `androidx.graphics:graphics-path:1.0.1`.
  Verify by parsing the AAB's ELF PT_LOAD headers for `p_align >= 16384`.
- **AAB ≠ installable** — testers need an **APK** (`assembleRelease`); AAB is Play-only.
- **Package name** locks at Create-app (Check availability); it's the applicationId forever.
- **Target API deadline** — Play requires new uploads to target an API level within ~1 year of the
  latest Android release, and emails "your app doesn't meet Google Play's target API level
  requirements" ahead of the cutoff (Android 15 / API 35 → 31 Aug 2025; Android 16 / API 36 →
  31 Aug 2026; expect the pattern to continue). Fix = raise `compileSdk` **and** `targetSdk`, bump
  versionCode, re-upload. An old AGP refuses to be quiet about a newer compileSdk but still builds
  fine: `android.suppressUnsupportedCompileSdk=<sdk>` in `gradle.properties` beats an AGP upgrade as
  the first move (verified: AGP 8.7.3 + `compileSdk 36`). Confirm the result — the merged manifest
  under `androidApp/build/intermediates/**/AndroidManifest.xml` must say
  `android:targetSdkVersion="<sdk>"`; don't trust the Gradle file alone.
- **Behaviour changes ride along with a targetSdk bump** — enforced edge-to-edge, orientation/resize
  overrides on large screens, predictive back. Worth a device/emulator pass on a UI-heavy app before
  submitting, and worth telling the user it's untested if there's no device at hand.
