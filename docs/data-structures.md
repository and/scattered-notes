# Data structures and algorithms in Scattered Notes

A map of the data structures (DS) and algorithms the app uses, where each lives, which feature it serves and what it costs. Costs use N for the number of notes, M for the number of agenda items (to-dos and dated lines) and L for the length of a line or text. Each entry ends with when to reach for the idea elsewhere.

Update this file when a feature adds or changes one of these.

## Date editing and the date log

Feature: set a day on an undated to-do, change the day of a dated one, and keep a history of the changes.

| Piece | DS / algorithm | File | Cost |
|---|---|---|---|
| Rewrite one line of a note | Array of lines: split, change one index, join | `AgendaExtractor.settingDate` in `Sources/Models/Agenda.swift` | O(L) for the note text |
| Replace the old `📅` marker | Regular expression (a finite automaton) | `AgendaExtractor.withoutMarkers` | O(length of the line) |
| Recognise a line after it moves | Key = the line's words without bullet, checkbox and markers | `AgendaExtractor.lineKey` | O(length of the line) |
| The change history | Append-only log in JSON Lines, one device per file | `Sources/Storage/DateChangeLog.swift` | append O(1) |
| Merge the files of several devices | Union of grow-only sets: a `Set` of ids drops repeats, then sort by time | `DateChangeLog.reload` | O(E log E) for E changes |
| History of one note | Hash map from note id to a time-ordered array | `DateChangeLog.byNote` | lookup O(1), then filter O(k) |
| Quick picks | Calendar arithmetic (`nextDate(after:matching:)`) | `QuickDates.options` | O(1) |

Why a log and not a field on the line. A to-do's current day lives in its note as a `📅` marker, because the note is the single source of truth and the other apps (Windows, Android, Obsidian Tasks) already read it. The history is different data: it only grows, and nothing reads it except the history list. An append-only log suits that. Appending one line never rewrites the file, so a crash can at worst leave one half-written last line, and `reload` skips a line that does not decode.

Why one file per device. If two devices append to one file, iCloud has to merge two versions and makes a conflict copy. With one file per device, nobody else writes your file. Reading merges all files. Because every change has a unique id and is never edited, merging is just "union, then sort", and the result is the same on every device whatever order the files arrive in. This is the idea behind a grow-only set, one of the simplest CRDTs (data types built to merge without conflicts).

When to reach for it: any history, audit trail or activity feed that is written often and read rarely.

Known limit. A line is matched to its history by its words. If you reword a to-do, its earlier history stays under the old words.

## Dashboard quick search

Feature: a search box on the Dashboard that narrows every section to items matching what you type.

| Piece | DS / algorithm | File | Cost |
|---|---|---|---|
| Split the query into words | Tokenize on whitespace | `DashboardSearch.terms` in `Sources/Models/DashboardSnapshot.swift` | O(length of query) |
| Ignore case and accents | Normalize both sides before comparing (folding) | `DashboardSearch.fold` | O(L) per text |
| Match | AND of substring tests: every word must be in the item text or its note title | `DashboardSearch.matches` | O(M x words x L) |
| Note title of an item | Hash map lookup, note id to note | `DashboardSearch.filter` | O(1) per item |
| Sections | Filter first, then build the snapshot, so grouping, sorting and counts all follow the filter | `DashboardView.scopedSnapshot` | O(M) |

Filter before grouping, not after: the sections, counts and "nothing planned" state are all derived from the snapshot, so one filter in front keeps them consistent. Reach for it when a screen has several derived views of one list.

Limits: it is a plain substring scan, so there is no typo tolerance or ranking, and it rescans all items on each keystroke. That is fine for thousands of items. For much more, an inverted index (word to items) would find matches without scanning.

## Note links and backlinks

Feature: find the notes a note mentions, by title or by `[[Title]]`, and the notes that mention it.

| Piece | DS / algorithm | File | Cost |
|---|---|---|---|
| Split a text into words | One pass over the characters, a word being a run of letters and digits | `NoteLinkIndex.words` in `Sources/Models/NoteLinks.swift` | O(L) |
| Ignore case and accents | Lower-case plain ASCII words, fold the rest | `NoteLinkIndex.words` | O(L) |
| Find titles in a text | Trie of words: follow the text's words down the tree and keep the longest title that ends on the way | `NoteLinkIndex.scan` | O(L), plus the length of the longest title at each word |
| Titles that overlap | Longest match wins, then skip past the words it used | `NoteLinkIndex.scan` | O(L) |
| `[[Title]]` | Regular expression, then a hash map lookup of the folded title | `NoteLinkIndex.scan`, `byFullTitle` | O(L) |
| Backlinks | Invert the links: hash map from target note to the set of notes that link to it, then sort newest first | `NoteLinkIndex.init` | O(links log links) |

