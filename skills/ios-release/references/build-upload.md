# Build, export, upload

From Xcode project to a processed build in App Store Connect, without Fastlane.

## Contents
- [One-shot](#one-shot)
- [Step by step](#step-by-step)
- [Version and build numbers](#version-and-build-numbers)
- [Signing](#signing)
- [Repeatable pipeline](#repeatable-pipeline)
- [Gotchas](#gotchas)

---

## One-shot

`publish` accepts a project instead of an `.ipa` — it archives, exports, uploads, and waits:

```bash
asc publish testflight --app "APP_ID" --project "App.xcodeproj" --scheme "App" \
  --group "Beta" --wait --output table
```

Use `--workspace` for a workspace. Same flags on `asc publish appstore` (add `--version`, and
`--submit --confirm` only with the user's OK).

---

## Step by step

```bash
asc xcode archive --project "App.xcodeproj" --scheme "App" --configuration Release \
  --archive-path ".asc/artifacts/App.xcarchive" --clean --overwrite \
  --xcodebuild-flag=-destination --xcodebuild-flag=generic/platform=iOS \
  --xcodebuild-flag=-allowProvisioningUpdates --output json

asc xcode export --archive-path ".asc/artifacts/App.xcarchive" \
  --ipa-path ".asc/artifacts/App.ipa" --overwrite --timeout 10m \
  --xcodebuild-flag=-allowProvisioningUpdates --output json

asc builds upload --app "APP_ID" --ipa ".asc/artifacts/App.ipa"
asc builds list --app "APP_ID" --limit 5 --output table    # wait for processingState VALID
asc versions attach-build --version-id "VERSION_ID" --build-id "BUILD_ID"   # bind it to the version
```

Attaching is its own step — **don't** reach for `asc release stage --build` just to attach (that
command also requires a metadata source, `--metadata-dir` or `--copy-metadata-from`). Two clean ways:
`asc versions attach-build` standalone, or let `asc review submit --build "BUILD_ID"` attach it at
submit time (it no-ops if already attached). Only if neither is available, PATCH iris
`appStoreVersions/{id}/relationships/build`.

⚠️ **Auto-generated export options need a signed-in Xcode account.** With none, export dies on
`No profiles for 'com.example.app' were found` (preceded by `Invalid credentials in keychain …
missing Xcode-Token`) even though the archive signed fine and the profile is installed — the
generated plist asks for *automatic* signing. Write the plist yourself and name the profile:

```xml
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>TEAMID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>iPhone Distribution: Your Name (TEAMID)</string>
  <key>provisioningProfiles</key>
  <dict><key>com.example.app</key><string>App AppStore</string></dict>
  <key>uploadSymbols</key><true/>
</dict>
```

```bash
xcodebuild -exportArchive -archivePath App.xcarchive -exportPath ./export \
  -exportOptionsPlist ./ExportOptions-AppStore.plist
```

Archiving with manual signing takes the same four settings on the command line:
`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="iPhone Distribution: …" PROVISIONING_PROFILE_SPECIFIER="App AppStore" DEVELOPMENT_TEAM=TEAMID`
— they override `CODE_SIGN_STYLE: Automatic` in a generated project without editing it.

`export` generates App Store export options automatically when `--export-options` is omitted, at a
unique archive-adjacent path it reports in the result. To pin one for inspection or reuse:

```bash
asc xcode export-options generate --archive-path ".asc/artifacts/App.xcarchive" \
  --output-path ".asc/export-options-app-store.plist" --overwrite
```

Raise `ASC_UPLOAD_TIMEOUT_SECONDS` for large IPAs on slow links.

---

## Version and build numbers

⚠️ **`MARKETING_VERSION` must equal the App Store version string exactly, character for character.**
A project building `1.0.0` cannot supply a build to an App Store version called `1.0` — the builds
upload fine, reach `VALID`, appear in the build list, and simply never become selectable for that
version. Nothing says why. An app can sit "almost ready" for months on this alone: the release notes
say *select a build*, the build list looks healthy, and the two version strings differ by one `.0`.

Check both before archiving, not after uploading:

```bash
asc status --app "APP_ID" --output table | grep -A1 "APP STORE"   # the version string ASC expects
rg -n "MARKETING_VERSION" project.yml *.xcconfig 2>/dev/null      # what the project stamps
```

If they differ, change the project to match the App Store version (or create the matching version in
ASC) — do not just bump the build number.

Apple rejects a duplicate build number for the same version string. Let the API pick the next one:

```bash
asc builds next-build-number --app "APP_ID" --version "1.0" --platform IOS \
  --initial-build-number 1 --output json
```

Then feed it into the archive:

```bash
asc xcode archive … --xcodebuild-flag=MARKETING_VERSION=1.0 --xcodebuild-flag=CURRENT_PROJECT_VERSION=7
```

Or edit the project first: `asc xcode version edit --build-number "7"`.

For projects that generate their Info.plist/xcconfig, `asc xcode inject` materializes release values
from a manifest — this replaces the usual Fastlane bump scripts:

```bash
asc xcode inject --manifest .asc/deployment.json --set version="1.0" --set build_number="7" --overwrite
```

`.asc/deployment.json` declares `values` plus `outputs` of type `plist`, `text` (e.g. a
`Deployment.xcconfig` with `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`), or `copy`. Point the
Xcode target at the generated files once, and every release just re-runs `inject`.

---

## Signing

`--xcodebuild-flag=-allowProvisioningUpdates` lets Xcode fetch/renew profiles during archive — the
simplest path for a solo developer with automatic signing, and usually all you need. Manual signing
resolution in `asc xcode export` is macOS-only (it inspects local identities and profiles).

New app, or rotating assets:

```bash
asc bundle-ids create --identifier "com.example.app" --name "Example" --platform IOS
asc bundle-ids capabilities add --bundle "BUNDLE_ID" --capability ICLOUD
asc certificates create --certificate-type IOS_DISTRIBUTION --generate-csr \
  --key-out "./signing/dist.key" --csr-out "./signing/dist.csr"
asc profiles create --name "AppStore Profile" --profile-type IOS_APP_STORE \
  --bundle "BUNDLE_ID" --certificate "CERT_ID"
asc profiles download --id "PROFILE_ID" --output "./profiles/AppStore.mobileprovision"
asc profiles local install --path "./profiles/AppStore.mobileprovision"
```

**No Xcode account? Sign entirely from the CLI.** `asc certificates list` showing DISTRIBUTION certs
does **not** mean you can sign — a certificate is useless without its private key, and the key lives
only on the machine that generated the CSR. Check what you can actually sign with:

```bash
security find-identity -v -p codesigning     # "Apple Distribution" / "iPhone Distribution" present?
```

If it isn't there, mint a new one (Apple allows a few; revoke an unused one if you hit the cap):

```bash
asc certificates create --certificate-type IOS_DISTRIBUTION --generate-csr \
  --key-out ./dist.key --csr-out ./dist.csr --common-name "Your Name" --email you@example.com
asc certificates view --id "CERT_ID" --output json | jq -r '.data.attributes.certificateContent' \
  | base64 -d > dist.cer
openssl x509 -inform DER -in dist.cer -out dist.pem
openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem -out dist.p12 -passout pass:TEMP
security import dist.p12 -k ~/Library/Keychains/login.keychain-db -P TEMP -T /usr/bin/codesign
```

⚠️ **`-legacy` is not optional.** OpenSSL 3 defaults to AES-256-CBC + PBKDF2, which macOS `security`
cannot read — the import fails with *"MAC verification failed during PKCS12 import (wrong
password?)"*, which sends you hunting a password problem that doesn't exist.

Then the matching profile:

```bash
asc bundle-ids list --paginate --output json | jq -r '..|objects|select(.type=="bundleIds")
  |"\(.id)  \(.attributes.identifier)"'
asc profiles create --name "App AppStore" --profile-type IOS_APP_STORE \
  --bundle "BUNDLE_ID" --certificate "CERT_ID"
asc profiles download --id "PROFILE_ID" --output ./App.mobileprovision
asc profiles local install --path ./App.mobileprovision
```

Store the key material outside any repo (`~/.appstoreconnect/certs`, `chmod 700`) and delete the
`.p12` once imported.

Cleanup and audit:

```bash
asc certificates revoke --id "CERT_ID" --confirm
asc profiles list --profile-state ACTIVE,INVALID --paginate --output json
asc profiles local clean --expired --dry-run
```

⚠️ **`profileState` is not a reliable expiry signal** — Apple reports some profiles as `ACTIVE` with
a past `expirationDate`. For a real expired-profile audit, compare `expirationDate` to today rather
than filtering on `INVALID`.

**Sharing signing assets across machines** — a lightweight, non-interactive alternative to
`fastlane match`, encrypted in a git repo:

```bash
asc signing sync push --bundle-id "com.example.app" --profile-type IOS_APP_STORE \
  --repo "git@github.com:team/certs.git" --password "$ASC_MATCH_PASSWORD"
asc signing sync pull --repo "git@github.com:team/certs.git" \
  --password "$ASC_MATCH_PASSWORD" --output-dir "./signing"
```

`pull` writes files to disk; keychain import and profile installation are separate steps.
Check `--help` for exact certificate/profile type enums — they're long and change.

---

## Repeatable pipeline

`asc workflow` composes asc and shell steps from `.asc/workflow.json`, passing values between steps
via JSONPath outputs:

```json
{
  "env": { "APP_ID": "1234567890", "PROJECT_PATH": "App.xcodeproj", "SCHEME": "App", "VERSION": "" },
  "workflows": {
    "testflight_beta": {
      "description": "Archive, export, upload, distribute.",
      "steps": [
        { "name": "resolve_next_build",
          "run": "asc builds next-build-number --app \"$APP_ID\" --version \"$VERSION\" --platform IOS --initial-build-number 1 --output json",
          "outputs": { "BUILD_NUMBER": "$.nextBuildNumber" } },
        { "name": "archive",
          "run": "asc xcode archive --project \"$PROJECT_PATH\" --scheme \"$SCHEME\" --configuration Release --archive-path \".asc/artifacts/App-$VERSION.xcarchive\" --clean --overwrite --xcodebuild-flag=-allowProvisioningUpdates --xcodebuild-flag=MARKETING_VERSION=$VERSION --xcodebuild-flag=CURRENT_PROJECT_VERSION=${steps.resolve_next_build.BUILD_NUMBER} --output json",
          "outputs": { "ARCHIVE_PATH": "$.archive_path" } },
        { "name": "export",
          "run": "asc xcode export --archive-path ${steps.archive.ARCHIVE_PATH} --ipa-path \".asc/artifacts/App-$VERSION.ipa\" --overwrite --timeout 10m --output json",
          "outputs": { "IPA_PATH": "$.ipa_path" } },
        { "name": "publish",
          "run": "asc publish testflight --app \"$APP_ID\" --ipa ${steps.export.IPA_PATH} --group \"Beta\" --wait --poll-interval 10s --output json" }
      ]
    }
  }
}
```

Run: `asc workflow run --name testflight_beta --set VERSION=1.0`. Confirm flags with
`asc workflow --help` — this surface is evolving.

Xcode Cloud instead of local builds: `asc xcode-cloud run --app "APP_ID" --workflow "CI" --branch main --wait`.

---

## Gotchas

**`exportArchive` fails with "Copy failed" — it is your `rsync`.** Xcode shells out to `rsync` to
assemble the .ipa and takes whichever one is first in `PATH`. A modern rsync (Homebrew ships 3.5.0)
is incompatible with what Xcode drives, and the export dies on `IDEDistributionCreateIPAStep`. The
error says nothing about rsync; you only see it in the distribution log:

```
rsync error: syntax or usage error (code 1) at main.c(1886) [server=3.5.0]
Step "<IDEDistributionCreateIPAStep>" failed with error "Copy failed"
```

Read that log — `xcodebuild` prints its path on failure, and the useful line is in
`IDEDistributionPipeline.log`. The fix is to hand Xcode the system one, which is openrsync claiming
2.6.9 compatibility:

```bash
env PATH="/usr/bin:/bin:/usr/sbin:/sbin" xcodebuild -exportArchive …
```

This is per-machine, not per-project: once Homebrew's rsync is on the box, every iOS project on it
exports the same way and fails the same way. Check with `which -a rsync`.

Do not work around it by zipping `Payload/` by hand. That produces an installable .ipa, but it skips
the step that writes `beta-reports-active` into the entitlements — the key TestFlight needs — and
you will not notice until a build refuses to distribute.

**Missing `iosApp` scheme.** `xcodebuild -scheme iosApp …` failing with "does not contain a scheme
named iosApp" means a shared scheme for another target (e.g. a widget) disabled autogeneration.
Create a shared `xcshareddata/xcschemes/iosApp.xcscheme` pointing at the app target's
BlueprintIdentifier (read it from `project.pbxproj`) — caretta-friends has a working file.

**Encryption prompt → build EXPIRES ~1 day after upload.** Set `ITSAppUsesNonExemptEncryption=false`
in Info.plist when the app only uses standard HTTPS/TLS. Without it, the upload leaves an *unanswered*
export-compliance question, and Apple expires the build roughly **24 h** after upload — even though
`processingState` is `VALID`. The tell: `asc builds list` shows `Expired: true` with an
`expirationDate` one day after `uploadedDate`, and `asc validate` blocks with `build.invalid.expired`
on a build you uploaded days ago. Two fixes: (a) add the plist key and re-archive (permanent — do this
for XcodeGen projects in `project.yml` `info.properties`), or (b) answer compliance on the existing
build via the API instead of rebuilding: `asc builds update --build-id "…" --uses-non-exempt-encryption false`
(confirm the flag with `asc builds update --help`). A build already past its `expirationDate` can't be
un-expired — upload a fresh one.

**`xcodebuild` can deadlock inside an agent session.** Its build service sometimes hangs when
launched from a non-Terminal context. Run it as a **background task** rather than blocking the
session, and if it still hangs, hand the user the exact command to paste into a real Terminal window.
Also note: piping through `tail` swallows the exit code — a backgrounded `xcodebuild … | tail` reports
success on a failed build. Grep the log for `BUILD SUCCEEDED` / `BUILD FAILED` instead of trusting
the exit status.

**Simulator link failure on x86_64 for Rust/C-backed projects.**
`-destination 'generic/platform=iOS Simulator'` builds **both** arm64 and x86_64. A static library
compiled only for `aarch64-apple-ios-sim` links fine for arm64 and dies with
`ld: symbol(s) not found for architecture x86_64`. Fix: add `ARCHS=arm64 ONLY_ACTIVE_ARCH=NO`, or
build the static lib for both targets and lipo them together.

**BETA_CONTRACT_MISSING (422).** ASC → Business → Agreements must all be Active (Paid + Free Apps).
If they are and it still fails, it's an Apple-side bug — contact support rather than retrying.

**Processing takes minutes to an hour.** `--wait --poll-interval 10s` on publish, or poll
`asc builds list`. A build stuck far longer than an hour usually means Apple rejected the binary —
check email and `asc builds info --build-id … --output table`.

**Keep artifacts out of git.** `.asc/artifacts/`, `*.xcarchive`, `*.ipa`, and any `*.p8` belong in
`.gitignore`.

---

## Shipping a macOS build outside the App Store

For a downloadable `.app` (beta, desktop companion), the gate is Gatekeeper, not App Review. Full
path, all steps required:

```bash
security find-identity -v -p codesigning | grep "Developer ID"     # different cert from IOS_DISTRIBUTION

codesign --force --deep --options runtime --timestamp \
  --entitlements entitlements.plist \
  --sign "Developer ID Application: Name (TEAMID)" "My App.app"

ditto -c -k --keepParent "My App.app" App.zip
xcrun notarytool submit App.zip --key AuthKey_KEYID.p8 --key-id KEYID --issuer ISSUER-UUID --wait
xcrun stapler staple "My App.app"          # attach the ticket for offline verification
spctl -a -vv "My App.app"                  # must read: accepted, source=Notarized Developer ID
```

The **same App Store Connect `.p8` key** authenticates `notarytool` — no extra credentials. Typical
turnaround is a couple of minutes.

⚠️ **A raw executable is not an app.** A bare Mach-O binary has no bundle, so macOS gives it no
window server registration: it runs but never shows a window, and `System Events` cannot see it.
Wrap it in `My App.app/Contents/{MacOS,Resources}` with an `Info.plist` (`CFBundleExecutable`,
`CFBundleIdentifier`, `LSMinimumSystemVersion`) and an `.icns` built by `iconutil`.

⚠️ **Hardened runtime breaks dynamically linked Homebrew dependencies — this is the big one.**
A binary built on a dev machine happily links `/opt/homebrew/opt/ffmpeg/lib/libavcodec.*.dylib`.
After signing it dies at launch with:

```
Library not loaded: /opt/homebrew/opt/ffmpeg/lib/libavcodec.62.dylib
… mapping process and mapped file (non-platform) have different Team IDs
```

Two separate problems: the library is signed by Homebrew, not you, and the person downloading your
app does not have it at all. `com.apple.security.cs.disable-library-validation` silences the first
and leaves the second — the app still fails on any machine without that exact Homebrew formula.
The real fix is to link the dependency statically (in Rust, a `static-ffmpeg`-style feature) or ship
the dylibs inside `Contents/Frameworks` and re-sign them with your identity. **Test the signed app
from a path the build machine never used, or you will ship something that only runs on your laptop.**

Entitlements a WebView-based desktop app (Tauri, Dioxus, Electron) usually needs:
`com.apple.security.cs.allow-jit`, `com.apple.security.cs.allow-unsigned-executable-memory`,
`com.apple.security.files.user-selected.read-write`, `com.apple.security.network.client`.
