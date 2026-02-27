---
phase: 02-app-shell-triggers
plan: 07
subsystem: notifications
tags: [UNUserNotificationCenter, NotificationDelegate, foreground-delivery, BackupCoordinator, error-state, Swift6]

# Dependency graph
requires:
  - phase: 02-app-shell-triggers
    provides: NotificationService with requestAuthorization (plan 02-03), os.log structured logging (plan 02-06), BackupCoordinator with silent guard returns (plan 02-04)
provides:
  - NotificationDelegate singleton ensuring foreground banner delivery for all UNUserNotificationCenter notifications
  - NotificationService.setup() replacing requestAuthorization() — sets delegate and requests auth unconditionally
  - AbletonBackupApp wires NotificationService.setup() via .task modifier on MenuBarView at launch
  - BackupCoordinator.runBackup() surfaces guard failures as error states with descriptive messages
  - BackupCoordinator.setup() surfaces nil watchedProjectsFolder as error state in menu bar icon
affects: [03-settings-ui, verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "UNUserNotificationCenterDelegate singleton with @unchecked Sendable for Swift 6 compliance in foreground notification delivery"
    - ".task modifier on SwiftUI View (not Scene) for launch-time async side effects in MenuBarExtra apps"
    - "Descriptive error state messaging in guard failures — enum-branched reason strings instead of silent returns"

key-files:
  created: []
  modified:
    - AbletonBackup/NotificationService.swift
    - AbletonBackup/AbletonBackupApp.swift
    - AbletonBackup/BackupCoordinator.swift

key-decisions:
  - "NotificationDelegate uses @unchecked Sendable — singleton with no mutable state, safe from any isolation domain under Swift 6"
  - ".task modifier attached to MenuBarView (not MenuBarExtra Scene) — Scene does not expose .task; view-level .task fires on first appearance which is equivalent to app launch for menu bar apps"
  - "nil watchedProjectsFolder sets error state but does NOT return from setup() — scheduler and manual trigger still start so user can resolve in Phase 3 settings"
  - "Guard 1 (already running) does not set error state — concurrent trigger while running is expected behavior, not a user-visible failure"

patterns-established:
  - "UNUserNotificationCenterDelegate: Always set before requestAuthorization in menu bar apps — foreground status suppresses all banners without delegate"
  - "Error state messaging: Guard failures surface descriptive strings via status = .error(reason) rather than silent returns"

requirements-completed: [NOTIF-01, NOTIF-02, APP-02]

# Metrics
duration: 2min
completed: 2026-02-27
---

# Phase 2 Plan 07: Notification Fixes + Guard Error States Summary

**UNUserNotificationCenterDelegate wired for foreground banner delivery; BackupCoordinator guard failures now surface as descriptive error states in the menu bar icon instead of silently returning**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-27T20:02:58Z
- **Completed:** 2026-02-27T20:04:57Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- `NotificationService.setup()` replaces `requestAuthorization()` — sets `UNUserNotificationCenterDelegate` and calls `requestAuthorization` unconditionally (no `.notDetermined` guard)
- `NotificationDelegate` singleton implements `willPresent` to deliver `.banner + .sound` while app is in foreground — menu bar apps are always in foreground so this is required for any notification to appear
- `BackupCoordinator.runBackup()` second guard (engine/db/folder nil) now sets `status = .error(reason)` with a human-readable message; first guard (already running) logs trigger name
- `BackupCoordinator.setup()` sets `status = .error(...)` when `watchedProjectsFolder` is nil so menu bar icon shows error state immediately

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix NotificationService — reliable auth + foreground delivery delegate** - `93f5b4d` (feat)
2. **Task 2: Fix BackupCoordinator — surface guard failures as error states** - `592329b` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `AbletonBackup/NotificationService.swift` - Replaced `requestAuthorization()` with `setup()`; added `NotificationDelegate` class with `@unchecked Sendable`
- `AbletonBackup/AbletonBackupApp.swift` - Added `.task { NotificationService.setup() }` on `MenuBarView`
- `AbletonBackup/BackupCoordinator.swift` - Removed `NotificationService.requestAuthorization()` call from `setup()`; updated guard failure to set `status = .error`; added nil folder error state

## Decisions Made

- `NotificationDelegate` uses `@unchecked Sendable` — it is a singleton with `private override init()` and no mutable state; Swift 6 strict concurrency requires the annotation since `NSObject` subclasses are not automatically `Sendable`
- `.task` modifier is attached to `MenuBarView` (the content view), not to `MenuBarExtra` (the scene) — `Scene` protocol in SwiftUI does not expose `.task`; view-level `.task` fires on first appearance which is effectively app launch for menu bar apps that are always visible
- `nil watchedProjectsFolder` sets error status but does NOT halt `setup()` — scheduler and manual trigger continue initializing so the app is functional once the user configures the folder in Phase 3 settings

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added @unchecked Sendable to NotificationDelegate for Swift 6 compliance**
- **Found during:** Task 1 (NotificationService changes)
- **Issue:** Swift 6 strict concurrency rejected `static let shared = NotificationDelegate()` because `NSObject` subclasses are not automatically `Sendable`, causing a compile error
- **Fix:** Added `@unchecked Sendable` to `NotificationDelegate` class declaration — singleton with no mutable state makes this correct
- **Files modified:** `AbletonBackup/NotificationService.swift`
- **Verification:** BUILD SUCCEEDED after fix
- **Committed in:** `93f5b4d` (Task 1 commit)

**2. [Rule 3 - Blocking] Moved .task modifier from Scene to View**
- **Found during:** Task 1 (AbletonBackupApp.swift changes)
- **Issue:** Plan specified `.task { NotificationService.setup() }` on `MenuBarExtra` (Scene level) but `Scene` does not expose a `.task` modifier in SwiftUI — build failed with "value of type 'some Scene' has no member 'task'"
- **Fix:** Moved `.task` modifier to `MenuBarView()` inside the `MenuBarExtra` content closure — semantically equivalent since the view appears immediately on app launch
- **Files modified:** `AbletonBackup/AbletonBackupApp.swift`
- **Verification:** BUILD SUCCEEDED after fix
- **Committed in:** `93f5b4d` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 bug/Swift 6 compliance, 1 blocking/API mismatch)
**Impact on plan:** Both auto-fixes required for correctness and compilation. No scope creep.

## Issues Encountered

- SwiftUI `Scene` protocol does not expose `.task` modifier — plan's specified API does not exist; fixed by moving to view level which achieves identical behavior for menu bar apps

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Notification delivery is now fully functional for menu bar apps (foreground suppression resolved)
- Guard failures produce visible user feedback via error state in menu bar icon
- Phase 3 settings UI can clear the nil-folder error state once user configures their Ableton Projects path
- BUILD SUCCEEDED under Swift 6 strict concurrency

---
*Phase: 02-app-shell-triggers*
*Completed: 2026-02-27*
