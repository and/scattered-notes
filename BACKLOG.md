# Backlog

Features we plan to build later. Move an item to "Done" when it ships.

## Planned

### Clickable dashboard counters

The four counters at the top of the Dashboard (**overdue**, **today**, **upcoming**, **open to-dos**) are display only. Make each one a button that filters the Dashboard to that group.

**Behavior**
- Clicking a counter shows only that group's items; the other sections hide.
- Clicking the active counter again clears the filter and shows everything.
- The active counter looks selected (filled background, accent outline) and is announced as selected to VoiceOver.
- Counters showing 0 stay clickable and show a short empty state, e.g. "Nothing overdue."
- Filters:
  - **overdue**: unfinished items dated before today
  - **today**: items dated today
  - **upcoming**: unfinished items dated in the next 14 days, grouped by day as now
  - **open to-dos**: all unchecked checklist items, including undated ones, grouped by note
- Esc clears an active filter before it navigates away (see the Esc rules in the README).

**Notes for the build**
- `StatChip` in `Sources/Views/Dashboard/DashboardView.swift` becomes a `Button` with a hover state and pointer feedback.
- Keep the filter in `DashboardView` state; no need to persist it.
- Reuse the existing `overdue`, `dueToday`, `upcomingByDay` and `undatedTodosByNote` properties rather than recomputing.
- Keyboard: counters must be reachable with Tab and activated with Space.
- Tests: pure filtering logic in a testable type, plus one UI-level check that the chip toggles the section.

**Open questions**
- Should "open to-dos" include completed-today items so they can be unticked?
- Should the filter reset when the user leaves the Dashboard and returns?

### Memory efficiency optimizations

Reduce memory footprint and per-frame allocations across the storage, model, and view layers (see [`docs/memory-efficiency.md`](docs/memory-efficiency.md) for the full audit):
- [x] Cache `agendaItems` per note and compute `DashboardView` sections from a single `Snapshot` per render instead of re-running `AgendaExtractor` 11× per frame (`bc7e424`).
- [x] Reload only modified `.md` files on file-watcher events on macOS via `fileCache` and `FolderWatcher` (`bc7e424`).
- [x] Keep `agendaCache` across `loadAll()` and re-run `AgendaExtractor` only for notes whose text or update time changed.
- [ ] Cache `displayTitle`, `previewExcerpt`, and `checklistStats` on `Note` at parse/save time instead of splitting `content` on every `NoteCardRow` render.
- [x] Replace per-keystroke array-allocating word count in `NoteDetailEditorView` with a zero-allocation scalar scan.
- [x] Replace `.agenda-log.json` (`AgendaLog`) with `📅` / `✅` date markers written into each line (Obsidian Tasks format), eliminating duplicate `"line"` strings, per-call dictionary allocations in `anchors(for:)`, and `.agenda-log.json` sync conflicts.
- [x] Replace `DateFormatter()` allocation in `NoteStorageManager.generateUniqueFileName` with a `static let` formatter.
- [x] Use `LazyVStack` in `MarkdownRendererView` and precompute sidebar badge counts without `.filter { ... }.count` array allocations.
- [x] Give Windows the same `(mtime, size)` file cache and per-note agenda cache as macOS and Android, and cache each note's `@people` on macOS and Windows.
- [ ] Measure cold start with a generated 10,000-note vault. Only if it takes over about 2 s, add a local derived disk cache keyed by `(relativePath, mtime, fileSize)`.

### iPhone: search bar is hidden until you pull the list down
- [ ] On the iPhone app's Notes screen the search bar is hidden by default and only appears after dragging the list down. It should always be visible.
- Commit `1a458fc` already set `.searchable(..., placement: .navigationBarDrawer(displayMode: .always))` in `ios/Sources/NotesScreen.swift`, but the problem was reported again. That change shipped in 1.2.0 (build 11), which was never uploaded to TestFlight, so the phone may be running an older build. First install the 1.3.0 build and check. If the bar is still hidden, `displayMode: .always` is not enough on this iOS version; try placing a search field above the list (as the Mac does) instead of relying on `.searchable`.
- Add an iPhone screen test (`ios/UITests`) that opens the Notes screen and checks the search field is on screen without scrolling.

### iPhone: the app takes a long time to load
- [ ] The iPhone app is slow to show the Dashboard and the Notes section. Reported in the Sn project's "Bugs" note.
- Measure first: on a device, time from launch to the first notes appearing, with the notes in iCloud, and note how many notes there are. Use Instruments (Time Profiler).
- Likely causes to check:
  - `NotesFolder` calls `storage.loadAll()` on the main thread, and again after short delays while iCloud catches up. Every note file is read through file coordination, and a file iCloud has not downloaded yet can block the read.
  - The Dashboard builds its sections from every note's agenda items on each draw.
