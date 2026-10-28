#!/bin/bash
# Builds a universal Release app, signs it with a Developer ID certificate, notarizes it with Apple
# and writes build/release/ScatteredNotes-<version>-mac.zip, ready to attach to a GitHub release.
#
# The release carries the iCloud entitlement (Sources/App/ScatteredNotes.entitlements), which needs a
# Developer ID provisioning profile. Xcode creates and renews it on its own (-allowProvisioningUpdates),
# as long as Xcode is signed in to the team's Apple account and the App ID com.scatterednotes.app
# has iCloud on with the container iCloud.com.scatterednotes in the Apple Developer website.
#
# One-time setup for notarization (stores credentials in your keychain, nothing in the repo):
#   xcrun notarytool store-credentials scattered-notes-notary \
#       --apple-id <apple id> --team-id <team id> --password <app-specific password>
#
# Usage: scripts/release.sh                (sign, notarize, staple)
#        SKIP_NOTARIZE=1 scripts/release.sh (sign only; macOS shows a warning on first open)
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM="${TEAM_ID:-RLVYQT69D4}"
PROFILE="${NOTARY_PROFILE:-scattered-notes-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Sources/App/Info.plist)
OUT="build/release"
ARCHIVE="$OUT/ScatteredNotes.xcarchive"
APP="$OUT/export/ScatteredNotes.app"
ZIP="$OUT/ScatteredNotes-$VERSION-mac.zip"

rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild archive \
    -project ScatteredNotes.xcodeproj -scheme ScatteredNotes \
    -configuration Release -derivedDataPath "$OUT/DerivedData" -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_ENTITLEMENTS=Sources/App/ScatteredNotes.entitlements ENABLE_HARDENED_RUNTIME=YES \
    | tail -3

# Re-signs the archived app with the Developer ID certificate and profile
cat > "$OUT/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/export.plist" -allowProvisioningUpdates | tail -3

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "iCloud.com.scatterednotes" \
    || { echo "The app is missing the iCloud entitlement" >&2; exit 1; }
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
