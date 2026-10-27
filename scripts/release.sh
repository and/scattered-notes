#!/bin/bash
# Builds a universal Release app, signs it with a Developer ID certificate, notarizes it with Apple
# and writes build/release/ScatteredNotes-<version>-mac.zip, ready to attach to a GitHub release.
#
# One-time setup for notarization (stores credentials in your keychain, nothing in the repo):
#   xcrun notarytool store-credentials scattered-notes-notary \
#       --apple-id <apple id> --team-id <team id> --password <app-specific password>
#
# Usage: scripts/release.sh                (sign, notarize, staple)
#        SKIP_NOTARIZE=1 scripts/release.sh (sign only; macOS shows a warning on first open)
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
TEAM="${TEAM_ID:-RLVYQT69D4}"
PROFILE="${NOTARY_PROFILE:-scattered-notes-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Sources/App/Info.plist)
OUT="build/release"
APP="$OUT/DerivedData/Build/Products/Release/ScatteredNotes.app"
ZIP="$OUT/ScatteredNotes-$VERSION-mac.zip"

rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild build \
    -project ScatteredNotes.xcodeproj -scheme ScatteredNotes \
    -configuration Release -derivedDataPath "$OUT/DerivedData" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp" \
    | tail -3

codesign --verify --deep --strict --verbose=2 "$APP"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/ScatteredNotes")"

ditto -c -k --keepParent "$APP" "$ZIP"

if [ -z "${SKIP_NOTARIZE:-}" ]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    spctl --assess --type execute --verbose "$APP"
fi

echo "Release archive: $ZIP"
