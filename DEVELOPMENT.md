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

## Tests

```bash
# Full suite (unit and end-to-end)
make test

# Only the end-to-end feature tests
make e2e-test
```

The suite covers the agenda parser and log, search, note file round trips and crash leftovers (`DataSafetyTests`), shortcut handling and the storage layer. Tests use a temporary notes folder and an isolated `UserDefaults` suite, so they never touch your real notes.

## Project layout

| Folder | Contents |
| :--- | :--- |
| `Sources/App` | App entry point, app delegate, window routing, Esc handling, accessible color theme |
| `Sources/HotKey` | Global hot keys (Carbon) and the shortcut model |
| `Sources/Models` | `Note`, the agenda parser (`Agenda.swift`) and note search |
| `Sources/QuickCapture` | The floating Quick Capture panel |
| `Sources/Storage` | Reading and writing notes, settings, the agenda log |
| `Sources/Views` | Dashboard, editor, note list, search palette, settings, sidebar, menu bar |
| `Tests/ScatteredNotesTests` | Unit and end-to-end tests |
| `scripts` | Release script and app icon generator |

## Data safety rules

Notes are the user's data, so these hold for any change to storage:

- Note files are written atomically, and a moved note's new file is written before the old one is removed.
- Loading never rewrites a note file.
- The agenda log (`.agenda-log.json`) is derived data. Losing or corrupting it must never affect notes.

## Releasing

`scripts/release.sh` builds a universal (Apple silicon and Intel) Release app, signs it with a Developer ID certificate, notarizes it with Apple, staples the ticket, and writes `build/release/ScatteredNotes-<version>.zip`.

One-time setup. Run this in a normal Terminal window, not through a tool that records commands, and leave off `--password` so you are prompted for the app-specific password with hidden input:

```bash
xcrun notarytool store-credentials scattered-notes-notary \
    --apple-id <apple id> --team-id <team id>
```

Release steps:

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/App/Info.plist` and `project.yml`.
2. Run `make test`.
3. Commit and push.
4. Run `scripts/release.sh`. Use `SKIP_NOTARIZE=1 scripts/release.sh` to sign only.
5. Tag and publish:

   ```bash
   git tag -a vX.Y.Z -m "Scattered Notes X.Y.Z"
   git push origin vX.Y.Z
   gh release create vX.Y.Z build/release/ScatteredNotes-X.Y.Z.zip --title "Scattered Notes X.Y.Z" --notes "..."
   ```

The script's environment variables: `SIGN_IDENTITY` (default `Developer ID Application`), `TEAM_ID`, `NOTARY_PROFILE` (default `scattered-notes-notary`) and `SKIP_NOTARIZE`.
