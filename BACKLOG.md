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

## Done

_Nothing yet._
