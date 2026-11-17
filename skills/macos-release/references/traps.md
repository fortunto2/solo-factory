# Traps and diagnostics

Rules come from Apple docs; the bundling traps from shipping Swift and Rust (Dioxus) desktop apps this way.
Apple: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution ,
https://developer.apple.com/documentation/security/resolving-common-notarization-issues ,
https://developer.apple.com/documentation/security/customizing-the-notarization-workflow ,
`man notarytool`, `man codesign`, `man stapler`.

## Reading a rejection

```bash
xcrun notarytool submit App.dmg --keychain-profile P --wait   # prints the submission id
xcrun notarytool log <id> --keychain-profile P                # JSON: path + message per issue
xcrun notarytool history --keychain-profile P
```

| Message in the log | Cause | Fix |
|---|---|---|
| signature of the binary is invalid / not signed with a valid Developer ID certificate | a nested file signed ad hoc (cargo and the linker do this) or with Apple Development | re-sign that file with the Developer ID identity |
| signature does not include a secure timestamp | `--timestamp` missing | add it to every codesign call |
| executable does not have the hardened runtime enabled | `--options runtime` missing on one nested binary | add it |
| uses an SDK older than 10.9 | old prebuilt dylib | rebuild or replace |
| requests get-task-allow | debug entitlement | remove it |
| archive contains critical validation errors | not a DMG/zip/pkg, or `zip` broke symlinks | `ditto -c -k --keepParent`, or a DMG |

Every Mach-O in the bundle is scanned, including ones deep in `Resources/` (a bundled CLI, a Python
`.so`, a plug-in). List them: `find App.app -type f -exec file {} + | grep -i mach-o`.

## "Signed and notarized but Gatekeeper still refuses"

1. `spctl -a -vv -t exec App.app`: read `source=`. `Unnotarized Developer ID` = ticket missing, or the
   app changed after the DMG was notarized.
2. `codesign --verify --deep --strict --verbose=2 App.app`: "a sealed resource is missing or invalid"
   means a file was edited, added or removed after signing (a `.DS_Store`, a regenerated cache, a
   `plutil` edit). Do every Info.plist edit before the first codesign.
3. A nested bundle (plug-in, helper app) left unsigned: the deep verify names it.
4. Launch crash `dyld: Library not loaded`: a library path that only exists on your Mac. Test on a Mac
   without Homebrew.
5. The file came through Telegram, Slack, AirDrop or a browser: quarantine is set on the DMG and the
   app inside is checked on first launch. A stapled DMG validates offline; an unstapled one needs the network.
6. Wrong certificate type: `security find-identity -v -p codesigning` must show Developer ID Application.

"Is damaged and can't be opened" usually means a signature that no longer validates (a truncated or
modified download, or a bundle edited after signing). "Cannot be opened because the developer cannot be
verified" means unsigned or unnotarized. `xattr -dr com.apple.quarantine App.app` is a local diagnosis
only, never part of the release instructions.

## Bundled libraries and helper binaries

- **Homebrew dylibs**: a binary linked to `/opt/homebrew/...` runs on your Mac and crashes on every
  other. Fail the build when `otool -L` of any bundled binary shows `/opt/homebrew`, `/usr/local` or a
  cargo target dir. Prefer static linking (for example a `static-ffmpeg` cargo feature) over copying dylibs.
- If you must ship a dylib: copy it to `Contents/Frameworks/`, then
  `install_name_tool -id @rpath/libX.dylib libX.dylib`,
  `install_name_tool -change /opt/homebrew/opt/x/lib/libX.dylib @rpath/libX.dylib bin`,
  `install_name_tool -add_rpath @executable_path/../Frameworks bin`. Rewrite transitive dependencies
  too (loop until `otool -L` is clean). `install_name_tool` invalidates signatures, so sign afterwards.
- **Inner first**: the outer seal records a hash of each nested file; signing the app and then a helper
  breaks the seal. Helpers in `Contents/MacOS/` and tools under `Resources/` all count.
- **Layout**: executables in `Contents/MacOS`, data in `Contents/Resources`, frameworks in
  `Contents/Frameworks`, plug-ins in `Contents/PlugIns`. Framework and plug-in bundles are signed as
  bundles (`codesign` the directory), not file by file.
- **Rust: undefined `___isPlatformVersionAtLeast`**: a C/C++/Metal dependency (ggml, whisper.cpp) uses
  `@available` under a low `MACOSX_DEPLOYMENT_TARGET`. Link compiler-rt from `build.rs`: search path
  `$(clang --print-resource-dir)/lib/darwin`, `cargo:rustc-link-lib=static=clang_rt.osx`.
- **Rust: iOS env leaking**: an `IPHONEOS_DEPLOYMENT_TARGET` set in `.cargo/config.toml` makes a C
  dependency's configure probe build for iPhone and fail ("unable to create an executable"). Set it to
  empty for the macOS build and set `MACOSX_DEPLOYMENT_TARGET` explicitly.
- **Info.plist templating**: keep `__VERSION__` in the source plist and `sed` it, or
  `plutil -replace CFBundleShortVersionString -string "$V"`; always `plutil -lint`. `CFBundleVersion`
  must increase each release (commit count works).
- **Frameworks**: Tauri bundles and notarizes itself from `APPLE_SIGNING_IDENTITY`, `APPLE_ID`,
  `APPLE_PASSWORD`, `APPLE_TEAM_ID`; still run the verification commands, and sign sidecars you add after
  bundling. Dioxus and SwiftPM emit a bare executable, so you assemble the `.app` and the script applies
  in full. Xcode projects: archive, export with Developer ID, then notarize, staple and DMG the same way.

## DMG and zip

- `hdiutil create -volname V -srcfolder STAGE -ov -format UDZO out.dmg`; STAGE holds the app and a
  `/Applications` symlink. Sign the DMG itself.
- Notarize the DMG, then staple it; the app inside is covered by the DMG's ticket. A zip cannot be
  stapled: notarize the zip, staple the `.app`, then re-zip with `ditto`.
- Assemble into a clean directory every time; stale files from an earlier build break the seal.
- Keep spaces out of the served file name (URLs, cask `url`); the volume name may have them.
- `hdiutil create` failing with "resource busy": a previous image is still mounted, `hdiutil detach` it.

## Notary service behaviour

- `--wait` takes minutes, sometimes longer for a new team's first submissions. If it is interrupted,
  resume with `notarytool info <id>` and `notarytool log <id>`.
- A keychain profile keeps secrets off the command line. An App Store Connect API key suits CI. Apple
  ID auth needs an app-specific password, never the account password.
- `altool` notarization is retired; use `notarytool` (Xcode 13+ command line tools).
- `stapler staple` failing with error 65 ("could not find ticket"): the submission was not Accepted or the
  ticket has not propagated; wait a minute and retry.

## Verifying like a user

- A different Mac or a fresh user account, DMG fetched by a browser (sets quarantine), not `cp`/`scp`.
- At most the one-time "downloaded from the Internet" dialog; any "unidentified developer" or "damaged"
  text is a failure.
