# Development

Everything you need to build, test and release Scattered Notes. For what the app does and how to install it, see the [README](README.md). Planned work is in [BACKLOG.md](BACKLOG.md).

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), only if you change `project.yml`

## Build and run

```bash
# Build the native app bundle into ./build/DerivedData
make build

# Launch it
make run
```

Or open the project in Xcode:

```bash
open ScatteredNotes.xcodeproj
```

The Xcode project is generated from `project.yml`. After adding, removing or renaming source files, regenerate it:

```bash
make project    # runs xcodegen generate
```

### iCloud Drive folder

The Mac and iOS apps share an iCloud container, `iCloud.com.scatterednotes`, which shows up as **Scattered Notes** in iCloud Drive (`NSUbiquitousContainers` in both Info.plists). `ICloudFolder` finds it, and `NoteStorageManager` follows it with an `NSMetadataQuery`. That query reports notes changed on other devices and downloads notes that are only in the cloud. Writes go through `NSFileCoordinator`.

Only signed builds carry the iCloud entitlement. `make build` and the tests are unsigned, so they never see the container and the "Use iCloud Drive" button says iCloud isn't available. `scripts/release.sh` adds `Sources/App/ScatteredNotes.entitlements`; the iOS target has it in `ios/project.yml`. In the Apple Developer website, the App IDs `com.scatterednotes.app` and `com.scatterednotes.ios` must have iCloud on, with the container `iCloud.com.scatterednotes` ticked.

## Tests

```bash
# Full suite (unit and end-to-end)
make test

# Only the end-to-end feature tests
make e2e-test
```

The suite covers the agenda parser and log, search, note file round trips and crash leftovers (`DataSafetyTests`), shortcut handling and the storage layer. Tests use a temporary notes folder and an isolated `UserDefaults` suite, so they never touch your real notes.

```bash
# Screen tests: start the app and use it with the mouse and keyboard
make ui-test
```

The screen tests (`UITests`) go through Quick Note, the editor and the dashboard as a person would. They start the app with `-uiTesting` and an empty notes folder of their own (`SN_UITEST_NOTES`), so it never sees real notes, iCloud or update checks. Debug builds use the app ID `com.scatterednotes.app.debug`, so their settings are separate from the installed app's. Run them before each release; they take about a minute, and the Mac can't be used meanwhile.

## Project layout

| Folder | Contents |
| :--- | :--- |
| `Sources/App` | App entry point, app delegate, window routing, Esc handling, accessible color theme |
| `Sources/HotKey` | Global hot keys (Carbon) and the shortcut model |
| `Sources/Models` | `Note`, the agenda parser (`Agenda.swift`) and note search |
| `Sources/QuickCapture` | The floating Quick Capture panel |
| `Sources/Storage` | Reading and writing notes and settings |
| `Sources/Views` | Dashboard, editor, note list, search palette, settings, sidebar, menu bar |
| `Tests/ScatteredNotesTests` | Unit and end-to-end tests |
| `scripts` | Release script and app icon generator |
| `ios` | iPhone and iPad app (SwiftUI), sharing `Sources/Models` and `Sources/Storage` |
| `android` | Android app (Kotlin, Jetpack Compose) |
| `windows` | Windows app (.NET, Avalonia) |

## iPhone and iPad app

The iOS app lives in `ios/`. It compiles the Mac app's `Sources/Models` and `Sources/Storage` (except the FSEvents `FolderWatcher`) into its own target, so notes, the agenda parser, the dashboard rules and storage are the same code on both. Mac-only parts of those files are behind `#if os(macOS)`. Its module is also named `ScatteredNotes`, so the shared `AgendaTests` and `NoteSearchTests` run on iOS unchanged.

