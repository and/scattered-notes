#!/bin/bash
# Archives the iPhone and iPad app and uploads it to App Store Connect, where it appears in TestFlight
# after Apple has processed it (usually 10 to 30 minutes).
#
# Xcode signs it with an Apple Distribution certificate and profile, created on its own
# (-allowProvisioningUpdates) while Xcode is signed in to the team's Apple account. The app must
# already exist in App Store Connect with the bundle ID com.scatterednotes.ios.
#
# Usage: scripts/release-ios.sh                 (archive and upload)
#        SKIP_UPLOAD=1 scripts/release-ios.sh   (archive and export an .ipa only)
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM="${TEAM_ID:-RLVYQT69D4}"
OUT="build/release-ios"
ARCHIVE="$OUT/ScatteredNotesiOS.xcarchive"
rm -rf "$OUT"
mkdir -p "$OUT"

(cd ios && xcodegen -q)
xcodebuild archive \
    -project ios/ScatteredNotesiOS.xcodeproj -scheme ScatteredNotesiOS \
    -configuration Release -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" \
    | tail -3

DESTINATION=upload
[ -n "${SKIP_UPLOAD:-}" ] && DESTINATION=export
cat > "$OUT/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$DESTINATION</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM</string>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/export.plist" -allowProvisioningUpdates | tail -3
