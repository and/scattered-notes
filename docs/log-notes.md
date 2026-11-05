# Log notes

A note whose title, or first line, starts with "Log -" is a log book: each line starts with the time it was written, like a line in a log file.

## What the note looks like

The time is part of the text, at the start of each line, the way a log file has it. What you see in the editor is what is in the file, so copying the whole note copies the times too:

```
Log - productivity
2026-11-05T13:32:00+05:30 this is good.
2026-11-05T13:39:57+05:30 what is happening?
```

- The time is ISO 8601 / RFC 3339 with seconds and the writer's UTC offset. The offset fixes the exact moment, so a line written in one time zone is read correctly in another.
- Other log readers (`tail`, `lnav`, Console, `grep` and `sort`) can read the file as it is. That is the reason the time is first on the line.
- The times are drawn in a quieter grey so the entries read first. The note is shown in the system monospaced font (SF Mono on a Mac), as in a log file.
- The "Log -" heading line has no time. A later line that starts with "Log -" is an ordinary entry.

## When a line gets its time

Pressing Return starts a new line with the time of that moment already written, followed by a space. The cursor is after it. Text you type, paste or delete is never stamped by the app, and a time can be edited like any other text. Lines written before the note became a log, or in another app, have no time unless you add one.

## Older files

The first version hid the time from the text, kept it at the end of the line (`ran 5k ⏱ 2026-11-05 11:34`) and showed it in a column. That form is still read by the agenda, but the editor now shows such a line as it is in the file, with the marker at its end.

## Where the code is

| What | File |
|---|---|
| Telling a log note, the time format, taking the times off a text and putting them back | `Sources/Models/LogNotes.swift` (`LogLines`) |
| The editor, and Return writing the time | `Sources/Views/Editor/LogEditorView.swift` |
| Agenda, previews and search ignore the times | `Sources/Models/Agenda.swift` (`withoutMarkers`) |
| Tests | `Tests/ScatteredNotesTests/LogNotesTests.swift` |

## Limits

- The iPhone, Windows and Android apps show the times as part of the text for now.
- The log editor does not offer "Make this a link".
