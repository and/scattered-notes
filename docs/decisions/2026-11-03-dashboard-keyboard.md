# Walking the Dashboard with the keyboard

2026-11-03. Commit `43c4914`.

## Problem
In the sidebar and the note list the arrow keys move around, but the Dashboard could only be used with the mouse.

## Evidence
The request: from the Dashboard, the right arrow should go to the first item, up should reach the search bar, down should go to the next item, and down from the search bar should reach the first item.

## Options
1. Mark the highlighted row only on screen. Rejected alone: it does nothing, so Return opens the highlighted item's note as well.
2. Let typing while an item is highlighted jump back to the search box. Not built for now; written in `BACKLOG.md` instead, with an open question about what Esc should do there.

## Decision
Keyboard focus moves between the search box and the items. The items are walked in the order they appear on the page: Overdue, Today, Next 14 Days, To-do, then Completed when it is expanded. A flat list of the visible items makes up and down a matter of moving an index.

## Result
A UI test presses right, Return, then up and down, and checks that the note opens and the search box takes the typing. I did not try the case with Completed expanded.

## Cost and next
Moving down from the search box takes focus off it, so refining a search while walking the results needs a trip back up. That is the backlog item.
