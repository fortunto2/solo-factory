# Metadata, keywords, ASO, release notes

Canonical metadata workflow plus the rules that decide whether the listing actually ranks and converts.

## Contents
- [Canonical workflow](#canonical-workflow)
- [Character limits](#character-limits)
- [Keywords and ASO rules](#keywords-and-aso-rules)
- [Writing What's New](#writing-whats-new)
- [Localization](#localization)
- [Migrating from fastlane](#migrating-from-fastlane)

---

## Canonical workflow

```bash
asc metadata pull --app "APP_ID" --version "1.0" --platform IOS --dir "./metadata"
# edit files
asc metadata validate --dir "./metadata" --output table          # offline, catches limit violations
asc metadata push --app "APP_ID" --version "1.0" --platform IOS --dir "./metadata" --dry-run --output table
asc metadata push --app "APP_ID" --version "1.0" --platform IOS --dir "./metadata"
```

File layout:
- `metadata/app-info/<locale>.json` — app-level: `name`, `subtitle`, `privacyPolicyUrl`,
  `privacyChoicesUrl`, `privacyPolicyText`
- `metadata/version/<version>/<locale>.json` — version-level: `description`, `keywords`,
  `marketingUrl`, `promotionalText`, `supportUrl`, `whatsNew`

⚠️ **`pull` only writes fields that exist remotely.** On a fresh version every version-level field is
null, so `metadata/version/<v>/<locale>.json` **is not created at all** — `pull` reports
`fileCount: 1` (just app-info) and it looks like the command half-failed. Create the file by hand
with the fields you intend to set; `push` picks it up and reports them as `add`. Same for `subtitle`:
it is app-info, not version, and is missing from the pulled JSON until it has a value.

Copyright is **not** a localization field: `asc versions update --version-id "VERSION_ID" --copyright "2026 Your Company"`.

Multiple app-info records (a live one plus an editable one) → resolve first and pass explicitly:
`asc apps info list --app "APP_ID" --output table`, then `asc metadata pull --app-info "APP_INFO_ID" …`.

Subscription apps get an extra Terms-of-Use/EULA heuristic: `asc metadata validate --subscription-app`.

**Review-artifact flow** when a change needs durable approval before it mutates anything:

```bash
asc metadata plan    --app "APP_ID" --version "1.0" --dir "./metadata" --review-dir ".asc/metadata/review"
asc metadata approve --review-dir ".asc/metadata/review" --all      # or --key "version:en-US:whatsNew"
asc metadata status  --review-dir ".asc/metadata/review" --output table
asc metadata apply   --app "APP_ID" --version "1.0" --dir "./metadata" --review-dir ".asc/metadata/review" --confirm
```

One-off edits without the file tree (always pass an explicit version selector — never rely on
"latest"):

```bash
asc apps info edit --app "APP_ID" --version "1.0" --platform IOS --locale "en-US" --keywords "a,b,c"
asc apps info edit --app "APP_ID" --version-id "VERSION_ID" --locale "en-US" --whats-new "…"
asc app-setup info set --app "APP_ID" --locale "en-US" --name "App Name" --subtitle "Subtitle"
```

---

## Character limits

| Field | Limit | Indexed for search? | Needs a new submission? |
|---|---|---|---|
| Name | 30 | **Yes** | Yes |
| Subtitle | 30 | **Yes** | Yes |
| Keywords | 100 (comma-separated) | **Yes** | Yes |
| Description | 4000 | No | Yes |
| What's New | 4000 | No | Yes |
| Promotional Text | 170 | No | **No — the only live-editable field** |

---

## Keywords and ASO rules

**Indexing.** Only title + subtitle + keywords are indexed. Apple's full-text search **combines words
across all three**, so "quran" in keywords plus "recitation" in the subtitle already matches
"quran recitation". Screenshot captions are OCR-indexed since the June 2025 algorithm update — put
high-value words in caption text.

**Keyword field mechanics:**
- Comma-separated, **no space after commas** — spaces burn characters. `quran,recitation` ✓
- **Never repeat** a word already in the name or subtitle — all three are indexed together, so
  repetition wastes budget.
- Never put the app name in keywords; it's already indexed.
- Skip plurals when the singular is present — Apple stems.
- Prefer **single words** over phrases: more cross-field combinations, fewer characters.
- Target **90%+ utilization** of the 100 chars; subtitle **65%+** of its 30.
- Validate against popularity data before swapping — never guess.

**Description** isn't indexed but still matters: users who see their search terms reflected convert
better, and conversion feeds ranking.

**Promotional text** is the only field that changes without a submission — refresh it monthly or for
seasonal pushes.

Keyword-only workflow:

```bash
asc metadata keywords diff  --app "APP_ID" --version "1.0" --dir "./metadata"
asc metadata keywords apply --app "APP_ID" --version "1.0" --dir "./metadata" --confirm
asc metadata keywords import --dir "./metadata" --version "1.0" --locale "en-US" --input "./keywords.csv"
```

Discoverability tags Apple generated for the app: `asc app-tags --help`.

**Non-Latin scripts:**
- Arabic — Apple likely normalizes the definite article ال, so "القرآن" and "قرآن" are probable
  duplicates. But hamza variants ("قران" vs "قرآن") hit different queries; both may be worth having.
- Chinese — no word-separating spaces; tokens split on `、` or `，`. Never whitespace-tokenize.
- Cyrillic storefronts — include the Latin spelling too; many users type in Latin script.

---

## Writing What's New

**The 170-character rule.** Only the first ~170 chars show without tapping "more". Lead with the
single most impactful change as a complete sentence — assume nobody taps "more".

Structure (omit empty sections): **New** → **Improved** → **Fixed**.

Tone: benefit-focused, direct address ("you"), action verbs, specifics. "Find your favorites in
seconds", not "Optimized search indexing algorithm."

| Don't | Why |
|---|---|
| "Bug fixes and improvements" | Says nothing; wastes the conversion slot |
| "Version 2.1.0 — we've been working hard!" | Version numbers in headings violate Apple guidelines |
| Naming competitors | Against App Store Review Guidelines |
| "Now matching our Android version" | Alienates iOS users |
| Keyword stuffing | What's New isn't indexed — every word must serve conversion |
| Walls of text | Users skim |

Bad: *"Fixed bugs. Updated UI. Various improvements."*
Good: *"Real-time highlighting is now perfectly synced, even at 2x speed. Dark mode colors are easier on the eyes, and the app launches 40% faster."*

**Keyword echo:** weave the locale's actual keywords into the notes *where they're relevant* — users
recognizing their search terms trust they found the right app. Never force unrelated keywords.

Pair each release with a refreshed **Promotional Text** (170 chars) summarizing the theme — it ships
without a submission.

---

## Localization

```bash
asc localizations list --version "VERSION_ID" --output table
asc localizations download --version "VERSION_ID" --path "./localizations"
asc localizations upload --version "VERSION_ID" --path "./localizations" --dry-run
```

Rules that matter more than the mechanics:
- **Localize keywords per market — don't translate them.** Research what users in that locale
  actually search. Identical keyword fields across locales is the tell-tale sign of untranslated
  metadata. A keyword with popularity 70 in the US store can be 5 in France.
- Formal register everywhere (вы / Sie / vous / usted).
- Cultural adaptation over literal translation — idioms need local equivalents.
- Budget for **30–40% text expansion** vs. English. Keep English What's New at 500–1500 chars.
- If a translation overflows 4000 chars, **shorten — never truncate mid-sentence**.

---

## Migrating from fastlane

```bash
asc migrate export --app "APP_ID" --version-id "VERSION_ID" --output-dir "./fastlane"
asc migrate validate --fastlane-dir "./fastlane"
asc migrate import --app "APP_ID" --version-id "VERSION_ID" --fastlane-dir "./fastlane" --dry-run
```

Use only for existing fastlane-format trees; new work goes through the canonical JSON above.
