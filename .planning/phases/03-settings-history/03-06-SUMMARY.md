---
phase: 03-settings-history
plan: 06
subsystem: ui
tags: [swiftui, scheduler, appstorage, userdefaults, scheduler-interval]

# Dependency graph
requires:
  - phase: 03-settings-history
    provides: GeneralSettingsView Backup section scaffold and BackupCoordinator with SchedulerTask
  - phase: 02-app-shell-triggers
    provides: SchedulerTask with start(interval:) / stop() API

provides:
  - BackupCoordinator.updateScheduleInterval(_:) method that restarts SchedulerTask with a new Duration
  - BackupCoordinator.setup() reads scheduleIntervalSeconds from UserDefaults on startup
  - GeneralSettingsView Backup section with schedule interval Picker (30 min / 1 hr / 2 hr / 4 hr)
  - Picker persists interval via @AppStorage and calls coordinator.updateScheduleInterval immediately on change

affects: [04-destinations, phase-3-gap-closure]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@AppStorage for schedule interval backed by UserDefaults.standard.integer(forKey:) in BackupCoordinator"
    - "updateScheduleInterval(_:) restarts running SchedulerTask — same start() call replaces previous task"

key-files:
  created: []
  modified:
    - AbletonBackup/BackupCoordinator.swift
    - AbletonBackup/Views/Settings/GeneralSettingsView.swift

key-decisions:
  - "scheduleIntervalSeconds stored as Int (seconds) in UserDefaults — @AppStorage(\"scheduleIntervalSeconds\") in view, UserDefaults.standard.integer(forKey:) in coordinator, consistent with autoBackupEnabled pattern"
  - "updateScheduleInterval calls scheduler.start() directly — SchedulerTask.start() cancels any existing task before starting a new one, so no explicit stop() needed"
  - "Default 3600s fallback when storedSeconds == 0 (key not yet written) — matches SchedulerTask.defaultInterval"

patterns-established:
  - "Coordinator-side interval bootstrap: read UserDefaults in setup(), not hardcoded default"
  - "View-side scheduler wiring: @AppStorage + onChange + coordinator method call"

requirements-completed: [APP-04]

# Metrics
duration: 50min
completed: 2026-03-03
---

# Phase 3 Plan 06: Schedule Interval Configuration Summary

**User-configurable backup schedule (30 min / 1 hr / 2 hr / 4 hr) persisted to UserDefaults via @AppStorage, wired to a live scheduler restart through BackupCoordinator.updateScheduleInterval(_:)**

## Performance

- **Duration:** 50 min
- **Started:** 2026-03-03T14:21:16Z
- **Completed:** 2026-03-03T15:11:23Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- BackupCoordinator.setup() now reads `scheduleIntervalSeconds` from UserDefaults on startup (fallback to 3600s when key absent), replacing the hardcoded SchedulerTask.defaultInterval call
- Added `updateScheduleInterval(_:)` method to BackupCoordinator under a new `// MARK: - Schedule Management (APP-04)` section — restarts the scheduler immediately with the new Duration
- GeneralSettingsView Backup section gains a "Backup schedule" Picker with four options (Every 30 minutes / Every hour / Every 2 hours / Every 4 hours) backed by `@AppStorage("scheduleIntervalSeconds")`
- Picker's `.onChange` calls `coordinator.updateScheduleInterval(_:)` so the running scheduler is restarted instantly without requiring an app relaunch

## Task Commits

Each task was committed atomically:

1. **Task 1: Add updateScheduleInterval(_:) to BackupCoordinator and read stored interval on startup** - `9673c64` (feat)
2. **Task 2: Add schedule interval Picker to GeneralSettingsView** - `4ce56a7` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified
- `AbletonBackup/BackupCoordinator.swift` - Added UserDefaults read for scheduleIntervalSeconds in setup(); added Schedule Management section with updateScheduleInterval(_:)
- `AbletonBackup/Views/Settings/GeneralSettingsView.swift` - Added @AppStorage("scheduleIntervalSeconds") property and Backup schedule Picker with 4 interval options

## Decisions Made
- `scheduleIntervalSeconds` stored as `Int` (seconds) in UserDefaults — `@AppStorage("scheduleIntervalSeconds")` in view, `UserDefaults.standard.integer(forKey:)` in coordinator, consistent with `autoBackupEnabled` pattern already in the codebase
- `updateScheduleInterval` calls `scheduler.start()` directly — `SchedulerTask.start()` cancels any existing task before starting a new one, so no explicit `stop()` call is needed before restart
- Default 3600s fallback when `storedSeconds == 0` (key not yet written on first launch) matches `SchedulerTask.defaultInterval` — no behavior change for existing users

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None — both tasks built cleanly on first attempt. No Swift 6 concurrency issues: `updateScheduleInterval` is `@MainActor`-isolated via `BackupCoordinator` class isolation, and SwiftUI `.onChange` runs on the main actor, so the call is safe.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- APP-04 is now fully satisfied: schedule configuration (30 min / 1 hr / 2 hr / 4 hr) is exposed in the Settings window, persists across launches, and restarts the running scheduler immediately
- Phase 3 gap closure is complete — all gap findings from 03-VERIFICATION.md have been addressed
- Ready for Phase 4 (Destinations)

## Self-Check: PASSED

- FOUND: AbletonBackup/BackupCoordinator.swift
- FOUND: AbletonBackup/Views/Settings/GeneralSettingsView.swift
- FOUND: .planning/phases/03-settings-history/03-06-SUMMARY.md
- FOUND commit 9673c64 (Task 1: BackupCoordinator changes)
- FOUND commit 4ce56a7 (Task 2: GeneralSettingsView Picker)
- BUILD SUCCEEDED confirmed twice (after each task)

---
*Phase: 03-settings-history*
*Completed: 2026-03-03*
