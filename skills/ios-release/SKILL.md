---
name: solo-ios-release
description: Ship an iPhone/iOS app to testers (TestFlight) or to the App Store, or push an update to an app already listed there. Use when the user says "make the iOS app available to testers", "TestFlight link", "publish to the App Store", "upload the build", "submit for review", "App Store Connect", "ASC", or "upload a new version". CLI-first via the `asc` tool (official App Store Connect API) — the browser is a fallback for the few things the API cannot do. Pair with the `ios-app` skill for the build/signing/archive checklist.
license: MIT
metadata:
  author: fortunto2
  version: "3.0.0"
  openclaw:
    emoji: "🍎"
---

# ios-release — ship iPhone via CLI

**Everything runs through `asc`** (App Store Connect CLI — official API, JWT-signed). The browser is
a fallback for the handful of flows Apple never exposed publicly — see
[references/browser.md](references/browser.md).

Sibling skill: **`android-release`**. Build/signing/archive details live in **`ios-app`**.
There is no APK-style sideload on iOS — testers install via TestFlight.

Golden rules:
- **Never submit for review without the user's explicit OK** — outward-facing and hard to reverse.
  TestFlight *internal*-tester rollout is low-risk (no Apple review); a prior "set it up" covers it.
- **Dry-run before every mutation.** The high-level commands take `--dry-run`; add `--confirm` only
  after the printed plan matches what the user asked for.
- **`asc validate` is the source of truth**, not your reading of the ASC web UI. Its ordered
  remediation plan *is* the task list — fix the first item, re-validate, repeat.
- **Confirm flags with `--help` before running.** The CLI moves fast; don't trust memory.

---

## Setup (once per machine)

```bash
brew install asc
asc auth login --name "default" --key-id "KEYID" --issuer-id "ISSUER-UUID" \
  --private-key ~/Downloads/AuthKey_KEYID.p8 --network
asc auth status
```

The key comes from ASC → Users and Access → Integrations → **App Store Connect API** → Team Keys →
**+** → role **App Manager** (Admin also works). The `.p8` downloads exactly once. `asc auth login`
copies the key material into the macOS Keychain, so the file can be deleted afterwards. Env-var
fallbacks, CI setup and per-repo profiles: [references/asc-cli.md](references/asc-cli.md).

---

## Routing

