#!/usr/bin/env bash
# Sign, DMG, notarize, staple and verify a macOS .app for distribution outside the Mac App Store.
# Prints the publish commands; never publishes.
#
# usage: release-dmg.sh <version>        (or VERSION=1.2.0)
#   APP=path/to/Example.app        built bundle (required)
#   IDENTITY="Developer ID Application: Example Inc (TEAMID12345)"   (required)
#   NOTARY_PROFILE=example-notary  notarytool keychain profile (required unless SKIP_NOTARY=1)
#   ENTITLEMENTS=entitlements.plist  optional
#   INNER="Contents/MacOS/helper Contents/Frameworks/libx.dylib"   nested code, signed first (relative to APP)
#   DMG_NAME=Example.dmg  VOLNAME="Example App"  OUT=dist
#   BUILD_CMD="make release"       run unless SKIP_BUILD=1
#   REPO=user/example-app  CASK=example-app   only used in the printed commands
#   SKIP_BUILD=1   reuse the existing bundle
#   SKIP_NOTARY=1  sign only (the DMG warns on other Macs)
set -euo pipefail

VERSION=${1:-${VERSION:?usage: $0 <version>}}
APP=${APP:?set APP to the built .app}
IDENTITY=${IDENTITY:?set IDENTITY to a Developer ID Application identity}
OUT=${OUT:-dist}
APP_BASENAME=$(basename "$APP" .app)
DMG_NAME=${DMG_NAME:-${APP_BASENAME// /}.dmg}
VOLNAME=${VOLNAME:-$APP_BASENAME}
DMG="$OUT/$DMG_NAME"
INNER=${INNER:-}

if [[ -n ${BUILD_CMD:-} && -z ${SKIP_BUILD:-} ]]; then
  bash -c "$BUILD_CMD"
fi
[[ -d $APP ]] || { echo "no bundle at $APP" >&2; exit 1; }
mkdir -p "$OUT"

# Nothing bundled may need a library only this Mac has.
while IFS= read -r f; do
  if file "$f" | grep -q 'Mach-O'; then
    if otool -L "$f" | tail -n +2 | grep -qE '/opt/homebrew|/usr/local'; then
      echo "refusing: $f links a library outside the system" >&2
      otool -L "$f" | tail -n +2 | grep -E '/opt/homebrew|/usr/local' >&2
      exit 1
    fi
  fi
done < <(find "$APP" -type f)

sign() {
  local args=(--force --options runtime --timestamp --sign "$IDENTITY")
  [[ -n ${ENTITLEMENTS:-} ]] && args+=(--entitlements "$ENTITLEMENTS")
  codesign "${args[@]}" "$1"
}

# Inner code first: the app's seal covers it as it is. No --deep when signing.
for rel in $INNER; do
  sign "$APP/$rel"
done
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# A fresh staging directory each run, so a stale file cannot end up in the image.
STAGE=$(mktemp -d "$OUT/dmg-stage.XXXXXX")
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ -z ${SKIP_NOTARY:-} ]]; then
  : "${NOTARY_PROFILE:?set NOTARY_PROFILE (xcrun notarytool store-credentials) or SKIP_NOTARY=1}"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -vv -t open --context context:primary-signature "$DMG"
  spctl -a -vv -t exec "$STAGE/$(basename "$APP")"
fi

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo
echo "$DMG"
echo "version $VERSION  sha256 $SHA  $(du -h "$DMG" | cut -f1)"
echo "staging dir (safe to delete): $STAGE"
echo "publish (not run):"
echo "  gh release create v$VERSION '$DMG' ${REPO:+--repo $REPO }--title '$VOLNAME $VERSION'"
echo "  then bump Casks/${CASK:-<name>}.rb in your tap: version \"$VERSION\", sha256 \"$SHA\""
