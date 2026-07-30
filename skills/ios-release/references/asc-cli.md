# asc CLI — auth, discovery, conventions

Reference for driving `asc` itself. Verified against **3.2.0**.

## Contents
- [Auth](#auth)
- [Command discovery](#command-discovery)
- [Verbs and flags](#verbs-and-flags)
- [Resolving IDs](#resolving-ids)
- [Environment variables](#environment-variables)
- [Repo setup](#repo-setup)

---

## Auth

```bash
asc auth login --name "default" --key-id "KEYID" --issuer-id "ISSUER-UUID" \
  --private-key ./AuthKey_KEYID.p8 --network
asc auth status --verbose
asc auth doctor              # diagnose a broken configuration
asc auth issuer-id           # print the active issuer
asc auth token               # signed JWT for raw curl against the API
```

- Key material is copied into the **macOS Keychain**; the `.p8` can be deleted afterwards. Keep a
  backup somewhere safe — Apple lets you download it exactly once.
- `--key-type individual` for an Individual Key (no issuer ID needed). Team keys need `--issuer-id`.
- Multiple accounts: `--name` creates profiles, `asc auth switch --name work` selects one.
- `--network` validates against the API at login — always use it, a typo'd issuer fails silently otherwise.
- **Never commit a `.p8`.** Add `*.p8` to `.gitignore` before the key lands in a repo directory.
- Inspect what the key is actually allowed to do: `asc web auth capabilities [--key-id KEYID]`.

Roles: **App Manager** covers metadata, builds, TestFlight, and submission. Admin adds Agreements
and user management. Developer alone cannot submit.

---

## Command discovery

Never guess a command path — the tree has 76 groups and moves fast.

```bash
asc search "submit app for review"          # deterministic local search over the command tree
asc search --output table "upload build"
asc <group> --help                          # e.g. asc builds --help
asc <group> <cmd> --help                    # authoritative flag list
asc capabilities --area release --output table       # what's covered / partial / web-session only
asc capabilities --status not-public-api --output table
asc schema --pretty "GET /v1/apps"          # bundled ASC endpoint schemas
```

⚠️ In **zsh**, `asc $var --help` does not word-split. Use `asc ${=var} --help` or `bash -c`.

---

## Verbs and flags

- Prefer `view` over legacy `get` for reads: `asc apps view --id "APP_ID"`.
- Prefer `edit` for update-only surfaces: `asc pricing availability edit …`.
- `create` bootstraps a record that doesn't exist yet — `edit` fails on a missing record
  (notably `pricing availability`: `create` first, then `edit`).
- Always use explicit long flags in automation.
- Destructive operations require `--confirm`. High-level release commands accept `--dry-run`.
- `--paginate` to walk all pages.

**Output:** TTY-aware — `table` interactively, `json` when piped. Force with `--output json|table|markdown`.
`--pretty` is JSON-only. In automation keep data on stdout, diagnostics on stderr.

⚠️ **Errors are printed as plain text, not JSON.** A failing command piped into `jq` dies with
`jq: parse error: Invalid numeric literal` and the real message — a missing required flag, a rejected
value — never reaches you. Never diagnose a failure through `jq`; re-run the bare command and read
what it actually said.

⚠️ **A mutation's response may omit the field you just set.** `asc versions update --copyright …`
returns the version object without `copyright`; that is not a failure. Confirm with `asc validate`
(the blocker disappears) rather than by grepping the write's response.

---

## Resolving IDs

Most commands want IDs, not names.

```bash
asc apps list --bundle-id "com.example.app" --output table     # APP_ID — most precise
asc apps list --name "My App" --output table
asc versions list --app "APP_ID" --platform IOS --paginate     # VERSION_ID
asc builds info --app "APP_ID" --latest --version "1.0" --platform IOS   # latest BUILD_ID
asc builds list --app "APP_ID" --sort -uploadedDate --limit 5 --output table
asc localizations list --version "VERSION_ID" --output table   # VERSION_LOCALIZATION_ID (screenshots need this)
asc testflight groups list --app "APP_ID" --paginate           # GROUP_ID
asc apps info list --app "APP_ID" --output table               # APP_INFO_ID
asc review submissions-list --app "APP_ID" --paginate          # SUBMISSION_ID
asc testflight pre-release list --app "APP_ID" --platform IOS --paginate
```

`export ASC_APP_ID="APP_ID"` once, then omit `--app`. Use `--paginate` on lists so IDs aren't
silently missed, and `--sort` for deterministic ordering.

**Digital goods** have their own ID layer — product IDs are distinct from *version* IDs:

```bash
asc iap list --app "APP_ID" --paginate --output json
asc iap versions list --iap-id "IAP_ID" --paginate --output json
asc subscriptions groups list --app "APP_ID" --paginate --output json
asc subscriptions list --group-id "GROUP_ID" --paginate --output json
asc subscriptions versions list --subscription-id "SUB_ID" --paginate --output json
```

Localizations and images hang off the *version* subtree
(`asc iap versions localizations list --version-id …`).

Stop and ask when app/version/product resolution is ambiguous — never guess between two similar apps.

---

## Environment variables

Fallbacks when the keychain isn't available (CI):

| Variable | Purpose |
|---|---|
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | key identity |
| `ASC_PRIVATE_KEY_PATH` / `ASC_PRIVATE_KEY` / `ASC_PRIVATE_KEY_B64` | key material |
| `ASC_APP_ID` | default app, omit `--app` |
| `ASC_TIMEOUT_SECONDS`, `ASC_UPLOAD_TIMEOUT_SECONDS` | timeouts (raise for big IPAs) |
| `ASC_BYPASS_KEYCHAIN=1` | force config-file storage |
| `ASC_STRICT_AUTH=true` | fail when credential sources are mixed |

Credential resolution: selected profile (keychain/config) → env vars for missing fields. A repo-local
`./.asc/config.json` takes precedence over both.

CI integrations exist for GitHub Actions (`rudrankriyam/setup-asc@v1`), GitLab, Bitrise, CircleCI.

Apple Ads is a **separate** credential system (`asc ads auth`, `ASC_ADS_*`) — App Store Connect keys
do not work there.

---

## Repo setup

```bash
asc init                    # writes ASC.md — a command reference for agents working in this repo
asc docs list               # embedded guides: api-notes, reference, workflows
asc docs show workflows     # task-based recipes
```

Per-repo credentials (rarely needed, prefer the keychain):

```bash
asc auth login --bypass-keychain --local --name "proj" --key-id … --issuer-id … --private-key …
# → ./.asc/config.json — add .asc/config.json to .gitignore
```
