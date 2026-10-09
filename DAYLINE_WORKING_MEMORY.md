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

## Alignment — 2026-10-03 right-dock capsule spacing

Intent: right-docked capsules and their drag connector should mirror the accepted
left-dock geometry. `FloatingItemGeometry.taskFrame` currently uses an 8-point
right inset versus an 18-point left inset, producing a 1-point right axis gap for
an 11-point connector and overlapping the axis input lane by 2 points. Use the
existing `pillInset` on both sides and remove unused `pillOuterInset`. Preserve
axis/window owners, all gestures, native glass, task sizes and vertical projection.
Add a mirror/connector/hit-lane regression over compact and expanded widths; physical
right-dock acceptance and build-55 packaging remain separate from source tests.

## Alignment — 2026-10-03 native editing and task accessibility

Intent: restore standard macOS editing shortcuts and make title editing/time
selection discoverable to accessibility users. Existing AppDelegate menu owns
keyboard command routing; TodoPillView.beginEditing and TimeMenuInteraction's
native menu remain the sole edit/menu actions. Add an Edit menu using responder
chain selectors, title edit accessibility action, and native time-control AX
role/value/press plus a concise pointer hint. Preserve physical double-click
arbitration, task focus, layout, and persistence; add no gesture or state owner.
Verification needed: build/tests and isolated native menu dispatch; real installed
text entry and VoiceOver acceptance remain separate from source checks.

Implemented only the right-side `taskFrame` inset replacement in `Domain.swift`
and removed `pillOuterInset`. The new geometry test first reproduced the 1-point
gap and input-lane intersection at three widths, then passed after the fix.
`swift test --filter ControlRailGeometryTests` passed all 12 tests with no warnings
or failures; `git diff --check` passed. Right-docked capsules now move 10 points
away from the axis, matching left docking and the existing 11-point connector.
This source check did not package, install, launch, or mutate the live app; parent
owns aggregate checks and real UI verification for the next delivery.

Native editing/accessibility implementation: changed `DaylineApp.swift` and
`TodoPillView.swift`. Standard Edit commands have nil targets so AppKit selects the
current responder; redo uses Command-Shift-Z. Title AX edit calls `beginEditing`.
The existing native time view exposes a popup-button role, absolute deadline value,
and press action that invokes its existing menu; its decorative text is AX-hidden.
Added short title/time pointer hints. No new gesture, focus state, or menu renderer.
`swift build` and `git diff --check` passed. An isolated native menu fixture verified
all six responder-chain selectors and redo modifiers without clipboard or live-app
access. Actual installed keyboard/VoiceOver behavior remains for parent UI review.

## Alignment — 2026-10-03 task entry and control clarity

New-task editing must follow the collision-resolved deadline into view. RootView
will set its existing focusMinute to the created item before setting editingID.
Keep Store placement and the single timeline scroll binding. Label the size slider
and give the existing edge-handle click an accessibility action. Preserve layout,
physical drag and saved preferences. Verify build and the native review fixture.

Build 54 installation: committed as e785976, tagged v0.2.8-build54, installed and
launched from /Applications/今日.app. All three installed binaries match the package;
strict signature verification passed. Build 53 is retained in work/install-build54.

## Alignment — 2026-10-09 refactor and save coalescing (branch refactor/cleanup-build55)

Intent: remove repeated range/clock plumbing, stop per-keystroke disk writes, fix
an automation crash and a range-shrink collision. Owners unchanged.

- Automation: update/set-completed/delete with an unknown UUID now return
  `ok: false` ("找不到这个待办") instead of force-unwrapping and crashing the app.
- Store saves are coalesced: `didSet` schedules one write 0.4 s after the last
  change; `persist()` writes immediately and `applicationWillTerminate` calls it.
  Removed the `savesChanges` toggle inside `setTimelineRange`.
- Range shrink places tasks through Store collision rules: in-range tasks keep
  slots, farthest outliers claim edge slots first so relative order survives.
- Store helpers `currentMinute`, `nextTask`, `itemsByDeadline`, `minuteFraction(at:)`,
  `quarter(atOrAfter:)`, `clampToRange` replace repeated start/end plumbing.
  `TimelineStore.unmeasuredProjection` is the single pre-measurement projection
  (was duplicated in TimelineView and FloatingPanel). Restore defaults come from
  the property declarations.
- Scroll indicators hidden with `.scrollIndicators(.never)`; the controller no
  longer mutates `hasVerticalScroller`.
- `GuardedClickArbiter`, `AxisRecallView`, `WindowDragSurface` moved unchanged to
  `InputViews.swift`.
- Settings popover opens toward the screen interior (`arrowEdge` by dock edge).

Verification: `./scripts/check.sh` passed (50 tests incl. 3 new: unknown-ID
automation, range-shrink order, burst save). Not packaged/installed; popover
arrow, scroll-indicator hiding and quit-save need installed-app observation.
Deferred: auto-return sink merge, single owner for drag preview minute.

Build 55 installation: CFBundleVersion 55 packaged to outputs/今日.app, installed to
/Applications/今日.app and launched. Strict deep signature verified; all three
installed binaries match the package. Build 54 and pre-install data snapshots are in
work/install-build55/. timeline.json hash unchanged across quit/install/launch;
read-only `dayline list` succeeded against the running build.

## Alignment — 2026-10-09 interaction fixes (groups A and B of the UI critique)

Intent, decided with the user: Esc cancels a title edit (restores the original; a
new empty task is removed). Deletion offers an inline undo chip at the task's slot
for a few seconds — ⌘Z cannot reach a non-activating panel reliably. Auto-return
and active follow pause while a title is edited and restart when editing ends.
Drag preview snaps to the nearest quarter (new tasks still round up). When no free
slot exists, adding fails (beep / automation error) and range shrinking that cannot
fit all tasks is refused. Hour ticks show faint hour numerals in the axis-to-pill
gap. "Return to now" keeps following now until the next manual scroll; its dot
shows only when now is more than one slot outside the viewport and inside the
range. Time menu labels next-day items with 次日. A moved task (time menu) is
scrolled into view. Overdue incomplete tasks stay unchanged (cyclic timeline).
Owners: Store (editing, undo record, placement), FloatingPanelController (auto-
return, follow-now), TimelineView (labels, return dot, undo chip), TodoPillView.

Implemented as aligned above. Store: `editingID` snapshots the original title;
`cancelEditing` (Esc) restores it; `commitEditing` deletes an emptied task after
restoring its old title so undo brings it back; `recentlyDeleted` + `undoDelete`
(5 s, titled tasks only); `hasFreeSlot`; `setTimelineRange` returns false when the
range cannot hold every task; `availableQuarter` returns nil when full; drag uses
nearest-quarter snapping. Controller: `followsNow`, editing restarts/pauses the
inactivity countdown, auto paths skip while editing. TimelineView: return dot needs
now in range and more than one slot outside; undo chip at the deleted slot; hour
numerals only on hours without a task. Time menu uses `displayRangeTime`; choosing
a time scrolls `focusMinute` to the placed task.

Verification: `./scripts/check.sh` passed, 55 tests (5 new store tests, 2 updated
return-dot tests). Isolated critique fixture (work/ui-critique, own state file)
rendered numerals in dark mode, the undo chip at the deleted slot, and no return dot
when now sits at the top. Real clicks, Esc, drag feel and undo-chip clicking were
not exercised; computer-use cannot target accessory apps.
