# Dayline working memory

## Current contract

- One recurring timeline. Tasks and completion persist across midnight.
- `TimelineStore` owns task/settings state and JSON persistence.
- `axisPanel` / `AxisRecallView` owns band input. Single click changes pin mode;
  double click toggles controls. Keep its front order and return-target clearance.
- Axis and task-time clicks share `GuardedClickArbiter`.
- One native scroll view produces `TimelineProjection`. Detached task windows
  use that measurement; `focusMinute` is only a scroll target.
- Hover does not resize windows. Expanded titles resize only their task panel.
- Each task has one drag gesture and the controller one drag session. Preview
  and commit share Store placement. Automatic docking pauses during dragging.
- One clock timer refreshes time; one cancellable work item handles inactivity.
- Native Liquid Glass and the shared panel factory own appearance and Spaces.
- CLI/MCP execute through the running app; neither writes timeline state.

Read `docs/DEVELOPMENT.md` for source owners and build/test commands.

## Alignment — 2026-10-03 review and simplification

Intent: simplify the existing implementation, repair normal interaction defects,
and make the project easy for another agent to continue. Preserve the contract
above and change each behavior at its existing owner.

Existing chains reviewed: Store persistence and range mutation; CLI/MCP → URL →
AppDelegate → AutomationController → Store; clock/delay publishers → controller
follow; measured scroll → timeline and detached panels; Settings and title editing.

CLI help alignment: `help`, `--help`, and `-h` must print usage and exit successfully without entering the URL client. Replace the existing help-as-error switch case with one direct entry-point branch; preserve request commands. Verify all three spellings and MCP metadata in the final smoke test.

Implemented:

- Consolidated time parsing and Store restoration; removed redundant checks.
- Range changes save once. Removed RootView's duplicate focus seeding.
- Auto-return consumes emitted delay/date values; dragging suspends follow.
- Return-target visibility uses measured scroll geometry; queued editor focus
  follows the current editing ID.
- Settings scroll within a 600-point viewport. Quitting commits the active edit.
- Automation returns reusable extended-hour deadline strings across midnight.
- Added one check command and a configurable package output path. The check
  command also runs from an exported source folder without Git metadata.
- Added one development guide, verified by a fresh-context agent handoff.

Changed owners: `AutomationController`, `TimelineStore`, `FloatingPanel`,
`TimelineView`, `TodoPillView`, `RootView`, `DaylineApp`, MCP copy/adapter,
related tests, build/check scripts, README and development guide.

Verification: `./scripts/check.sh` passed all 46 tests, release build, CLI help
(all three spellings), and MCP initialize/tools-list/ping. A separate
`git diff --check` passed.
`./scripts/build-app.sh release` produced 0.2.8 (54); strict deep signature
verification passed for the repository package and its delivered copy at
`/Users/alexwhite/Documents/Codex/2026-10-03/bang/outputs/今日.app`.
The delivered CLI/MCP metadata smoke passed. All three executable hashes match
between packages. Dayline SHA-256:
`3ac48b25cc1ed98dfe96e6418ef8c967831319425795801540a85bb6c2b965bc`.
Physical trackpad and Spaces behavior remains unverified. This pass did not
install or launch the app; `/Applications/今日.app` remains build 53.


## Alignment — 2026-10-03 explicit return-to-now action

Intent: clicking the orange target must return the actual current minute to the
saved anchor even when `focusMinute` already equals its rounded quarter, including
97% docking and fractional scroll. Existing button → `seedFocus` reassigns the same
ID and can do nothing; the rounding can itself leave the current minute offscreen.
Route the button through RootView to the existing controller scroll owner. Share
its direct clip-view target-to-anchor operation with inactivity docking, using a
clamped fractional current minute independently of inactivity mode. Keep startup
ID seeding, one measured projection, one scroll view, and existing event ownership.
Verify the shared operation with an isolated native scroll view, including repeat
invocation; final verification is recorded above.

Implemented in `TimelineView`, `RootView`, and `FloatingPanel`: the explicit button
now supplies clamped fractional now to the same direct native scroll operation as
automatic docking. Removed its repeated quarter-ID assignment; startup seeding is
unchanged. The button restarts the existing inactivity countdown so first-todo mode
does not immediately override an explicit return-to-now action. No scroll view,
offset state, timer, or gesture was added. Removed the scheduler's duplicate delay
clamp. The native-scroll regression covers fractional time at the 97% anchor,
unchanged focus ID and a repeated return after partial scrolling.
