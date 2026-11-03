# Notes in the list react when the pointer is over them

2026-11-03. Commit `c2c0c5e`.

## Problem
Pointing at a note in the list did nothing. It felt reactionless.

## Evidence
My own use of the app. Rows on the Dashboard already reacted to the pointer, so the note list stood out as the odd one.

## Why
Each note is an entity, something I interact with. An entity I interact with needs some reaction to show it noticed me, even before I click.

## Options
1. Leave it as it is. Rejected: it is the feeling I wanted to fix.
2. Change the selected row's look. Rejected: selection already has its own blue, chosen so the white text stays readable.
3. A light gray background while the pointer is over the row, like the Dashboard rows. Chosen.

## Decision
A light gray background with a short fade on the row under the pointer. It never changes which note is selected, and the selected row keeps its look. The faint blue mark the Dashboard uses to point at a note in the list keeps priority, so the two cues stay different.

## Result
A UI test checks that pointing at a row does not open or select it. I have not looked at the shade on screen yet.

## Cost and next
One more piece of state in every row. Worth checking the shade in light and dark mode and with a different system accent color.