A trie is a tree where each step is one word, so all titles starting "Trip to" share the first two steps. The first version looked titles up by their first word and tested each candidate. It took 1.9 s to index 2,000 notes in which every title began with "Topic"; the trie takes 0.3 s, because the number of titles that share a first word no longer matters. Reach for a trie when many keys share a prefix and you need the longest one that matches. Aho-Corasick is the same idea with extra links so a failed match does not restart; this app does not need them, because it matches whole words and restarts at the next word anyway.

The system's own word splitting (`enumerateSubstrings(.byWords)`) was left out: it changes with the language and is slower, and the same rule has to be written again for Windows and Android.

Limits: the index is rebuilt from all notes, so keep it and rebuild only when a note's title or text changes. A title of one common word, such as "Notes", links wherever that word appears.

## Hash maps and multimaps

A hash map finds a value from a key in O(1) on average.

- `DashboardSnapshot.notesByID` (`Sources/Models/DashboardSnapshot.swift`): note id to note, so each agenda item finds its note without scanning N notes. Built with `Dictionary(uniqueKeysWithValues:)`, which crashes on a duplicate id.
- `AgendaExtractor.resolvingDates` (`Agenda.swift`): `[String: [(due, done)]]`, a multimap from a line's words to the markers it had when last saved. A line keeps its days when it moves or is edited. Two identical lines each take one entry with `removeFirst`, so they keep their own days. O(N) to build, O(1) to find.
- Sidebar badges (`SidebarView.rowCounts`): one pass over the notes counting into a `[String: Int]`.
- People and tags (`SidebarView.counted`, `GoToTargets.named`): two dictionaries, one for counts and one for the first spelling seen, so "Ana" and "ana" count together.
- Caches keyed by path or note id (see Caches below).

Reach for it when you ask "give me the thing for this key" more than once.

## Sets

A set answers "have I seen this?" in O(1).

- `DashboardSnapshot`: `inPlace` (ids already shown in Overdue, Today or To-do, so Completed skips them) and `doneToday`.
- `Mentions.names` and `Note.parse`: remove repeats while keeping the order of first appearance, case-insensitively.
- `Note.appKeys`: the front matter keys the app owns; any other key is kept untouched, so notes edited in other apps survive a save.
- Cache pruning in `NoteStorageManager.loadAll`: keep only cache entries whose note still exists.
- `DateChangeLog.reload`: drops a change seen twice.

## Grouping and bucketing

`Dictionary(grouping:by:)` sorts items into buckets by key in one pass, O(M).

- `DashboardSnapshot.upcomingByDay`: items by day, then the keys are sorted.
- `DashboardSnapshot.undatedTodosByNote`: to-dos by note id, items ordered by line, notes ordered by last update.
- `DashboardView` Completed section: run-length grouping. Items are already sorted, so a new group starts whenever the label changes. O(M) and no dictionary needed.

## Sorting

Sorting costs O(n log n). The skill is the comparison.

- Composite keys: notes sort pinned first, then newest (`NoteStorageManager.sortNotes`). Completed items sort by day ticked, newest first, with note update time, note id and line number as tie-breaks, so the order never flickers between runs.
- Search results sort by score, then by update time, and keep the first `limit` (`NoteSearch.search`). Sort-then-prefix is O(R log R) for R results; a heap would be O(R log k) and worth it only when R is huge.
- Overdue sorts by date ascending.

## Caches and invalidation

A cache trades memory for time. The hard part is knowing when an entry is stale.

- `fileCache` (`NoteStorageManager`): parsed note by file path, valid while the file's modification date and size are unchanged. A reload costs one `stat` per file and a parse only for files that changed.
- `agendaCache`: agenda items by note id, valid while the text and update time are equal. The update time is part of the key because relative words resolve against it.
- `peopleCache`: `@people` by note id, valid while the text is equal.
- `allAgendaItems`: a lazily built aggregate over every note, thrown away in the `didSet` of `notes`. Nothing recomputes it until the next read.

