# A new note takes its title from its first line

2026-11-03. Commit `43c4914`.

## Problem
A new note showed "Untitled Note" in the header while the note's text said something else, and the title never changed.

## Evidence
A screenshot showed the header "Untitled Note" above a note whose text was "super!".

## Options
1. Create new notes with an empty title and show the first line as a gray placeholder. Rejected: it leaves the stored title empty and looks different from every other note.
2. Treat the title as following the first line unless it was typed by hand. Chosen.

## Decision
The cause was that a new note was created with the literal title "Untitled Note", which the app took as a title someone had chosen, so it never looked at the text. Now a note whose title is empty, "Untitled Note", or the same as its first line keeps following its first line as it is edited. A title typed in the header is left alone.

## Result
A UI test creates a note with ⌘N, types a line, and checks that the saved title matches it.

## Cost and next
Existing notes whose title equals their first line follow edits to that line now, and so does a hand-typed title that happens to equal the first line. The file name does not change, so a new note's file keeps the name `untitled-note` for good.