```bash
cd ios
xcodegen generate                 # after adding or removing files
open ScatteredNotesiOS.xcodeproj  # run on a simulator or your device

# Tests on a simulator
xcodebuild test -project ScatteredNotesiOS.xcodeproj -scheme ScatteredNotesiOS \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

The tests include screen tests (`ios/UITests`) that tap through the Notes screens on a simulator. The app started with `-uiTesting` uses an empty folder of its own, so they never touch real notes.

Running on a device signs with the team in `ios/project.yml`. The icon is drawn by the Mac icon script without the squircle, then flattened because the App Store rejects icons with an alpha channel:

```bash
swift scripts/generate_icon.swift --ios ios/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png
sips -s format jpeg icon_1024.png --out /tmp/icon.jpg && sips -s format png /tmp/icon.jpg --out icon_1024.png
```

## Android app

The Android app lives in `android/`: Kotlin and Jetpack Compose. `core/` is a port of the Windows `ScatteredNotes.Core` logic (note format, agenda,  dashboard, search, file names) and must follow the same rules; when you change the agenda rules on Mac and Windows, change `AgendaExtractor.kt` too. `storage/` reads the notes folder either in the app's private storage or in a folder picked with the system folder picker (Storage Access Framework).

Requirements: JDK 17 or 21 (Gradle 8.14 does not run on newer JDKs) and the Android SDK with platform 36.

```bash
cd android
export JAVA_HOME=$(/usr/libexec/java_home -v 21)   # or /opt/homebrew/opt/openjdk@21
./gradlew testGithubDebugUnitTest   # core logic tests
./gradlew installGithubDebug        # build and install on a running emulator or device
```

There are two builds (product flavors) with the same app ID:

| Flavor | Published as | Updates |
| :--- | :--- | :--- |
| `github` | `ScatteredNotes-<version>-android.apk` on the GitHub release | Checks GitHub once a day (`update/Updater.kt`), downloads the APK and installs it through Android's `PackageInstaller`, after the user confirms |
| `play` | `ScatteredNotes-<version>-play.aab`, uploaded to Google Play | By Google Play. It has no updater, internet permission or install permission, since Play doesn't allow apps to update themselves |

`scripts/release-android.sh` builds both, signed with the same release key, so a phone can move from one to the other. The key is `~/.config/scattered-notes/android-release.jks`. Its password is in the keychain, under the service `scattered-notes-android-keystore`. Keep a backup of both somewhere safe: without the key, no update can be installed over an existing install.

In Google Play, Play App Signing has to use this same key, not a key Google generates; otherwise the Play build and the GitHub APK can't update each other. When creating the app, choose to export and upload your own key from a Java keystore and follow the Play Console's PEPK steps with the keystore above.

Debug builds are signed with the Android debug key, so a release can't be installed over them. Uninstall a debug build first.

The launcher icon is `generate_icon.swift --android`, scaled into the `mipmap-*` folders.

## Data safety rules

Notes are the user's data, so these hold for any change to storage:

- Note files are written atomically, and a moved note's new file is written before the old one is removed.
- Loading never rewrites a note file.
- Frontmatter properties the app does not know must survive a save unchanged (`extraFrontmatter` / `ExtraFrontmatter`), so notes edited in Obsidian lose nothing. All four ports keep them in the same order, after the app's own fields.
- The agenda markers (`📅 2026-10-28` for the day a line refers to, `✅ 2026-10-28` for the day it was ticked, the Obsidian Tasks format) live in the line itself. `AgendaExtractor.resolvingDates` / `ResolvingDates` / `resolvingDates` writes them, only when a note is saved, never when it is loaded, and only on lines whose date comes from a relative word or that are ticked. A marker always wins over the words next to it. The three ports must write the same text for the same input.

## Releasing

`scripts/release.sh` archives a universal (Apple silicon and Intel) Release app and exports it signed with a Developer ID certificate and provisioning profile. It then notarizes it with Apple, staples the ticket, and writes `build/release/ScatteredNotes-<version>-mac.zip`. The profile is needed for the iCloud entitlement. Xcode creates and renews it on its own, as long as Xcode is signed in to the team's Apple account (Xcode → Settings → Accounts).

One-time setup. Run this in a normal Terminal window, not through a tool that records commands, and leave off `--password` so you are prompted for the app-specific password with hidden input:

```bash
xcrun notarytool store-credentials scattered-notes-notary \
    --apple-id <apple id> --team-id <team id>
```

Release steps. All apps share one version number; the build number (`CFBundleVersion`, Android `versionCode`) goes up by one each release.

1. Bump the version and build number in:
   - `Sources/App/Info.plist` and `project.yml` (Mac)
   - `ios/project.yml` (iPhone and iPad)
   - `android/app/build.gradle.kts` (`versionName`, `versionCode`)
   - `windows/Directory.Build.props` and `windows/src/ScatteredNotes.App/app.manifest`
2. Run `make test`.
3. Commit and push.
4. Build:
   - `scripts/release.sh` (Mac). Use `SKIP_NOTARIZE=1 scripts/release.sh` to sign only.
   - `scripts/release-android.sh` (Android APK and Play bundle)
   - `cd windows && dotnet publish src/ScatteredNotes.App -c Release -r win-x64 -o <dir>`, then rename `ScatteredNotes.exe` to `ScatteredNotes-X.Y.Z-windows.exe`
5. Tag and publish on GitHub:

   ```bash
   git tag -a vX.Y.Z -m "Scattered Notes X.Y.Z"
   git push origin vX.Y.Z
   gh release create vX.Y.Z build/release/ScatteredNotes-X.Y.Z-mac.zip \
       build/release-android/ScatteredNotes-X.Y.Z-android.apk <windows exe> \
       --title "Scattered Notes X.Y.Z" --notes-file <notes>
   ```

6. Run `scripts/release-ios.sh` to upload the iPhone and iPad app to TestFlight.
7. Upload `build/release-android/ScatteredNotes-X.Y.Z-play.aab` in the Play Console (Test and release), with the same notes.

The script's environment variables: `TEAM_ID` (default `RLVYQT69D4`), `NOTARY_PROFILE` (default `scattered-notes-notary`) and `SKIP_NOTARIZE`.