- Fix ideas: load on a background task and show notes as they arrive; keep the `(mtime, size)` cache between launches (see the cold-start item under Memory efficiency); build the Dashboard from cached items.
- Done when the Notes list and the Dashboard show within about a second on a typical vault.
- **Status (2 Nov):** measured on a generated vault in a Release build (M-series Mac, 5,000 notes): reading every note at launch 1.5 s (files 0.1 s, parsing 0.8 s, the rest is the storage manager), building the Dashboard's items 1.1 s, now 0.4 s after skipping the date patterns on lines that cannot hold a day. A real vault of about 60 notes takes a few milliseconds, so the slowness on the phone is probably iCloud (notes still downloading), not parsing. Added Settings → Diagnostics on the iPhone (note count, first and last load time, Dashboard time, notes waiting for iCloud) to tell which. Next: install 1.3.x on the phone, read the numbers, and fix what they point to. If notes are waiting for iCloud, show a "Downloading n notes" line instead of an empty list. Still open for large vaults: parse frontmatter dates without `ISO8601DateFormatter`, and load off the main thread.

### MCP server and CLI for Claude and ChatGPT

Let local AI tools (Claude Desktop, Claude Code, ChatGPT Desktop) query and update Scattered Notes with full awareness of relative date anchors, Dashboard state, projects, tags, and `@person` mentions—rather than reading raw `.md` files and guessing what `"tomorrow"` means.

**Behavior**
- Expose a local MCP server (e.g. `ScatteredNotes --mcp` or `scattered-notes-mcp`) and CLI subcommands that read the user's configured notes folder (`AppSettings.shared.notesDirectoryURL`).
- Provide semantic tools backed by `DashboardSnapshot`, `AgendaExtractor`, `NoteSearch`, and `Mentions`:
  - `get_dashboard`: returns `overdue`, `dueToday`, `doneToday`, `upcomingByDay` (next 14 days, dates read from the `📅` markers in the notes), and `undatedTodosByNote`.
  - `search_notes(query)`: runs `NoteSearch.search` and returns matching notes with snippets and match positions.
  - `list_notes(project?, tag?, person?)`: filters notes by `+project`, `#tag`, or `@person`.
  - `read_note(id)`: returns full note metadata, body, and resolved agenda items.
  - `capture_note(content, project?)`: creates a properly formatted `.md` file (supporting inline `+project` and `#tag` tokens) and writes the `📅` marker for relative words.
  - `toggle_todo(note_id, line_number)`: ticks or unticks a checklist or dated line in the `.md` file and adds or removes the line's `✅` marker.
- Also provide a one-click **"Copy MCP config for Claude / ChatGPT"** button or instructions in Settings, plus an optional `AGENTS.md` / `CLAUDE.md` file format guide for direct folder access.

### ⌘N doesn't create the note in the open project
- [ ] The New note button (✎) shows "⌘N" in its tooltip. Clicking it inside a project puts the new note in that project. Pressing ⌘N does not.
- Likely cause: the app's `WindowGroup` adds File ▸ New Window with ⌘N, and a menu item beats the `.keyboardShortcut("n")` on the button in `NoteListView`. Confirm, then replace the default New Window item with a "New Note" command (`CommandGroup(replacing: .newItem)`) that calls the same `createNewNoteInCurrentCategory()` as the button. Decide where New Window goes (probably ⇧⌘N).
- Test: ⌘N inside a project, a person and a tag creates the note with the same placement as the button.
- **Status (2 Nov):** fix written, not yet committed. File ▸ New Note takes ⌘N and calls the same function as the button; New Window moved to ⇧⌘N. The placement rule is now `NewNoteDraft` with unit tests. Still to do: press ⌘N in the running app inside a project, a person and a tag, and confirm. If it still misses the project, the cause is not the menu shortcut and this needs a closer look.

### New note is not visible after creating it
- [ ] Creating a note doesn't always show it. Needs a repro first: which list is open, which sort, and whether a search or filter is active. Check that the new note is selected, scrolled into view, and not hidden by the current filter, sort or search.

