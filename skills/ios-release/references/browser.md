# Browser fallback — what the API cannot do

Read this **only** when `asc` cannot cover the step. Everything here is slower and more fragile than
the CLI path in SKILL.md. This file also carries the field notes from the pre-CLI era, so the
hard-won gotchas aren't lost.

Rule when a browser is unavoidable: **the user logs in** to App Store Connect — never touch their
password or 2FA.

## Contents
- [What genuinely needs a browser](#what-genuinely-needs-a-browser)
- [App Privacy questionnaire](#app-privacy-questionnaire)
- [The screenshot-upload finalize trap](#the-screenshot-upload-finalize-trap)
- [Playwright automation gotchas](#playwright-automation-gotchas)
- [Manual version checklist](#manual-version-checklist-full-fallback)

---

## What genuinely needs a browser

| Flow | Status | Route |
|---|---|---|
| Create a new app record | No public API | `asc web apps create` (web session) or the New App form |
| App Privacy declaration | No public API | `asc web privacy plan/apply`, else the questionnaire below |
| Agreements (Paid/Free Apps) | No API | ASC → Business → Agreements |
| Tax/banking | No API | ASC → Business |
| Some rejection-message detail | Partial | `asc web review show`, else Resolution Center |
| Replying to a rejection + attachments | No public API | Resolution Center → "Reply to App Review" |
| Resubmitting after a rejection | No public API | Remove the rejected item, then "Resubmit to App Review" |

Check coverage before assuming: `asc capabilities --status not-public-api --output table` and
`asc capabilities --status web-session --output table`.

`asc web auth login --apple-id "user@example.com"` opens an Apple web session (separate from the API
key). It covers most of the above without a real browser — try it first.

---

## Creating the app record

No public API — Apple's docs say so explicitly. Preferred: `asc web apps create --name "My App"
--bundle-id "com.example.app" --sku "MYAPP123"`. Preflight either way:

```bash
asc bundle-ids create --identifier "com.example.app" --name "My App" --platform IOS   # must exist first
asc apps list --bundle-id "com.example.app" --output json                             # confirm none exists
```

Driving the New App form by hand? Four gotchas, all verified:
- **"New App" is a dropdown**, not a direct action — click the button, then the *menu item*.
- **Platform is checkboxes**, not radios; multiple allowed.
- **Bundle ID dropdown loads asynchronously** after platform selection — it shows "Loading…" and is
  disabled. Wait for it, then match the option label `"My App - com.example.app"`.
- **User Access (Limited/Full) is required** and its custom radios sit under `<span>` overlays that
  intercept clicks. Fix: `scrollIntoView` on the radio element, then click the radio ref directly.
- If Create stays disabled with everything filled, Apple's Ember form didn't fire its change
  handlers — retype one text field slowly, character by character.

Never auto-retry the Create click. After success, verify and set up:

```bash
asc apps view --id "APP_ID" --output json --pretty
asc app-setup info set --app "APP_ID" --primary-locale "en-US"
asc app-setup categories set --app "APP_ID" --primary GAMES
asc pricing availability create --app "APP_ID" --territory "USA,GBR" --available true
```

---

## App Privacy questionnaire

No public API. Preferred path is the web session:

```bash
asc web privacy pull --app "APP_ID" --out "./privacy.json"      # current answers
asc web privacy plan --app "APP_ID" --file "./privacy.json"     # review the diff
asc web privacy apply --app "APP_ID" --file "./privacy.json"
asc web privacy publish --app "APP_ID" --confirm                # apply ≠ published
```

Check every data type, purpose, tracking and linkage answer against what the app *actually* does,
including third-party SDKs. Never infer privacy answers from the app name or store copy. A successful
`apply` does not prove the answers were published — verify, or check
`https://appstoreconnect.apple.com/apps/APP_ID/appPrivacy` manually.

Manual flow (Trust & Safety → App Privacy), mirroring the Play data-safety answers:

1. Privacy Policy URL → Save. Data Collection = **Yes, we collect data from this app** → Next.
2. **Select data types** (checkbox grid). For a volunteer/field app syncing to a backend:
   Name, Email Address, Precise Location, Photos or Videos, Other User Content, User ID → Save.
3. For **each** type click **Set Up** and walk its modal:
   - Purpose = **App Functionality** → Next.
   - "Linked to the user's identity?" → **Yes** (data tied to the account) → Next.
   - Two info screens (Tracking definitions / examples) → Next, Next.
   - "Used for tracking purposes?" → **No** → Save.
4. When every type shows a usage summary (no "Set Up" left), **Publish** → confirm.

**On-device / offline-first app that transmits nothing?** The whole flow collapses: Data Collection =
**No, we do not collect data from this app** → Save → **Publish**. Result on the product page is
"Data Not Collected", no data-type grid. "Collect" = transmitted off device; accessing the photo
library / location purely on-device and never sending it out is *not* collection. (A privacy policy
URL is still mandatory even when nothing is collected — see readiness.md.) The iris write is a plain
PATCH and the metadata around it (`description`, `keywords`, `subtitle`, category, `contentRights`,
`releaseType`, and creating `appStoreReviewDetail`) all accept normal iris PATCH/POST from the page
context — handy when a field isn't yet exposed by `asc`.

---

## The screenshot-upload finalize trap

**This is why the CLI path exists.** Kept as evidence — do not re-litigate it.

**Symptom.** After uploading screenshots via a Playwright/automation browser, "Add for Review" fails
with a misleading red item: **"There are still screenshot uploads in progress."** It never clears —
minutes, then an hour. Re-uploading (PNG→JPEG, delete+re-add) doesn't help.

**Root cause.** ASC screenshot upload is a 3-step protocol: *reserve* (`POST /iris/v1/appScreenshots`
→ returns `uploadOperations` = presigned S3 multipart PUT URLs) → *PUT the bytes* → *commit*
(`PATCH …/{id}` with `uploaded:true` + `sourceFileChecksum`). A headless/automation browser reserves
and shows "N of 10 Screenshots" but the ASC JS uploader **never completes the S3 multipart + commit**,
so each asset is stuck at `assetDeliveryState.state = UPLOAD_COMPLETE` (not `COMPLETE`), still carries
`uploadOperations`, and `sourceFileChecksum` stays null. Under the hood "Add for Review" does
`POST /iris/v1/reviewSubmissions` (201) → `POST /iris/v1/reviewSubmissionItems` → **409 Conflict**
(item not addable while an asset is un-finalized) → it rolls back with a DELETE. The UI mistranslates
that 409 as "uploads in progress."

**Diagnose** (read the real state; cloud thumbnails never render under automation even when fine).
From the page's own origin/cookies:
```js
// localizationId from the network tab: GET …/appStoreVersionLocalizations?filter[appStoreVersion]=…
fetch(`/iris/v1/appScreenshotSets?include=appScreenshots&filter[appStoreVersionLocalization]=<locId>`,
  {headers:{'Accept':'application/vnd.api+json'},cache:'no-store'})
  .then(r=>r.json()).then(j => j.included.filter(x=>x.type==='appScreenshots')
    .map(s => [s.attributes.fileName, s.attributes.assetDeliveryState.state]));
// COMPLETE = good; UPLOAD_COMPLETE with uploadOperations present = stuck.
```
A **409 on `reviewSubmissionItems`** in the network log confirms it's this, not a real processing wait.

**What does NOT fix it** (all verified — don't burn time):
- Waiting (40+ min), reloading, re-clicking Add for Review.
- Re-uploading as JPEG instead of PNG (files were valid RGB/no-alpha; format isn't the issue).
- Driving the protocol by hand from the automation browser: reserve + PUT succeed (`PUT` → 200, S3
  `ETag` == the file's MD5), but the commit `PATCH {uploaded:true, sourceFileChecksum:<md5-hex>}`
  returns **200 yet is a no-op** — state stays UPLOAD_COMPLETE. The web-iris endpoint accepts but
  doesn't action the commit.

**The fix — two options:**
1. **`asc screenshots upload`** (what SKILL.md does). The official
   `api.appstoreconnect.apple.com` implements the commit correctly. This is the whole reason the CLI
   path replaced the browser one.
2. A **real, non-automation browser** (the user's own Safari/Chrome). The native ASC uploader
   completes the multipart + commit and assets flip to `COMPLETE`.

---

## Playwright automation gotchas

- **React ignores JS `.click()`** on radios/checkboxes/rows — the value reverts on re-render. Use a
  real `browser_click`. Reliable pattern: in `browser_evaluate`, tag the target with a data-attr
  (find it by its sibling label text), then `browser_click` the `[data-…]` selector. Verify the
  checked/enabled state with a follow-up `evaluate` before moving on.
- **File chooser = modal state.** Clicking "Choose File" opens a native dialog Playwright captures as
  modal state that blocks every other tool. Clear stray ones with `browser_file_upload []` (empty
  paths) once per open chooser. Per the trap above, feeding the screenshot input via automation still
  won't finalize.
- **Direct deep-links to sub-pages** work on hard-nav (e.g. `…/distribution/pricing/availability`);
  the version editor lives at `…/distribution/ios/version/inflight`.
- **The iris API is reachable from the page context** with the user's cookies — great for *reading*
  true state (screenshot delivery state, `reviewSubmissions`, version `appStoreState`) when the DOM
  is ambiguous. Prefer it over screenshotting placeholders.
- **Resolution Center attachments upload but stay invisible to automation.** `setInputFiles` on the
  hidden input does attach the file, yet the resulting list renders in neither the accessibility
  snapshot nor a page screenshot, and the input's own `.files` reads empty afterwards. Retrying
  because "it didn't work" silently attaches duplicates. Ask the person looking at the screen.
- **A cached web session can be authenticated and still 401.** `asc web auth status` reporting
  `authenticated: true` with `teamId: 0` means every `asc web …` call fails; log out and back in, or
  drive the browser instead.

---

## "You must renew your Apple Developer Program membership"

TestFlight shows this banner on a perfectly current membership. Before anyone pays anything, check
both places — it takes a minute and the banner is often just a stale cache after a recently accepted
agreement:

| Check | Where | Healthy looks like |
|---|---|---|
| Membership | developer.apple.com/account → **Membership details** | a *future* Renewal date, program listed |
| Agreements | ASC → **Business** → Agreements | Paid Apps **and** Free Apps both `Active` |

If both are fine, the banner is cosmetic — uploads, submissions and TestFlight keep working. If the
Free Apps agreement is *not* Active, that is the real blocker, and it also produces
`BETA_CONTRACT_MISSING (422)` on upload.

---

## Manual version checklist (full fallback)

If the CLI is unavailable entirely. Modern ASC uses a two-step model: **Add for Review** (adds the
version as an *item* to a `reviewSubmission`) → **Submit for Review**. There is no single Submit
button.

1. **App Information** — Name, Subtitle, **Category** (primary + optional secondary), **Content
   Rights**, **Age Rating** (questionnaire → all "None"/No for a benign app → 4+).
2. **Version page** ("1.0 Prepare for Submission"):
   - Promotional Text / Description / **Keywords** (≤100 chars, comma-separated, no spaces) /
     Support URL / Marketing URL.
   - **Screenshots** — one size suffices; ASC reuses it. 6.5" (`1284×2778`, also `1242×2688`) or
     6.9" (`1320×2868`). RGB, **no alpha**, PNG or JPEG.
   - **Build** — attach via `+`. Set `ITSAppUsesNonExemptEncryption=false` in Info.plist to skip the
     per-upload encryption prompt.
   - **App Review Information** — contact name/phone/email + Notes (say "works without an account"
     if sign-in is optional; describe camera/location/AR usage). Sign-In required = off if usable
     anonymously.
   - **Version Release** — "Automatically release" is the usual default.
3. **App Privacy** — see above, then **Publish**.
4. **Pricing and Availability** — **easy to miss, a separate required item.** Set a **Price**
   (Free = `$0.00` tier → Confirm) *and* **Availability** (Set Up Availability → All Countries →
   Confirm). If either is unset, "Add for Review" stays blocked with a "Pricing" required item.
5. **Add for Review** → resolve red "required to start the review" items → **Submit for Review**
   (confirm with the user first).
