---
name: solo-macos-release
description: Ship a macOS app outside the Mac App Store - Developer ID signing, hardened runtime, DMG, notarization with notarytool, stapling, verification, GitHub release and a Homebrew cask bump. Use when the user says "ship the Mac app", "notarize", "notarytool", "DMG", "Developer ID", "sign the app", "hardened runtime", "Homebrew cask", "tap", "Gatekeeper", "app is damaged and can't be opened", "cannot be opened because the developer cannot be verified", or "stapler". Works for native Swift, Rust (Dioxus, Tauri) and any bundle with helper binaries. Do NOT use for TestFlight, iPhone or App Store submissions (use /ios-release), or for Android (use /android-release).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "📦"
---

# macos-release - ship a Mac app without the store

Direct distribution: sign with a **Developer ID Application** certificate, Apple scans the upload
(**notarization**), you **staple** the ticket, and users open the DMG with no warning. No review,
no listing, no sandbox requirement. Sibling: **`ios-release`** (store route, table below).

Golden rules:
- **Never publish (`gh release create`, cask push) without the user's OK.** The script signs,
  notarizes and prints the publish commands; it does not run them.
- **Sign inside-out.** Every nested Mach-O first, the app last, the DMG after. `--deep` is for
  verifying, not for signing.
- **The proof is Gatekeeper, not `codesign --verify`.** Verify the final file with the commands below.
- **Read the notary log on any failure** (`notarytool log <id>`); do not guess.
- Secrets (key path, key id, issuer) live in env or the keychain, never in the script or repo.

## One-time setup

1. A Developer ID Application certificate in the login keychain:
   `security find-identity -v -p codesigning | grep "Developer ID Application"`.
2. Notary credentials stored once as a keychain profile:
   `xcrun notarytool store-credentials example-notary --apple-id user@example.com --team-id TEAMID12345`
   (prompts for an app-specific password), or with an App Store Connect API key
   (`--key AuthKey_XXXX.p8 --key-id XXXX --issuer <uuid>`). Check:
   `xcrun notarytool history --keychain-profile example-notary`.
3. `entitlements.plist` (start empty, see [references/entitlements.md](references/entitlements.md)) and an
   `Info.plist` with `CFBundleIdentifier` (e.g. `com.example.app`), `CFBundleShortVersionString`,
   an increasing `CFBundleVersion`, `LSMinimumSystemVersion`.

## The order that works

1. **Build** release binaries. Refuse any that link `/opt/homebrew`, `/usr/local` or a build dir
   (`otool -L`).
2. **Assemble** `App.app/Contents/{MacOS,Resources,Frameworks}`; set versions with `plutil -replace`
   or a `__VERSION__` template. Finish every edit to the bundle now.
3. **Sign nested code first**: helper executables, `.dylib`, `.framework`, plug-ins, XPC services:
   `codesign --force --options runtime --timestamp --entitlements E.plist --sign "$IDENTITY" <file>`
4. **Sign the app** the same way, last.
5. `codesign --verify --deep --strict --verbose=2 App.app`; smoke-run the bundled helpers.
6. **DMG**: stage `App.app` plus `ln -s /Applications`, `hdiutil create -format UDZO`, then
   `codesign --force --timestamp --sign "$IDENTITY" App.dmg` (no `--options runtime` on a DMG).
7. **Notarize the DMG**: `xcrun notarytool submit App.dmg --keychain-profile example-notary --wait`.
8. **Staple**: `xcrun stapler staple App.dmg`.
9. **Verify** (below), then `shasum -a 256 App.dmg`.
10. **Publish** with the user's OK: `gh release create`, then bump the cask.

## Verification (final artifact)

```bash
codesign --verify --deep --strict --verbose=2 App.app
spctl -a -vv -t exec App.app            # accepted, source=Notarized Developer ID
spctl -a -vv -t open --context context:primary-signature App.dmg
xcrun stapler validate App.dmg          # The validate action worked!
```

`source=Unnotarized Developer ID` or `rejected`: ticket missing or the bundle changed after signing.
The real last test is a **browser download** (sets quarantine) opened on another Mac or a fresh
user. `spctl` on the build Mac passes more easily and proves less.

## Script

[scripts/release-dmg.sh](scripts/release-dmg.sh) does steps 3-9 and prints the publish commands.
Env: `APP`, `IDENTITY`, `NOTARY_PROFILE`, `ENTITLEMENTS`, `INNER` (space-separated nested paths
relative to the app, signed first), `DMG_NAME`, `VOLNAME`, `OUT`, `BUILD_CMD`, `REPO`, `CASK`.
`SKIP_BUILD=1` skips `BUILD_CMD`; `SKIP_NOTARY=1` signs only (a local check).

```bash
APP=build/Example.app IDENTITY="Developer ID Application: Example Inc (TEAMID12345)" \
NOTARY_PROFILE=example-notary INNER="Contents/MacOS/helper" \
  skills/macos-release/scripts/release-dmg.sh 1.2.0
```

## Publish (printed, not run)

```bash
gh release create v1.2.0 dist/Example.dmg --title "Example App 1.2.0" --notes-file notes.md
# tap: Casks/example-app.rb -> version "1.2.0", sha256 "<shasum above>"
```

Cask template, bump one-liner, Sparkle: [references/release-and-cask.md](references/release-and-cask.md).

## Checklist

- [ ] Certificate is **Developer ID Application** (not Apple Development, not Mac App Distribution)
- [ ] Every nested binary signed with `--options runtime --timestamp`; app signed last, untouched after
- [ ] No `/opt/homebrew`, `/usr/local` or cargo-dir paths in `otool -L`
- [ ] Entitlements minimal, each one justified by a real failure
- [ ] `codesign --verify`, `spctl`, `stapler validate` all clean
- [ ] Tested from a real download with quarantine on another Mac
- [ ] sha256 taken from the stapled DMG that is uploaded
- [ ] Publish commands reviewed with the user

## What differs from the store route

| | Developer ID (this skill) | Mac App Store / TestFlight (`ios-release`) |
|---|---|---|
| Certificate | Developer ID Application | Mac App Distribution + installer |
| Sandbox | optional; hardened runtime required | App Sandbox required |
| Review | automated notary scan, minutes | human review |
| Updates | yours (cask, Sparkle) | the store |

## Traps (full list with causes: [references/traps.md](references/traps.md))

- **Notarized but still refused**: bundle edited after signing, a nested binary unsigned, or a library
  linked to a Homebrew path that does not exist on the user's Mac.
- **`Invalid` from notarytool**: missing `--timestamp`, missing `--options runtime` on one nested
  binary, or an ad-hoc/Apple Development signature inside (cargo link-signs ad hoc).
- **Hardened runtime breaks** plug-in loading, JIT, mic: add the one entitlement, not a wildcard.
- **Rust**: undefined `___isPlatformVersionAtLeast` needs `clang_rt.osx` linked; ship static libs.
- **Cask checksum mismatch**: sha256 of a pre-staple or local copy, not the uploaded file.

## Don't

- Don't sign with `--deep`, and don't re-sign with another identity to "fix" a rejection.
- Don't zip a `.app` with `zip` (breaks symlinks); use `ditto -c -k --keepParent` or a DMG.
- Don't tell users to run `xattr -dr com.apple.quarantine` as the release process; it is a local diagnosis.
- Don't put the Apple ID password or the `.p8` key in the repo.