### Navigation: Master Dashboard › Project › Notes › Note
Structure the app as levels, and make every Esc go up one level:
- Master Dashboard › Project › (Project dashboard / Notes) › Note.
- From the editor, Esc (and a visible Back control) returns to the list of notes it was opened from, then to the project, then to the Master Dashboard.
- Extends the Esc rules in the README. A filter or search clears before Esc navigates up.
- Same levels on iPhone, using the navigation stack's back button.

### Go to a folder from the keyboard
- [x] **Done (3 Nov, Mac): ⌘O opens "Go to Project, Person or Tag…".** Type part of a name (accents and case ignored; `#` limits it to tags, `@` to people), ↑↓ pick, ↵ goes there and leaves the keyboard in that place's notes, Esc closes. Also lists Dashboard, All Notes and Inbox. Code: `GoToTargets.swift` (tested) and `GoToPaletteView.swift`. Not built for Windows, Android or iPhone yet.
- Original request: a shortcut that opens a quick switcher to jump to a project, person or tag by typing part of its name. Return opens it. Related: the existing "Search All Notes…" shortcut.

### Drag a note onto a project
- **Status (3 Nov, Mac): written, not yet confirmed in the running app.** Notes in the list can be dragged onto a project or the Inbox in the sidebar; the target outlines itself, the note moves, and ⌘Z moves it back. Code: `NoteDrag.swift`, with `NoteDragTests` for the payload and drop rules. The screen test `testDraggingANoteOntoAProjectMovesItAndUndoBringsItBack` skips itself while the screen is locked and has not run yet: run `make ui-test` at the Mac, and drag a note by hand once. Not built for Windows, Android or iPhone.
- [ ] Dragging a note from the list onto a project in the sidebar moves it into that project. The project highlights as a drop target. Moving is undoable (⌘Z).
- Dropping onto Inbox moves it out of the project.

### New notes made inside a project belong to it
- [ ] Covered for the ✎ button. Cover every way to create a note (⌘N, the menu, Quick Capture with a project open) with one shared code path and a test per entry point. See the ⌘N item above.

### iPhone: see projects
- [ ] The iPhone app has no way to browse projects (Quick Capture can file into one). Add a Projects section on the Notes screen or as a tab, listing each project with its note count; tapping one shows its notes. Same levels as the navigation item above.

### Project kanban view with a work-in-progress limit
- [ ] Make the Projects section clickable to show a kanban board.
- Columns by status (for example Next, In progress, Done). In progress is capped (default 3). The person can raise it to 4, 5 or more.
- At the limit, moving another project in asks "Finish or park one first?" instead of blocking.
- **Open questions**
  - How do we find the person's capacity: ask in settings, or learn from how many projects they actually finish per week?
  - Learning from completion is possible with on-device data (done dates already live in the `✅` markers). Should the app suggest a limit ("You finish about 2 a week; try 2")?
  - Use an OS-provided intelligence layer for the suggestion, or keep it a simple rule in the app? Start with the rule.

### Quick Capture: pick a project inline
- [ ] Pressing + in Quick Capture opens an inline list of projects, filtered as you type, so the note is filed without leaving the window. Return picks the highlighted project; Esc closes the list and keeps the text.

### Recent notes under Quick Access
- [ ] Show the last few notes opened or edited under Quick Access in the sidebar. A Settings switch turns it on or off.
- Open question: on by default? Proposal: on, because it is the fastest way back to what you were doing.

### Auto-link notes and show linked notes at the right
- [ ] Detect mentions of other notes' titles in a note's text, and show them as links. A panel at the right of the editor lists notes this note links to and notes that link to it (backlinks).
- Start with exact title matches and explicit `[[Title]]` links; no fuzzy matching.
- Linking must not rewrite the `.md` files unless the person accepts a suggestion.

