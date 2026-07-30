# Readiness repairs

Read **only** the section matching a proven `asc validate` / `asc review doctor` blocker. Fix one
class of blocker, re-validate, then move on. Don't dump the whole catalog at the user.

```bash
asc validate --app "APP_ID" --version "1.0" --platform IOS --output table   # ordered repair queue
asc review doctor --app "APP_ID" --version "1.0" --platform IOS --output table
asc validate iap --app "APP_ID" --output table              # only if the release has IAPs
asc validate subscriptions --app "APP_ID" --output table
```

Add `--strict` when warnings must fail automation.

## Contents
- [Build processing and encryption](#build-processing-and-encryption)
- [Content rights](#content-rights)
- [Age rating](#age-rating)
- [Version metadata and localizations](#version-metadata-and-localizations)
- [App info and privacy policy URL](#app-info-and-privacy-policy-url)
- [Pricing and availability](#pricing-and-availability)
- [Review details](#review-details)
- [Screenshots](#screenshots)
- [Stuck or rejected submissions](#stuck-or-rejected-submissions)

---

## Build processing and encryption

```bash
asc builds info --build-id "BUILD_ID" --output table     # processingState must be VALID
asc encryption declarations list --app "APP_ID" --output table
```

Create a declaration **only** when its answers truthfully describe the binary:

```bash
asc encryption declarations create --app "APP_ID" \
  --app-description "Uses standard HTTPS/TLS" \
  --contains-proprietary-cryptography=false \
  --contains-third-party-cryptography=true \
  --available-on-french-store=true
asc encryption declarations assign-builds --id "DECLARATION_ID" --build "BUILD_ID"
```

Better: if the app only uses exempt transport encryption, set `ITSAppUsesNonExemptEncryption=false`
in Info.plist and rebuild — that kills the per-upload prompt permanently.
`asc encryption declarations exempt-declare --plist "./Info.plist"` edits the plist for you.

## Content rights

```bash
asc apps content-rights view --app "APP_ID" --output table
asc apps content-rights edit --app "APP_ID" --uses-third-party-content=false
```

## Age rating

An empty declaration reports as **24 separate blockers** — one per field. One flag clears all of
them for an app with no objectionable content:

```bash
asc age-rating view --app "APP_ID" --output table
asc age-rating edit --app "APP_ID" --all-none         # 24 fields → false / NONE, rating becomes 4+
```

Verify the result actually describes the app before moving on, then set only the fields that differ:

```bash
asc age-rating edit --app "APP_ID" --user-generated-content true    # public sharing/feeds
```

⚠️ `--all-none` is a *claim about the product*, not a formality. Public sharing, chat between users,
web browsing or medical content make it a false declaration and grounds for rejection.

Apple's dependency chain: `userGeneratedContent=true` is required before `socialMedia` can be true;
both `ageAssurance=true` and `socialMedia=true` before `socialMediaAgeRestricted`. Set every
prerequisite in the same edit or explicitly preserve current values. Use `--age-rating-override-v2`
(the older `--age-rating-override` is deprecated).

## Version metadata and localizations

```bash
asc versions view --version-id "VERSION_ID" --include-build --include-submission --output table
asc localizations list --version "VERSION_ID" --output table

asc metadata pull --app "APP_ID" --version "1.0" --platform IOS --dir "./metadata"
# edit files under ./metadata
asc metadata validate --dir "./metadata" --output table          # offline length/required checks
asc metadata push --app "APP_ID" --version "1.0" --dir "./metadata" --dry-run --output table
asc metadata push --app "APP_ID" --version "1.0" --dir "./metadata"
```

Read the dry-run diff before applying. Don't overwrite local edits with a `pull` unless the user
chose the remote copy as source of truth.

Limits worth pre-checking: name 30 · subtitle 30 · **keywords 100 chars total** (comma-separated, no
spaces after commas — spaces waste budget) · promo text 170 · description 4000.

## App info and privacy policy URL

```bash
asc apps info list --app "APP_ID" --output table
asc app-setup info set --app "APP_ID" --primary-locale "en-US" \
  --privacy-policy-url "https://example.com/privacy"
```

"Multiple app infos found" = the app has both a live and an editable record; resolve the exact
APP_INFO_ID from the list before editing.

A privacy policy URL is mandatory for every iOS app — even one that collects nothing (a one-paragraph
"runs on-device, collects no data" page satisfies it). No page yet? The `/legal` skill generates the
copy; host it in seconds on Cloudflare Pages for a live URL Apple accepts (no custom domain needed):

```bash
wrangler pages project create <name> --production-branch production
wrangler pages deploy ./site --project-name <name> --branch production   # → https://<name>.pages.dev
```

A brand-new Pages project serves 522 for ~30–60 s while its edge cert provisions — recheck until 200
before pasting the URL into ASC. The same site can carry both the Privacy Policy (`/privacy`) and the
Support/Marketing URL (its root).

## Pricing and availability

**The classic miss** — a separate required item from everything else. Check whether a record exists
at all before editing; `edit` fails on a missing record.

```bash
asc pricing availability view --app "APP_ID" --output table

# first time — create, don't edit
asc pricing availability create --app "APP_ID" --territory "USA,GBR" \
  --available true --available-in-new-territories true

# afterwards
asc pricing availability edit --app "APP_ID" --territory "USA,GBR" --available true
```

Ask which territories — don't assume a standard list. Worldwide is a real answer, and there are
**175** of them, so build the list instead of typing it:

```bash
TERR=$(asc pricing territories list --paginate --output json \
  | jq -r '[.. | objects | select(.type=="territories") | .id] | unique | join(",")')
asc pricing availability create --app "APP_ID" --territory "$TERR" \
  --available true --available-in-new-territories true
```

**Availability is not price.** A free app still needs an explicit price schedule, and its date rule
is unforgiving:

```bash
asc pricing schedule create --app "APP_ID" --free --base-territory "USA" --start-date "YYYY-MM-DD"
```

⚠️ `--start-date` is mandatory and accepts **only today in Apple's timezone (US Pacific)**. A future
date fails with *"Entire timeline must be covered … start date … in the future"*; an earlier one
fails with *"Interval can not have a start date in the past"*. When your local date is ahead of
Pacific, "today" for you is rejected — use the Pacific date: `TZ=America/Los_Angeles date +%F`.

## Review details

```bash
asc review details-for-version --version-id "VERSION_ID" --output table
asc review details-create --version-id "VERSION_ID" \
  --contact-first-name "Dev" --contact-last-name "Support" \
  --contact-email "dev@example.com" --contact-phone "+1 555 0100" \
  --notes "Explain the reviewer access path here."
asc review details-update --id "DETAIL_ID" --notes "Updated reviewer instructions."
```

⚠️ **`--contact-phone` is required** even though nothing in `--help` marks it so — without it the API
returns *"missing a required attribute … 'contactPhone'"*. Ask the user for it; it is reviewer-only
and never shown on the store page.

⚠️ **`details-create` can leave `demoAccountRequired: true`** despite the flag defaulting to false.
Read the response back, and if it is true, clear it — otherwise App Review waits for credentials
you never supplied:

```bash
asc review details-update --id "DETAIL_ID" --demo-account-required=false
```

Update the resolved record instead of creating a duplicate. Notes should state plainly whether the
app works without an account, and explain any camera/location/AR/health usage. Set demo-account
fields only when review genuinely needs credentials — **never print those secrets in logs or handoff
text**.

## Screenshots

```bash
asc screenshots list --version-localization "LOC_ID" --output table
asc screenshots sizes --output table
asc screenshots validate --path "./screenshots" --device-type "IPHONE_65" --output table
```

Production and upload: [screenshots.md](screenshots.md).

## Stuck or rejected submissions

```bash
asc review status --app "APP_ID" --version "1.0" --output table
asc submit status --version-id "VERSION_ID" --output table
asc review history --app "APP_ID" --version "1.0" --paginate --output table   # current stall vs. old rejections
asc status --app "APP_ID" --include builds,appstore,submission,review --output table
```

Cancel only with evidence and the user's approval — never just because review feels slow:

```bash
asc submit cancel --version-id "VERSION_ID" --app "APP_ID" --confirm
```

Retry sequence (there is no retry command): cancel if the active submission must be withdrawn →
repair proven blockers → re-run `asc validate` → confirm no active submission owns the version →
submit again. Reuse an inspected `READY_FOR_REVIEW` draft rather than creating a second submission.
