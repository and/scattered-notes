# Log notes

A note whose title, or first line, starts with "Log -" is a log book. Each line is given the time it was written, shown in a column at the right of the editor, like line numbers in a code editor.

## What the file looks like

The time is stored in the note's file at the start of each line, the way a log file has it:

```
Log - productivity
2026-11-05T13:32:00+05:30 this is good.
2026-11-05T13:39:57+05:30 what is happening?
```

- The time is ISO 8601 / RFC 3339 with seconds and the writer's UTC offset. The offset fixes the exact moment, so a line written in one time zone shows the right local time when read in another.
- The file is a plain log. Other log readers (`tail`, `lnav`, Console, `grep` and `sort`) can read it as it is. That is the reason the time is first on the line.
- The "Log -" heading line has no time. A later line that starts with "Log -" is an ordinary entry and gets one.
- The editor hides the times from the text and draws them in the column as `2026-11-05 13:39:57`, in the time zone the Mac is set to. Saving puts them back.

## When a line gets its time

- A line gets the current time the first time it has text, and keeps it however it is edited afterwards.
- A line pushed down by a new line keeps its time. A split line keeps the time on its first part. Deleting whole lines removes their times only.
- Lines written before the note became a log, or in another app, have no time until they are edited.

## Older files

The first version wrote the time at the end of the line: `ran 5k ⏱ 2026-11-05 11:34`, and a later one `ran 5k ⏱ 2026-11-05T11:34:07+05:30`. Both are still read, and a line is written in the new form the next time it is saved.

## Where the code is

| What | File |
|---|---|
| Reading and writing times, keeping them in step with typing | `Sources/Models/LogNotes.swift` (`LogLines`) |
| The editor and the time column | `Sources/Views/Editor/LogEditorView.swift` |
| Agenda, previews and search ignore the times | `Sources/Models/Agenda.swift` (`withoutMarkers`) |
| Tests | `Tests/ScatteredNotesTests/LogNotesTests.swift` |

## Limits

- The iPhone, Windows and Android apps show the times as part of the text for now.
- The log editor does not offer "Make this a link".
