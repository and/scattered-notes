#!/bin/bash
# Builds the signed Android releases:
#   build/release-android/ScatteredNotes-<version>-android.apk  attached to the GitHub release; updates itself from GitHub
#   build/release-android/ScatteredNotes-<version>-play.aab     uploaded to Google Play, which updates it
#
# Both are signed with the same key, so a phone can move between them. The key is outside the repo,
# in ~/.config/scattered-notes/android-release.jks, and its password is in the keychain (service
# scattered-notes-android-keystore). Keep a backup of both: without the key, no update can be
# installed over an existing install.
set -euo pipefail
cd "$(dirname "$0")/.."

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}"
export SN_ANDROID_KEYSTORE="${SN_ANDROID_KEYSTORE:-$HOME/.config/scattered-notes/android-release.jks}"
SN_ANDROID_KEYSTORE_PASSWORD="$(security find-generic-password -s scattered-notes-android-keystore -w)"
export SN_ANDROID_KEYSTORE_PASSWORD
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
APKSIGNER="$(ls -d "$SDK"/build-tools/*/apksigner | sort -V | tail -1)"

VERSION=$(sed -n 's/.*versionName = "\(.*\)"/\1/p' android/app/build.gradle.kts)
OUT="build/release-android"
rm -rf "$OUT"
mkdir -p "$OUT"

(cd android && ./gradlew -q clean testGithubReleaseUnitTest assembleGithubRelease bundlePlayRelease)

cp android/app/build/outputs/apk/github/release/app-github-release.apk "$OUT/ScatteredNotes-$VERSION-android.apk"
cp android/app/build/outputs/bundle/playRelease/app-play-release.aab "$OUT/ScatteredNotes-$VERSION-play.aab"

"$APKSIGNER" verify --print-certs "$OUT/ScatteredNotes-$VERSION-android.apk" | grep "SHA-256"
"$JAVA_HOME/bin/jarsigner" -verify "$OUT/ScatteredNotes-$VERSION-play.aab" | head -1

echo "Android releases: $OUT"
