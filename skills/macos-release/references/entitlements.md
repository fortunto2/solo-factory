# Entitlements and hardened runtime

Notarization requires the **hardened runtime** (`codesign --options runtime`) on every executable.
The runtime blocks things an ordinary process may do; an entitlement re-allows exactly one of them.
Start with an empty `<dict/>`, run the app, add only what a real failure demands.
Apple: https://developer.apple.com/documentation/security/hardened_runtime ,
https://developer.apple.com/documentation/bundleresources/entitlements

| Symptom under hardened runtime | Entitlement key |
|---|---|
| Microphone records silence | `com.apple.security.device.audio-input` (+ `NSMicrophoneUsageDescription`) |
| Camera black | `com.apple.security.device.camera` (+ `NSCameraUsageDescription`) |
| Photos library read fails | `com.apple.security.personal-information.photos-library` (+ `NSPhotoLibraryUsageDescription`) |
| App loads plug-ins or dylibs signed by other teams (CLAP/VST hosts, Python extensions) | `com.apple.security.cs.disable-library-validation` |
| JIT, a JS/WASM engine, anything that makes executable memory | `com.apple.security.cs.allow-jit` and/or `com.apple.security.cs.allow-unsigned-executable-memory` |
| Network, only when the App Sandbox is on | `com.apple.security.network.client` |
| File picker access, only when sandboxed | `com.apple.security.files.user-selected.read-write` |

Rules:
- Each privacy entitlement needs its Info.plist usage string too; a missing string crashes the app on
  first access.
- The sandbox is optional outside the store. `files.*` and `network.*` keys only matter if you enable
  `com.apple.security.app-sandbox`.
- Give helper executables the same entitlements when they use the capability (a helper that records
  audio or loads plug-ins needs it as much as the app).
- Never ship `com.apple.security.get-task-allow` (debug); notarization rejects it.
- Inspect what a signed file carries: `codesign -d --entitlements :- App.app`.
- If the app works unsigned and fails when signed, a runtime exception is missing: watch
  `log stream --predicate 'eventMessage CONTAINS "library validation"'` while launching it.
