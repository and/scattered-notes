# Scattered Notes for Windows 11: plan

The goal is a Windows 11 app with the same features as the Mac app, working on the same notes folder.
A person with a Mac and a PC can sync the folder with iCloud for Windows or OneDrive and use both
apps on it.

## Stack

**C# on .NET 10 with Avalonia 12, its Fluent theme, and Fluent System Icons.**

- .NET 10 is the current long-term support release (supported to November 2028). .NET 8 support ends
  on 10 November 2026, so it is not used.
- Avalonia builds and runs on macOS as well as Windows. The whole app can be developed, run and tested
  on the Mac, and `dotnet publish -r win-x64` produces the Windows build from the Mac.
- Avalonia's Fluent theme gives the Windows 11 look, and FluentIcons.Avalonia gives the Windows 11 icon set
  on every platform. On Windows 11 the windows use the Mica backdrop. FluentAvalonia was dropped: the
  sidebar is a plain list styled like `NavigationView`, which keeps one less dependency.
- Win32 APIs that only matter on Windows (`RegisterHotKey`, start at login) sit behind small interfaces,
  with a Windows implementation and a no-op or Mac implementation for development.

The Windows-only parts are checked in the Parallels Windows 11 VM and in GitHub Actions on
`windows-latest`.

## Repository layout

The Windows app lives in the same repo, so a format change lands for both apps in one commit.

```
windows/
  ScatteredNotes.Windows.sln
  src/
    ScatteredNotes.Core/        class library, no UI
      Models/                   Note, Frontmatter, ProjectArea, AgendaItem
      Agenda/                   AgendaExtractor, AgendaLog
      Search/                   NoteSearch
      Storage/                  NoteStore, AtomicFile, FileNames, AppSettings
    ScatteredNotes.App/         Avalonia app
      Views/                    Shell, Dashboard, NoteList, Editor, AgendaColumn, Search, Settings
      QuickCapture/             Quick Capture window
      Platform/                 HotKeys, StartAtLogin, Backdrop (Windows and fallback versions)
  tests/
    ScatteredNotes.Core.Tests/  xUnit
fixtures/                       note files and expected results shared by both test suites
```

## File format contract

Both apps must read and write exactly the same files. These rules come from the Mac code and do not
change:

- Notes are UTF-8 Markdown files with YAML frontmatter, under `Inbox/`, `Projects/<name>/` and
  `Areas/<name>/`.
- Frontmatter keys, in order: `id`, `title` (quoted, escaped), `type`, `target` (quoted, optional),
  `created_at`, `updated_at`, `pinned` (only when true), `tags` (only when present).
