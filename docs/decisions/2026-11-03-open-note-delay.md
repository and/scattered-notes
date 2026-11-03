# Opening a note from the Dashboard felt slow

2026-11-03. Commit `43c4914`.

## Problem
Clicking a to-do on the Dashboard paused before the note opened. Opening a note from the note list did not.

## Evidence
I guessed the cause first, then measured. Timing code logged the milliseconds from the click until the main thread was idle again, over several clicks each way:

| Where the click was | Idle after the click |
|---|---|
| A note in the note list | about 112 to 138 ms |
| A to-do on the Dashboard | about 315 to 440 ms |

A profiler sample of the app showed no single slow function. The time was spread across SwiftUI layout work.

## Options
1. Keep the Dashboard's two-column layout and make the rebuild cheaper (cache the sidebar counts, build the list lazily). Rejected: the layout swap would still happen, so some delay would stay.
2. Always use three columns (sidebar, note list, detail) and show the Dashboard in the detail column. Chosen.
3. Measure first. Done before choosing, because my first guess ("the layout swap") was only half supported until the comparison.

## Decision
The window now always has three columns. On the Dashboard, the note list is squeezed to zero width and hidden, so the Dashboard still looks full width. Opening a note then only fills the detail pane, the same as opening from the list.

## Result
The comparison showed the layout swap cost about 200 ms. After the change I did not re-measure; I expect about 120 ms, the list-click figure. A UI test checks that the list is hidden on the Dashboard and returns elsewhere.

## Cost and next
The list view stays in the window while hidden. Some keyboard paths now needed care, such as the right arrow from the sidebar. Next step: re-measure to confirm the number.