| Intent | Go to |
|---|---|
| Get a build to testers | [A. TestFlight](#a-minimal--testflight) |
| Ship a new app to the Store | [B. App Store](#b-full--app-store-submission) |
| New version of a listed app | [C. Update](#c-update--new-version) |
| Crashes, feedback, testers, reviews | [D. After release](#d-after-release) |
| `asc validate` reports blockers | [references/readiness.md](references/readiness.md) |
| Description, keywords, ASO, What's New | [references/metadata-aso.md](references/metadata-aso.md) |
| Screenshots — capture, frame, upload | [references/screenshots.md](references/screenshots.md) |
| Archive, export, signing, CI pipeline | [references/build-upload.md](references/build-upload.md) |
| Create the app record, App Privacy | [references/browser.md](references/browser.md) |
| Flags, auth, IDs, command discovery | [references/asc-cli.md](references/asc-cli.md) |

Open every session on an unfamiliar app with the dashboard:

```bash
asc apps list --output table                    # find the APP_ID
asc status --app "APP_ID" --output table        # builds + version + submission state
```

**App registry.** Before asking the user for app IDs, review contacts, copyright or store URLs,
look for an `ios-apps.yaml` in their knowledge base or repo root (`rg -l "asc_auth|bundle_id" --glob "*.yaml"`).
Releases need the same handful of values every time; a registry means asking once. Keep that file in
a **private** repo — it holds a phone number and email that App Review sees but the store never shows.

---

## A. MINIMAL — TestFlight

One command covers upload, processing wait, and group assignment:

```bash
asc publish testflight --app "APP_ID" --ipa "./App.ipa" --group "Beta" --wait --output table
```

No `.ipa` yet? `asc xcode archive` + `asc xcode export` build one —
see [references/build-upload.md](references/build-upload.md).

Then:
- **Internal testers** (≤100, must be Users on the ASC team) — no review, available in minutes.
- **External testers / public link** — needs a short Beta App Review plus the export-compliance
  answer. Add `--submit --confirm` to trigger that review.

Monitor:

```bash
asc builds list --app "APP_ID" --limit 5 --output table   # processingState must reach VALID
asc testflight groups list --app "APP_ID" --output table
```

⚠️ **BETA_CONTRACT_MISSING (422)** on upload = check ASC → **Agreements** are all **Active** (Paid +
Free Apps). If they are and it still fails, it's an Apple-side backend bug — contact support, don't
just wait it out.

---

## B. FULL — App Store submission

The version sits in "Prepare for Submission" until a checklist is complete. Drive that checklist
from `validate`, never from clicking around the web UI.

```bash
# 1. What's missing? Output is an ordered remediation plan — the first item is the next thing to fix.
asc validate --app "APP_ID" --version "1.0" --platform IOS --output table

#    On an unstarted version this table is ~35 KB (an empty age rating alone is 24 rows).
#    Collapse it to one line per problem before showing the user anything:
asc validate --app "APP_ID" --version "1.0" --platform IOS --output json \
  | jq -r '[.. | objects | select(has("checkId"))] | group_by(.checkId)
      | map({c: .[0].checkId, s: .[0].severity, n: length, fix: .[0].remediation})
      | .[] | "\(.s|ascii_upcase) [\(.n)x] \(.c)\n  → \(.fix)"'

# 2. Fix the first blocker → references/readiness.md. Re-run step 1. Repeat until clean.

# 3. Stage: apply metadata, attach the build, re-validate — creates NO review submission.
asc release stage --app "APP_ID" --version "1.0" --build "BUILD_ID" \
  --metadata-dir "./metadata" --dry-run --output table
asc release stage --app "APP_ID" --version "1.0" --build "BUILD_ID" \
  --metadata-dir "./metadata" --confirm

# 4. Submit — ONLY after the user says go.
asc review submit --app "APP_ID" --version "1.0" --dry-run --output table
asc review submit --app "APP_ID" --version "1.0" --confirm

# 5. Monitor.
asc review status --app "APP_ID" --version "1.0" --output table
```

Starting from an `.ipa` with nothing staged, `asc publish appstore` collapses steps 3–4:

```bash
asc publish appstore --app "APP_ID" --ipa "./App.ipa" --version "1.0" \
  --submit --wait --dry-run --output table      # then --confirm instead of --dry-run
```

**Do not mix lanes.** Once a lane has created a review submission, inspect it
(`asc submit status --version-id "VERSION_ID"`) and continue in that same lane.

Success = the version's `appStoreState` / `reviewSubmission.state` reads **WAITING_FOR_REVIEW**.

### What validate enforces
Metadata lengths · required localizations · review details · primary category · attached and
processed build · encryption declaration · content rights · **pricing schedule and territory
availability** (a separate required item — the classic miss) · screenshot presence and sizes · age
rating. Repair recipes for each: [references/readiness.md](references/readiness.md).

**App Privacy is not in the public API** — use `asc web privacy` or the browser. See
[references/browser.md](references/browser.md).

---

## C. UPDATE — new version

```bash
asc versions create --app "APP_ID" --version "1.1" --platform IOS
asc metadata pull --app "APP_ID" --version "1.1" --dir "./metadata"      # edit whatsNew
asc metadata push --app "APP_ID" --version "1.1" --dir "./metadata" --dry-run --output table
asc release stage --app "APP_ID" --version "1.1" --build "BUILD_ID" --copy-metadata-from "1.0" --confirm
asc validate --app "APP_ID" --version "1.1" --output table
```

`--copy-metadata-from` carries localizations forward. App Privacy and Pricing persist unless data
practices or price changed; screenshots persist unless the UI changed.

Writing the release notes is a real task, not a formality — the first 170 characters are all most
users read. Rules and examples: [references/metadata-aso.md](references/metadata-aso.md).

---

## D. After release

```bash
asc testflight crashes list --app "APP_ID" --sort -createdDate --limit 10 --output table
asc testflight feedback list --app "APP_ID" --sort -createdDate --limit 10
asc reviews list --app "APP_ID" --sort -createdDate --limit 20 --output table
asc builds test-notes create --build-id "BUILD_ID" --locale "en-US" --whats-new "What to test…"
```

Crash data lags 24–48 h — an empty list right after shipping means nothing. Tester management,
performance diagnostics, build retention and analytics:
[references/post-release.md](references/post-release.md).

---

## Guardrails

- No `--confirm` until a `--dry-run` plan has been read and matches the request.
- Never create a second review submission for a version that already has one.
- A validation failure stops the release — never ship a partial one.
- Don't call a version ready because one validator passed; report warnings that still need a
  web-session or manual check.
- Non-iOS targets: same lifecycle with `--platform MAC_OS` / `TV_OS`.
- `asc screenshots capture/frame/run` are experimental — say so in handoff notes.

---

*CLI recipes adapted from [rorkai/app-store-connect-cli-skills](https://github.com/rorkai/app-store-connect-cli-skills) (MIT, © 2026 Rudrank Riyam), command paths verified against `asc` 3.2.0. Field-tested gotchas are our own.*
