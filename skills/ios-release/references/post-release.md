# After the build ships — testers, crashes, reviews

TestFlight orchestration, crash triage, customer reviews, build retention. Everything here works on
a shipped or shipping build.

## Contents
- [TestFlight groups and testers](#testflight-groups-and-testers)
- [What to Test notes](#what-to-test-notes)
- [Crash triage](#crash-triage)
- [Beta feedback](#beta-feedback)
- [Performance diagnostics](#performance-diagnostics)
- [Customer reviews](#customer-reviews)
- [Build retention](#build-retention)
- [Analytics](#analytics)

---

## TestFlight groups and testers

```bash
asc testflight groups list --app "APP_ID" --paginate --output table
asc testflight groups create --app "APP_ID" --name "Beta Testers"
asc testflight testers list --app "APP_ID" --paginate --output table
asc testflight testers add --app "APP_ID" --email "tester@example.com" --group "Beta Testers"
asc testflight testers invite --app "APP_ID" --email "tester@example.com"

asc builds add-groups --build-id "BUILD_ID" --group "GROUP_ID"
asc builds remove-groups --build-id "BUILD_ID" --group "GROUP_ID" --confirm
```

Snapshot the whole configuration into a file (useful before restructuring groups, or to replicate
setup on another app):

```bash
asc testflight config export --app "APP_ID" --output "./testflight.yaml" --include-builds --include-testers
```

---

## What to Test notes

Testers see these in the TestFlight app — the difference between useful feedback and none.

```bash
asc builds test-notes create --build-id "BUILD_ID" --locale "en-US" --whats-new "Test the new onboarding: sign up, skip, then re-open."
asc builds test-notes update --localization-id "LOCALIZATION_ID" --whats-new "Updated instructions."
```

Write them as instructions, not a changelog: what to try, what changed, what to watch for.

---

## Crash triage

```bash
asc testflight crashes list --app "APP_ID" --sort -createdDate --limit 10 --output table
asc testflight crashes list --app "APP_ID" --build "BUILD_ID" --sort -createdDate
asc testflight crashes list --app "APP_ID" --device-model "iPhone16,2" --os-version "18.0"
asc testflight crashes list --app "APP_ID" --paginate            # full analysis
```

Summarize for a human in this order: total count → top signatures grouped by exception type, ranked
by frequency → affected builds → device/OS breakdown → timeline (when it started or spiked).

⚠️ App Store Connect crash data lags **24–48 h**. A quiet list right after a release means nothing yet.

---

## Beta feedback

```bash
asc testflight feedback list --app "APP_ID" --sort -createdDate --limit 10 --include-screenshots
asc testflight feedback list --app "APP_ID" --build "BUILD_ID" --sort -createdDate
```

---

## Performance diagnostics

Needs a build ID (`asc builds info --app "APP_ID" --latest --platform IOS`).

```bash
asc performance diagnostics list --build "BUILD_ID"
asc performance diagnostics list --build "BUILD_ID" --diagnostic-type "HANGS"   # HANGS | DISK_WRITES | LAUNCHES
asc performance diagnostics view --id "SIGNATURE_ID"
asc performance download --build "BUILD_ID" --output ./metrics.json
```

Report the highest-weight signatures first — weight, not count, is what users feel.

---

## Customer reviews

```bash
asc reviews list --app "APP_ID" --sort -createdDate --limit 20 --output table
asc reviews --help          # responding to reviews lives here
```

---

## Build retention

Old TestFlight builds clutter the picker and confuse testers.

```bash
asc builds list --app "APP_ID" --sort -uploadedDate --limit 10 --output table
asc builds info --app "APP_ID" --latest --version "1.0" --platform IOS
asc builds expire-all --app "APP_ID" --older-than 90d --dry-run
asc builds expire-all --app "APP_ID" --older-than 90d --confirm
asc builds expire --build-id "BUILD_ID" --confirm
```

Expiring is not deleting — the build stops being installable by testers. Always dry-run first.

---

## Analytics

```bash
asc analytics --help                                     # sales and analytics report requests
asc insights --help                                      # weekly/daily generated insights
asc finance --help                                       # payments and financial reports
asc web analytics overview --app "APP_ID" --start 2026-01-01 --end 2026-03-31
```

Apple's analytics reports are asynchronous: request → wait → download. `asc web analytics` recreates
the ASC dashboard views directly and is usually faster for a quick look.
