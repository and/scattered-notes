# Memory Efficiency Audit & Optimization Plan

This document details the memory and allocation bottlenecks in **Scattered Notes** (macOS Swift/SwiftUI and Windows C#/Avalonia) and how to resolve them.

**Status (29 October 2026):** items 3 and 4 are fixed and items 1, 2, 5, 7 and 8.4 are partly fixed. Item 6 and the disk cache in 8.3 are left open on purpose; measure cold start with a generated 10,000-note vault before building the cache. Details are under each item.

---

## 1. Full Note Bodies Retained in RAM Permanently

> **Status: partly fixed on macOS** (`bc7e424`). `loadAll()` now keeps each parsed note with its file's modification date and size, and re-reads only files where either changed. The file watcher was also replaced: it watched only the root folder, so edits inside `Inbox/`, `Projects/` and `Areas/` (including notes synced from another device) were missed. `FolderWatcher` now uses FSEvents over the whole tree. Windows now has the same `(mtime, size)` file cache. Still open: note bodies stay in memory. Loading `content` on demand is not planned, because the dashboard and search need every note's text.

**Where**
- macOS: `Sources/Models/Note.swift`, `Sources/Storage/NoteStorageManager.swift` (`loadAll()`)
- Windows: `windows/src/ScatteredNotes.Core/Storage/NoteStore.cs` (`LoadAll()`)

**Problem**
- `NoteStorageManager.notes` (and `NoteStore.Notes`) holds the full `content: String` of every `.md` file in memory at all times.
- When a note is open in `NoteDetailEditorView`, its body string is duplicated across:
  1. `NoteStorageManager.shared.notes`
  2. `NoteDetailEditorView.note.content`
  3. `@State private var editableContent`
  4. AppKit's `NSTextStorage` backing `TextEditor`
- On macOS, `fileWatcherSource` calls `loadAll()` on any filesystem event in the root directory, re-reading and re-parsing every note file from disk even when only one file changed.

**Fix**
- Track `(fileURL, contentModificationDate)` per note so `loadAll()` only re-reads files whose modification timestamp changed.
- Keep lightweight metadata (`id`, `title`, `previewExcerpt`, `checklistStats`, `tags`, `filePath`, `createdAt`, `updatedAt`, `isPinned`) in memory for list and sidebar rendering, and load `content` on demand for the active editor or full-text search.

---

## 2. Repeated Full-Body String Splitting on View Renders & Keystrokes

> **Status: partly fixed.** The word count is now a single scalar scan (`NoteDetailEditorView.wordCount(in:)`). Open: storing `displayTitle`, `previewExcerpt` and `checklistStats` on `Note`.

**Where**
- macOS: `Sources/Models/Note.swift` (`displayTitle`, `previewExcerpt`, `checklistStats`), `Sources/Views/NoteList/NoteListView.swift` (`NoteCardRow`), `Sources/Views/Editor/NoteDetailEditorView.swift`

**Problem**
- `displayTitle`, `previewExcerpt`, and `checklistStats` are computed properties that each call `content.components(separatedBy: .newlines)`, bridging to `NSString` and allocating a heap `[String]` array for every line in the note.
- `previewExcerpt` calls `displayTitle` inside its line loop (`if trimmed.hasPrefix("#") && trimmed.contains(displayTitle)`), splitting the full note a second time.
- Each `NoteCardRow` render evaluates `displayTitle`, `previewExcerpt` (twice: `.isEmpty` check and text value), and `checklistStats`—allocating 4–5 full line arrays per row render.
- In `NoteDetailEditorView` (line 275), the status bar computes word count on every keystroke via:
  ```swift
  editableContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
  ```
  which allocates a `[String]` of every word in the note on every character typed.

**Fix**
- Compute `displayTitle`, `previewExcerpt`, and `checklistStats` in a single pass when a `Note` is parsed or saved, and store them as stored properties on `Note`.
- Compute word count via a zero-allocation character/scalar scan (tracking transitions between whitespace and non-whitespace) or update it inside the debounced save timer (`scheduleSave()`).

---

## 3. `DashboardView` Re-runs Regex Extraction Across All Notes 11× Per Render

> **Status: fixed on macOS** (`bc7e424`). `NoteStorageManager` caches agenda items per note until the note's `content` or `createdAt` changes, or its agenda log entries change, and caches the combined list until `notes` changes. `DashboardView.body` builds one `Snapshot` from a single read and derives every section and counter from it. The editor's agenda column uses the same cache. The Windows app already built the dashboard from one read.

**Where**
- macOS: `Sources/Storage/NoteStorageManager.swift` (`agendaItems`), `Sources/Models/Agenda.swift` (`AgendaExtractor`), `Sources/Views/Dashboard/DashboardView.swift`

**Problem**
- `storageManager.agendaItems` is a computed property (`notes.flatMap { agendaItems(for: $0) }`) that runs `AgendaExtractor.items(from:anchors:)` (up to 9 `NSRegularExpression` matches per line) across every note in the vault.
- In `DashboardView`, `overdue`, `dueToday`, `upcomingByDay`, `undatedTodosByNote`, and `openTodoCount` are computed properties that each read `storageManager.agendaItems`.
- A single evaluation of `DashboardView.body` reads `overdue` 4 times, `dueToday` 4 times, and `upcomingByDay`, `undatedTodosByNote`, and `openTodoCount` once each—running full-vault regex extraction **11 times per frame**.

**Fix**
- Cache extracted `[AgendaItem]` per note (recomputing only when a note's `content` or `createdAt` changes) or publish `agendaItems` from `NoteStorageManager`.
- In `DashboardView.body`, snapshot `let items = storageManager.agendaItems` once and derive `overdue`, `dueToday`, `upcoming`, `todos`, and `openTodoCount` from that local array.

---

## 4. `AgendaLog` Duplicate String Storage & Per-Call Allocations

> **Status: fixed on all platforms.** `.agenda-log.json` is gone. The day a line refers to and the day it was ticked are written into the line itself as `📅 2026-10-27` and `✅ 2026-10-28` (`AgendaExtractor.resolvingDates`), so there is no extra store, no duplicate `line` field, no per-call dictionary mapping, and no single-file sync contention.

**Where**
- macOS: `Sources/Storage/AgendaLog.swift`, `Sources/Storage/NoteStorageManager.swift` (`generateUniqueFileName`)
- Windows: `windows/src/ScatteredNotes.Core/Agenda/AgendaLog.cs`

**Problem**
- `.agenda-log.json` and `AgendaLog.Entry` store each line's text twice: once as the dictionary key (`logKey`) and again in `Entry.line` (which is never read—`anchors(for:)` only reads `firstSeen`).
- `AgendaLog.anchors(for:)` calls `notes[noteID.uuidString]?.mapValues(\.firstSeen)`, allocating a new `[String: Date]` dictionary on every call.
- `AgendaLog.encoder` and `AgendaLog.decoder` are computed properties (`static var`) that instantiate a new `JSONEncoder` / `JSONDecoder` on every read/write.
- `NoteStorageManager.generateUniqueFileName` allocates a new `DateFormatter()` on every save instead of reusing a `static let` formatter.

**Fix**
- Keep a direct `[String: Date]` map in memory (or cache `firstSeen` dates directly) so `anchors(for:)` is an `O(1)` lookup with zero dictionary allocation.
- Change `AgendaLog.encoder`, `AgendaLog.decoder`, and the filename `DateFormatter` to `static let`.

---

## 5. Eager `VStack` in `MarkdownRendererView`

> **Status: partly fixed.** It is a `LazyVStack` now. Parsing per keystroke in split mode is still open.

**Where**
- macOS: `Sources/Views/Editor/MarkdownRendererView.swift`

**Problem**
- `MarkdownRendererView` wraps `ForEach(0..<lines.count)` in an eager `VStack` inside a `ScrollView`, instantiating views and parsing `AttributedString(markdown:)` for every line in the note at once (including offscreen lines).
- In `.split` editor mode, `MarkdownRendererView` binds directly to `$editableContent`, re-splitting and re-parsing all lines on every keystroke.

**Fix**
- Replace `VStack` with `LazyVStack` so only visible lines are instantiated and parsed.
- Debounce or line-cache `AttributedString(markdown:)` parsing in split mode.

---

## 6. Hidden `QuickCapturePanel` Subscribes to `NoteStorageManager` Updates

**Where**
- macOS: `Sources/QuickCapture/QuickCapturePanel.swift`, `Sources/QuickCapture/QuickCaptureView.swift`

**Problem**
- `QuickCapturePanel.shared` stays allocated for the lifetime of the app with a buffered window backing store (`backing: .buffered`), an active `NSVisualEffectView`, and an `NSHostingView<QuickCaptureView>`.
- Because `QuickCaptureView` observes `@ObservedObject var storageManager = NoteStorageManager.shared`, SwiftUI invalidates and re-evaluates `QuickCaptureView` whenever notes change in the main window, even while the panel is hidden (`orderOut(nil)`).

**Fix**
- Only pass the lightweight `projects` and `areas` lists needed by the destination menu, or attach/refresh the `QuickCaptureView` state only when `showPanel()` is called.

---

## 7. Sidebar Badge Counts Allocate Temporary Arrays

> **Status: fixed on macOS.** The Inbox and project badges come from one pass over the notes (`rowCounts()`).

**Where**
- macOS: `Sources/Views/Sidebar/SidebarView.swift` (lines 64, 77, 116)

**Problem**
- Inbox, every Project row, and every Area row compute `.badge(storageManager.notes.filter { ... }.count)`, allocating a temporary `[Note]` array per sidebar row on every note change.

**Fix**
- Precompute note counts per category/target in a single pass inside `NoteStorageManager` (or use a non-allocating count helper) and read the count in `O(1)` from `SidebarView`.

---

## 8. Power-User Scale Profile & Multi-Year Bottlenecks

Because Scattered Notes centers on frictionless Quick Capture (`⌥ N` / `Ctrl+Alt+N`), a power user creates many small notes rather than a few large documents:

| Metric | 1 Year (Power User) | 3 Years (Power User) |
| :--- | :--- | :--- |
| **Note count** | ~2,500 – 5,000 notes (8–15/day) | ~7,500 – 15,000 notes |
| **Note size distribution** | ~70% Quick Captures (200–450 B), ~25% Meeting/Project notes (0.8–3 KB), ~5% Long notes (4–15 KB). Median ~400 B; mean ~1 KB | Same (~1 KB mean) |
| **Raw text in RAM** | ~2.5 – 5 MB UTF-8 (~12 – 18 MB with Swift/C#/Kotlin model structs & caches) | ~7.5 – 15 MB UTF-8 (~35 – 55 MB in RAM) |
| **Disk footprint (4 KB blocks)** | ~10 – 20 MB across `.md` files + ~300 – 600 KB `.agenda-log.json` | ~30 – 60 MB across `.md` files + ~1 – 2 MB `.agenda-log.json` |

At 5,000–15,000 notes, RAM and disk usage remain modest, but **cold-start file I/O**, **`.agenda-log.json` growth/sync contention**, and **full-vault scans** become the primary scaling bottlenecks:

### 8.1 Keep All Note Metadata & Agenda Stamps in `.md` Frontmatter
- **Status: implemented.** Each `.md` file carries its note metadata (`id`, `title`, `created_at`, `updated_at`, `tags`, `pinned`) in YAML frontmatter and its line-level dates as `📅` and `✅` markers in the line, eliminating `.agenda-log.json` altogether.
  - **Zero cross-note cloud sync contention:** Two devices editing different notes never write to the same shared `.agenda-log.json` file.
  - **Self-contained files:** Every note carries its own resolved dates and completion days, readable by any Markdown tool.

### 8.2 `AgendaLog` Cleanup (Superseded by line markers)
- **Status: fixed on every platform; `AgendaLog` and the interim `AgendaStamps` frontmatter maps are both gone.**
- Previously, `.agenda-log.json` stored each line's text twice (as the dictionary key and again in `Entry.line`), required `.agenda-log 2.json` conflict merging across devices, and grew across the entire vault in a single file.
- The line markers resolve all three: the date lives in the line it belongs to, so nothing is stored twice and nothing needs pruning.

### 8.3 Persistent Local Index Cache for Instant Cold Start at 5,000+ Notes
- **Where:** `NoteStorageManager.loadAll()` (macOS/iOS), `NoteStore.LoadAll()` (Windows), `NoteStore.loadAll()` (Android)
- **Problem:**
  - `fileCache` (skipping re-parse when `(mtime, size)` is unchanged) only lives in memory for the current process lifetime.
  - On cold launch with 5,000–15,000 notes, the app must open, read, split frontmatter, and run `AgendaExtractor` (9 regexes per line) across every `.md` file on disk before the Dashboard is ready.
  - On Windows (`NoteStore.cs`), `LoadAll()` still lacks the in-memory `(mtime, size)` `fileCache` that macOS and Android have, so every `FileSystemWatcher` event re-reads all files from disk.
- **Fix:**
  - Add the in-memory `(mtime, size)` `fileCache` and `agendaCache` to Windows `NoteStore.cs`.
  - Store a **derived local cache file** (in the platform's local app-cache directory, *not* synced to iCloud/OneDrive) mapping `(relativePath, mtime, fileSize)` to parsed note metadata and extracted `[AgendaItem]`. On cold launch, `stat` the directory tree, hydrate unchanged notes from the local cache, and only read/parse `.md` files whose `(mtime, size)` changed. If the cache is missing or corrupt, rebuild it transparently from the `.md` files + `.agenda-log.json`.

### 8.4 Pre-Index `@people`, `#tags`, and Search Tokens Per Note
- **Status: partly fixed.** `@people` are cached per note on macOS (`NoteStorageManager.people(in:)`) and Windows (`NoteStore.PeopleIn`), and each note is scanned once per sidebar refresh instead of twice. Tags already come from a stored property. Search tokens are not indexed.
- **Where:** `Sources/Views/Sidebar/SidebarView.swift` (`counted`), `Sources/Models/Mentions.swift`, `Sources/Search/NoteSearch.swift`
- **Problem:**
  - `SidebarView` re-scans every note's full body via `Mentions.people(in:)` and `Mentions.tags(in:)` (2 regex scans + lowercase allocations per note) whenever `storageManager.notes` changes. At 5,000 notes, every 0.5s auto-save triggers 10,000 regex scans just to render the sidebar counts.
- **Fix:**
  - Extract and cache `people: [String]` and `inlineTags: [String]` per note alongside `agendaCache` in `NoteStorageManager` (recomputing only for the single note whose `content` changed), and maintain aggregated sidebar counts incrementally.

