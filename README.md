# Scattered Notes (macOS)

A high-performance, native macOS quick note-taking app designed for rapid capture and structured organization under **Projects** and **Areas**. Stored as transparent Markdown files on disk.

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-green)

<p align="center">
  <img src="docs/quick-capture.png" alt="Scattered Notes Quick Capture HUD" width="680" />
</p>

<p align="center">
  <img src="docs/dashboard.png" alt="Scattered Notes Dashboard showing overdue, today and upcoming items" width="820" />
</p>

---

## Download

Get the latest signed and notarized build from the [Releases page](https://github.com/and/scattered-notes/releases/latest):

1. Download the `ScatteredNotes-<version>.zip` file and unzip it.
2. Drag **ScatteredNotes.app** into your Applications folder and open it.

Requires macOS 14 (Sonoma) or later. Runs on Apple silicon and Intel Macs.

---

## Features

- ⚡️ **Global Quick Capture (⌥ + N)**:
  - Floating Spotlight/Raycast-style HUD modal accessible from anywhere across macOS.
  - Auto-focused multiline editor.
  - Instant project/destination selector (capture directly to `Inbox` or pick an active `Project`/`Area`).
  - Inline `#tag` extraction.
  - Press `⌘ + Enter` to save & auto-dismiss.
  - Press `Esc` to cancel.
- 🗓️ **Dashboard**: your notes' to-dos and plans on one page (see [Dashboard](#dashboard)).
  - Overdue, Today, Next 14 Days and open to-dos, collected from every note.
  - Counters for overdue, today, upcoming and open to-dos.
  - Tick any item off from the dashboard or from the note's agenda column.
- 🔎 **Global Search (⌘ + K or ⌥ + F)**: Spotlight-style palette over all notes with ranked results and highlighted snippets. `⌥ + F` works from any app.
- 📂 **Full 3-Pane View**:
  - **Sidebar**: Quick access to *Inbox*, *All Notes*, *Projects*, and *Areas* with live badge counts and inline creation.
  - **Notes List**: Full-text instant search across titles, contents, and `#tags`. Sort by modified date, creation date, or title.
  - **Markdown Editor**: Syntax highlighting, split view, and live preview.
  - **Interactive Checklists**: Click `- [ ]` checkboxes in live preview or split view to check them off directly.
- 💾 **Local & Open Storage**:
  - Notes are saved as plain `.md` files under `~/Documents/ScatteredNotes/`:
    - `Inbox/`
    - `Projects/<ProjectName>/`
    - `Areas/<AreaName>/`
  - YAML frontmatter maintains metadata (`id`, `title`, `type`, `target`, `tags`, `pinned`).
  - Live directory file watching automatically synchronizes external modifications (e.g. from Obsidian, Finder, or Git).
- 🏷️ **Menu Bar Companion**:
  - Native menu bar status item for instant capture, opening the main window, and accessing recent notes.

---

## Dashboard

The Dashboard is the app's home view: today's date, four live counters (**overdue**, **today**, **upcoming**, **open to-dos**) and a plain list of everything you've written that needs doing, gathered from all your notes in one place. Each item shows which note it came from; click the note name to jump straight to it. Nothing to set up: write a to-do or a day in any note and it shows up here.

It reads every note and lists the lines that need action:

- **Checklist items**: `- [ ] Renew passport`
- **Dated or relative lines**: any line that mentions a day, even without a checkbox.

| Writes like | Means |
| :--- | :--- |
| `@2026-10-30`, `2026-10-30` | that date |
| `today`, `tonight`, `tomorrow` | day written, or the next day |
| `day after tomorrow`, `in 3 days`, `in 2 weeks` | counted from the day written |
| `the day after` | one day after the closest dated line above it |
| `friday`, `next friday` | next such weekday |
| `next week` | 7 days after the day written |
| `oct 30`, `30 October`, `Oct 30th` | that date (next year if it already passed by more than six months) |

**Relative words use the day you wrote the line**, not the day the note was created or last opened. The app records when each line first appeared in a hidden `.agenda-log.json` at the root of your notes folder, so editing a note later never moves earlier lines. The log is derived data; deleting it is safe, and older relative lines then fall back to the note's creation date.

**Completing items**: click the circle next to an item on the dashboard or in the note's agenda column (right margin of the editor, toggled with the sidebar button). Completing a plain dated line turns it into a checked item (`- [x] ...`) in the note.

---

## Quick Start

### Build & Run
```bash
# Build the native app bundle
make build

# Launch the app
make run
```

### Run Tests
```bash
# Run the complete test suite (Unit & E2E)
make test

# Run specifically the End-to-End Feature Test Suite
make e2e-test
```

### Open in Xcode
```bash
open ScatteredNotes.xcodeproj
```

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌥ + N` | Trigger Floating Quick Capture HUD (any app) |
| `⌥ + F` | Search all notes (any app) |
| `⌘ + K` | Search all notes (inside the app) |
| `⌘ + ↵` | Save note in Quick Capture |
| `Esc` | Dismiss Quick Capture; in the main window go back to the Dashboard, then hide the window |
| `↵` | On a selected note, start editing it (cursor after the searched word when opened from a search) |
| `⌘ + N` | New Note in current project/inbox (Main Window) |
| `⌘ + Q` | Quit application |

Both global shortcuts can be changed in **Settings → Global Shortcuts**.
