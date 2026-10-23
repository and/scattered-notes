# Scattered Notes (macOS)

A high-performance, native macOS quick note-taking app designed for rapid capture and structured organization under **Projects** and **Areas**. Stored as transparent Markdown files on disk.

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-green)

<p align="center">
  <img src="docs/quick-capture.png" alt="Scattered Notes Quick Capture HUD" width="680" />
</p>

---

## Features

- ⚡️ **Global Quick Capture (⌥ + N)**:
  - Floating Spotlight/Raycast-style HUD modal accessible from anywhere across macOS.
  - Auto-focused multiline editor.
  - Instant project/destination selector (capture directly to `Inbox` or pick an active `Project`/`Area`).
  - Inline `#tag` extraction.
  - Press `⌘ + Enter` to save & auto-dismiss.
  - Press `Esc` to cancel.
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
| `⌥ + N` | Trigger Floating Quick Capture HUD |
| `⌘ + ↵` | Save note in Quick Capture |
| `Esc` | Dismiss Quick Capture |
| `⌘ + N` | New Note in current project/inbox (Main Window) |
| `⌘ + Q` | Quit application |