- `id` is an uppercase UUID (Swift's `uuidString`). C# `Guid.ToString()` is lowercase, so the Windows app
  writes `ToString().ToUpperInvariant()` and reads IDs case-insensitively.
- Dates are ISO 8601. Reading accepts both with and without fractional seconds, like the Mac app.
- The body after the frontmatter is preserved byte for byte.
- File names are `yyyy-MM-dd_<title>.md`, with a 6-character ID suffix on a clash.
- `.metadata.json` in each project and area folder holds its icon.
- `.agenda-log.json` at the root: `notes -> <note id> -> <line key> -> { line, firstSeen }`. `firstSeen`
  is ISO 8601 in UTC without fractional seconds (`2026-10-27T06:55:00Z`).

Windows-specific rules:

- **Line endings.** Read both `\n` and `\r\n`. Keep the line ending a file already uses. New files use
  `\n`, like the Mac.
- **BOM.** Accept a UTF-8 BOM on read. Never write one.
- **File names.** Besides the characters the Mac already strips, remove trailing dots and spaces and
  avoid the reserved names `CON`, `PRN`, `AUX`, `NUL`, `COM1`-`COM9` and `LPT1`-`LPT9`.

Shared fixtures in `fixtures/` (sample notes plus expected parse results) are loaded by both the XCTest
and xUnit suites, so the two parsers cannot drift apart.

## Feature mapping

| Mac | Windows 11 |
|---|---|
| Menu bar app | Notification area (tray) icon via Avalonia `TrayIcon`; closing the main window hides it |
| `⌥ N` Quick Capture, `⌥ F` Search (Carbon hot keys) | `RegisterHotKey`. Defaults `Ctrl+Alt+N` and `Ctrl+Alt+F`, changeable in Settings. `Alt+F` is not used because it opens the File menu in most Windows apps |
| Quick Capture floating panel | Borderless, topmost window, centered on the active screen, takes focus on the hot key |
| `NavigationSplitView` sidebar, list, editor | Sidebar list with Dashboard, All Notes, Inbox, Projects, Areas; list and editor columns |
| Dashboard | Same sections and counters; rows complete on click |
| Agenda column in the editor | Right-hand pane, toggled from the editor toolbar |
| Markdown preview with clickable checkboxes | Markdig parse to Avalonia controls written for the app, so checkboxes stay clickable |
| Search palette (`⌘ K`) | `Ctrl+K` dialog, same ranking and snippets |
| `Esc`: tab to Dashboard, Dashboard hides window | Same, via a window-level key handler |
| `Enter` on a note focuses the editor at the searched word | Same, using `TextBox.CaretIndex` |
| Launch at login | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` entry, switch in Settings |
| `UserDefaults` | `%APPDATA%\ScatteredNotes\settings.json` |
| Default folder `~/Documents/ScatteredNotes` | `Documents\ScatteredNotes`. If `%USERPROFILE%\iCloudDrive` exists, the first run offers it |
| WCAG selection colours | Same values (`#1D4ED8` light, `#1E40AF` dark) |

## Data safety on Windows

The Mac rules carry over, plus Windows behaviours:

- **Atomic save.** Write to a temp file in the same folder, flush it to disk, then
  `File.Move(overwrite: true)`. A note that moves is written to its new path before the old file is
  removed.
- **Locked files.** OneDrive, iCloud and antivirus tools briefly lock files. Retry sharing violations with
  back-off. If the retries fail, keep the edit in memory and show a warning; never drop it.
- **Watcher.** `FileSystemWatcher` with debounce. Skip events caused by the app's own writes.
- **Quit and shutdown.** Flush pending edits on window close, app exit, and Windows shutdown or sign-out.
- **Sync conflicts.** Both machines can rewrite `.agenda-log.json`. On load, merge the main file with any
  conflict copies and keep the earliest `firstSeen` for each line. Do the same on the Mac.

Port the Mac `DataSafetyTests` (round-trip fuzz, crash mid-save, duplicate IDs, moved notes) to xUnit,
and add tests for CRLF files, BOM files, reserved names and locked files.

## Phases

Each phase ends with passing tests and a commit.

**0. Setup**
- Install the .NET 10 SDK on the Mac.
- Create the solution, projects and test project. Add a GitHub Actions workflow that builds and tests on
  `windows-latest`.
- Repair the Parallels "Windows 11" VM, which `prlctl` reports as `invalid`, for hands-on testing.

**1. Core library**
- Port `Note` with frontmatter split, escaping and serialisation, plus `AgendaExtractor` with every date
  phrase, `AgendaLog`, `NoteSearch` and the store (load, dedupe, save, move, delete, projects, areas).
- Port the Mac tests to xUnit, and add the shared fixtures and the Windows-specific tests above.
- Done when the core reads the real iCloud notes folder (read-only) and produces the same agenda as
  the Mac app.

**2. Main window**
- Build the `NavigationView` shell, note list with sort and filter, editor with autosave, destination menu,
  pin, delete, reveal in Explorer, and status bar.

**3. Dashboard and agenda**
- Build the dashboard sections and counters, completing items, the agenda column in the editor, and the
  Markdown preview with clickable checkboxes.

**4. Background app**
- Add the tray icon and menu, Quick Capture window, global hot keys (with clash reporting), start at
  login, and close-to-tray.

**5. Search and keyboard**
- Add the search palette, `Ctrl+K`, the global search hot key, `Esc` rules, and `Enter` to focus the
  editor at the searched word.

**6. Settings and polish**
- Add the Settings page (folder, font size, shortcuts recorder, start at login), Mica, dark and light
  themes, Narrator names, and keyboard focus order.

**7. Release**
- Make self-contained single-file builds for `win-x64` and `win-arm64`. Parallels on Apple silicon runs
  Windows on ARM, so `arm64` is needed for testing too.
- Ship a zip, and later an installer. Add a release script, a GitHub release, and a "Windows" section in
  the README.

## Signing and distribution

Unsigned apps show a SmartScreen warning. Options:

1. **Microsoft Store.** Microsoft signs the MSIX, so there is no warning, and updates are automatic.
   Registration is free for individual developers (to confirm when registering).
2. **Azure Trusted Signing.** A monthly-fee signing certificate for GitHub release builds. Availability
   for individuals depends on country, which needs checking for India.
3. **Unsigned zip on GitHub** for the first release, with install notes explaining the SmartScreen
   "More info, Run anyway" step.

Proposal: start with option 3 for early testing, then publish through the Store.

## Changes needed in the Mac app

- Apply the Windows file name rules (trailing dots, reserved names) when creating notes, and sanitise
  project and area folder names. A folder such as `Work: 2026` cannot exist on Windows, so it would
  not sync.
- Merge `.agenda-log.json` conflict copies on load.
- Load the shared fixtures in the XCTest suite.

## Out of scope for the first version

- Windows 10.
- Clickable dashboard counters (in `BACKLOG.md`; build them on both platforms together).
- Auto-update outside the Store.

## Status (27 October 2026)

- Phases 0 to 6 are written. `windows/` builds on the Mac, and `dotnet test` passes 69 tests.
- Loading a copy of the real iCloud notes folder leaves every note file and `.agenda-log.json` byte for
  byte unchanged, so the formats match.
- The app runs on macOS for development: `dotnet run --project windows/src/ScatteredNotes.App --
  --settings <file> --notes-folder <folder>` uses test data instead of the real notes.
- `dotnet publish -r win-x64` and `-r win-arm64` produce single-file `ScatteredNotes.exe` builds from the Mac.
- Not yet checked on Windows: global hot keys, tray icon, Mica, single instance, start at sign-in, and
  locked-file retries. These need the Parallels VM or the GitHub Actions build.

## Mac app bugs found while porting

- `Note.splitFrontmatter` compares the delimiter line with `\r` still on it, so a note saved with Windows
  line endings loses its frontmatter on the Mac: the whole file shows as the body.
- `togglingChecklistLine` splits on `.newlines` and joins with `\n`, so ticking an item in a `\r\n` file
  turns every line break into a blank line.