**Plan (5 Nov): no AI first, one rule set for every app**
- **Status (5 Nov): Mac done; Windows done (links, backlinks, "Make this a link" and Related, in `NoteLinks.cs` and `RelatedNotes.cs` with the same tests; not yet seen running on a Windows PC). Android not started. No Suggested on Windows or Android.**
- Rules live in one pure type (`NoteLinks`, in `Sources/Models`), ported by hand to Windows (`ScatteredNotes.Core`) and Android (`core/`) like `AgendaExtractor`, so a note shows the same links on every device.
- Mentions: look for every other note's title in the text in one pass (a trie or Aho-Corasick automaton), ignoring case and accents, matching whole words only, and skipping titles shorter than 3 characters and the note's own title. `[[Title]]` is parsed like `@name` is in `Mentions`.
- Backlinks: a map from each note to the notes that link to it, rebuilt only for notes that changed (same pattern as `agendaCache`). Renaming a note changes its backlinks, so the map is also rebuilt when a title changes.
- Related notes without AI: notes that share a `+project`, `#tag` or `@person`, then notes that share rare words (TF-IDF score), shown below the links as "Related".
- Panel at the right of the editor: Links to, Linked from, Related. Click a row to open the note. A mention in the text gets a "Make this a link" button that writes `[[Title]]`; nothing is written otherwise.
- Tests: whole-word matches, accents, a title inside a longer word, two notes with the same title, a note linking to itself, `[[Title]]` with no such note, a rename.
- Open questions: what to do when two notes share a title (list both, or ask); whether the panel is on by default or opened from the toolbar.
- Later, optional, Mac and iPhone only: a "Suggested" section ranked with Apple's on-device sentence embeddings (NaturalLanguage `NLEmbedding`), labeled as a suggestion and never written to the files. Windows and Android keep the rule-based list, because results from a model would differ between devices.

### Dashboard: typing while an item is highlighted goes to the search box
- [ ] On the Dashboard the arrow keys move keyboard focus off the search box onto the items. Make typing a letter while an item is highlighted jump back to the search box and add the letter there, so the search can be refined while walking through the results without pressing ↑ back to the box.
- Open question: should Esc in that state clear the search or only return focus to the items?

### Log notes: a summary of what the log says
- [ ] Read a log note's entries and show a short summary of them, for example for a day of reading: when it started and ended, how long was spent working and how long on breaks, how many entries, the longest unbroken stretch.
- Example, from the reading day in `docs/log-notes.svg`: 09:08 to 13:40, about 3 h 31 min working on reading and replies, 1 h 1 min on breaks and lunch, 7 entries, longest unbroken stretch 2 h 27 min (10:07 to 12:34).

**Plan**
- A pure type (`LogSummary`, in `Sources/Models` next to `LogLines`) so the Mac and iPhone show the same numbers, ported by hand to Windows and Android later.
- Length of an entry: the time from its stamp to the next entry's stamp. The last entry of a day runs to the next stamp or, for today, to now. A gap longer than a set limit (for example 3 hours) is not counted, since the log was probably left alone.
- Break or work: an entry that holds a word like "break", "lunch", "walk", "tea", "coffee" or "nap" counts as a break; the rest count as work. The words are a short list we can change. Start with the list, and let a `#break` or `#work` tag in the line override it.
- Group by day (the date in the stamp) and show one summary per day, newest first, with a total for the week.
- Where it shows: a "Summary" section in the Links column of a log note, and later a line on the dashboard. A summary is shown, never written into the file.
- Tests: two entries a day apart, a gap over the limit, entries out of order, a line with no stamp, a `#break` override, a day that crosses midnight, a stamp with another UTC offset.
- Open questions: should the person mark breaks by a tag instead of guessing from words? Should a summary be shareable, for example as text to paste into a report?

### Autocomplete for projects, tags and people
- [ ] Typing `+`, `#` or `@` in a note or in Quick Capture opens a short list of matching names, filtered as you type: projects after `+`, existing tags after `#`, people already mentioned after `@`. ↑↓ choose, Return or Tab completes the name, Esc closes the list and leaves the text as typed.
- Covers the "Quick Capture: pick a project inline" item above for `+`; do the two together, with one shared list of suggestions for the Mac editor, Quick Capture and the iPhone.
- Open questions: should the list show how many notes use a tag or name? Should a new name, one with no match, be offered as "Create"? Should the log editor offer it too?

### Reminders: a notification for what is due
- [ ] The apps never alert on their own: a to-do or dated line shows on the Dashboard only when the app is opened. Send a notification, on the iPhone first and then Mac, Windows and Android, when an item is due today or overdue, so "call the bank tomorrow" reaches the person without opening the app.
- Open questions: at what time of day for a line that has a day but no time? A daily summary or one alert per item? Tapping an alert should open the note at that line. Done items and snoozed ones must not alert.

### Calendar integration
- [ ] Connect the Dashboard to the calendar directly. Two directions to weigh: show calendar events beside the dated lines on the Dashboard, and write a dated line or to-do into a calendar (Apple Calendar through EventKit on Mac and iPhone; Google and Outlook calendars later, and Windows and Android through their own calendar APIs).
- Open questions: read only, or write too? One calendar for Scattered Notes or the person's choice? A line with no time becomes an all-day event. Keep the note as the source: a changed event in the calendar must not rewrite the note without asking.

## Done

_Nothing yet._