## Strings: parsing and scanning

- Regex chain of responsibility (`AgendaExtractor.parseDay`): an ordered list of patterns, the first match wins. ISO date, month and day, "the 22nd", "in N days", weekdays and the rest are tried most specific first, so "day after tomorrow" is not read as "tomorrow".
- Cheap pre-filter (`mayMentionADay`, `hasMarker`): scan the bytes for a hint before running any regex. Most lines hold no date, and a scan is far cheaper than a pattern.
- Single-pass tokenizer / state machine (`Mentions.marks`): walks the text once, remembering only the previous character, and finds `@person`, `#tag` and `+project` in O(L). `NoteDetailEditorView.wordCount` is the same idea with no array allocated.
- Line-cursor scanner (`Note.splitFrontmatter`, `Note.parse`): reads the YAML header and body in one pass.
- Carrying state down a loop (`previousDate` in `AgendaExtractor.items`): "the day after" needs the closest dated line above it, so one variable is passed along.
- Cursor remapping (`EditorFocus.mappedOffset`): the editor hides the markers, so a caret position in the text with markers is mapped to the text without. Today that costs O(n × markers); a single walk with a running offset would be O(n).
- Escaping (`Note.escapeYAML`, `unescapeYAML`): one pass with an iterator.

## Ranking and search

- Weighted scoring (`NoteSearch.match`): a title hit, a start-of-title hit and body hits each add points. Occurrences are counted only up to 6, so one long note full of the word cannot beat a precise title match. A snippet window is cut around the first hit.
- Tiered ranking (`GoToTargets.matching`, the ⌘O switcher): rank 0 for a prefix, 1 for a word prefix, 2 for a substring; ties keep the original order, which makes the sort deterministic. A leading `#` or `@` limits the search to tags or people. It is not fuzzy matching: "dbms" does not find "database management". Fuzzy matching would use a subsequence scan or edit distance.
- Unicode folding (`GoToTargets.fold`): case and accents are removed before comparing.

## Systems and timing

- Debounce (`NoteDetailEditorView.scheduleSave` 0.4 s, `QuickCaptureView` 0.6 s, iOS editor 0.8 s): each keystroke restarts a timer, so the file is written once typing pauses.
- Suppression window (`isPerformingInternalFileOperation`): after the app writes a file, file-watcher events are ignored for 0.5 s so the app does not reload its own write. A time-based guess; simple, and it can miss an outside change made inside the window.
- Event coalescing: `FolderWatcher` (FSEvents, 0.3 s latency) and `ICloudWatcher` (`NSMetadataQuery`, 0.5 s) batch bursts of changes into one reload.
- Bounded retry (`NotesFolder.refresh` on iPhone, `EditorFocus.focusTextView`): try again after 2 s and 6 s, or a fixed number of times, then stop.
- Crash-safe write order (`NoteStorageManager.save`): write the new file, then delete the old one when a note moves. A crash leaves two copies, never none; `loadAll` keeps the newest of two notes with the same id.
- Collision counters (`generateUniqueFileName`, `uniqueDestination`): add a suffix until the name is free.
- Undo stack (`NSUndoManager` in `MainSplitView.dropNote`): moving a note by drag registers the inverse move.
- Migration pass (`migrateAreasToTags`): old Areas become tags once.
- Version compare (`AppVersion` in `Release.swift`): compare dot-separated numbers part by part.

## Known weak spots

Honest list, with the cheap fixes. See `docs/memory-efficiency.md` for more.

- Note lookup by id is a linear scan (`notes.first(where:)` in `save`, `toggleChecklistItem`, `setDate`): O(N) each. A `[UUID: Int]` index would make it O(1) but must be rebuilt when `notes` changes.
- `save` re-sorts all notes every time: O(N log N). Inserting at the right place would be O(N).
- The search palettes recompute their lists on every keystroke instead of indexing once (no trie or inverted index). Fine at hundreds of notes; at tens of thousands it would need an index.
- `NoteListView` search lowercases each note's text on every filter.
- `AgendaItem.id` is the note id plus line number, so inserting a line above shifts the ids below it.
- `Dictionary(uniqueKeysWithValues:)` in `DashboardSnapshot` traps on a duplicate note id.
