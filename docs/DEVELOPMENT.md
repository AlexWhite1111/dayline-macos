# Dayline development

Start with `AGENTS.md` and `DAYLINE_WORKING_MEMORY.md` for current change
constraints and verification status. `README.md` describes the product and
integration setup. This file maps the implementation and safe development path;
historical build logs are not evidence for the current checkout.

## Build and check

Requires macOS 26, Python 3, and a Swift toolchain with the macOS 26 SDK.
`Package.swift` uses Swift tools 6.0 with Swift 5 language mode. There are no
third-party package dependencies. Run commands from the repository root:

```sh
./scripts/check.sh
./scripts/build-app.sh release work/delivery-verification/今日.app
```

The check runs tests, a release build and CLI/MCP protocol smoke checks. It does not launch the app or send valid commands to live tasks.
For a focused iteration, use `swift test --filter TimelineStoreCurrentTaskTests`
or the relevant test class, followed by the full check before handoff.

Packaging defaults to `outputs/今日.app` when its second argument is omitted.
Use `work/delivery-verification/今日.app` during review to preserve the delivered
package. The script replaces its output, copies the three executables/resources,
then signs and verifies the bundle. It does not install or launch.
`Resources/Info.plist` owns bundle identity. Builds use the local architecture;
ad hoc signing supports local use, not notarized distribution. Matching version
numbers do not imply matching binaries.
Regenerate the checked-in icon with `scripts/make-icon.sh` only when changing it.

## Where to change code

| Owner | Responsibility |
| --- | --- |
| `Sources/Dayline/DaylineApp.swift` | App lifecycle, one Store/controller graph, URL dispatch, editing commit on deactivation/quit. |
| `Sources/Dayline/TimelineStore.swift` | Only task/settings state owner and JSON writer; range, collision placement, editing, cyclic current-task selection. |
| `Sources/Dayline/Domain.swift` | Codable models, clock/range conventions, shared layout formulas and measured `TimelineProjection`. |
| `Sources/Dayline/FloatingPanel.swift` | Main/axis/task windows, hit ownership, levels, docking, drag session, overlay scheduling, scroll forwarding and inactivity return. |
| `Sources/Dayline/TimelineView.swift` | One SwiftUI scroll view, scale, measured projection, orange return target and user-scroll reporting. |
| `Sources/Dayline/TodoPillView.swift` | One pill renderer/editor/drag gesture; AppKit time menu interaction. |
| `Sources/Dayline/RootView.swift`, `Glass.swift` | Rail/settings and one native Liquid Glass modifier. Login-item status belongs to `SMAppService`, not saved JSON. |
| `Sources/Dayline/AutomationController.swift` | Map automation actions to Store operations and serialize results. |
| `Sources/DaylineAutomation/DaylineAutomation.swift` | Shared request/response schema, URL encoding/decoding, response files and post-launch response timeout. |
| `Sources/DaylineCLI/main.swift`, `Sources/DaylineMCP/main.swift` | Terminal argument and stdio JSON-RPC adapters; neither writes timeline state. |

## Execution contracts

- One recurring timeline; task positions are deadlines in 15-minute slots.
  Crossing midnight does not clear tasks or completion. `currentTask(at:)`
  selects the next incomplete task, wrapping to the first when necessary.
- The narrow band routes `AxisRecallView` → controller → existing `NSScrollView`.
  Its single click toggles pin mode; double click toggles the rail. Axis and time
  controls share `GuardedClickArbiter`. Keep the axis ahead of the main window and
  preserve the orange return target's hit clearance after every rail transition.
- Scroll geometry produces one measured `TimelineProjection` with its matching
  scale. Task panels and return-target visibility consume that measurement;
  `focusMinute` is a scroll target, not a continuous screen-position measurement.
- Collection changes use coalesced reconciliation; scrolling updates positions.
  Hover must not resize windows. Title expansion resizes only its task panel.
  Drag preview and commit use Store placement rules; follow suspends during drag.
- Combine `@Published` emits before assignment. Use the emitted value or defer
  Store reads; reading the property immediately inside its sink may use old state.
- Inactivity follows `observeLayoutInputs` → `configureAutoReturn` →
  `scheduleAutoReturn` (one work item); `registerTimelineInteraction` restarts it.
  Active follow uses the Store's existing `clockTimer` ticks.
- Store owns slot snapping, collision placement and range adjustment.
- UI/CLI/MCP share one Store. CLI/MCP → `dayline://automation/v1` →
  `AppDelegate` → `AutomationController` → `TimelineStore`. The ten MCP tools are listed in README; list before planning,
  use its `now`/`nextTodoID` instead of recomputing the cyclic rule, and treat
  `time` as deadline. `TimelinePanelControlling` is automation's only window-state
  path (show, control rail).

## Safe tests and handoff

Live data is `~/Library/Application Support/Dayline/timeline.json`. Do not use
`TimelineStore()` in tests: pass a fresh temporary `stateURL` and
`startsTimer: false`, and clean up only that test directory. Existing persistence
and automation tests show this pattern. Controller tests can execute requests
against that Store directly without opening a URL. A real CLI action, including
`list`, can launch the registered installed app; use the protocol smoke script
for isolated adapter checks. Starting the app is not an isolated test fixture.

Before handing off, record changed owners, removed paths, checks run and remaining
uncertainty in the current working-memory entry. Review `git diff` and
`git status --short`. Keep source, packaged bundle and installed app identities
separate; a source check is not an installed-app test.

For UI changes, manually repeat band scroll / single / double click after rail
hiding; first drag, hover, edit-focus/quit save; time menu versus double-click
mode; size/edge-fade alignment; delayed follow and drag interruption; both dock
edges/screens and Space changes. Record actual observations separately from tests.
