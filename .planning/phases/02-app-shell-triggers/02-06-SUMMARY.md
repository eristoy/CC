---
phase: 02-app-shell-triggers
plan: 06
subsystem: infra
tags: [oslog, logging, swift, observability, diagnostics]

# Dependency graph
requires:
  - phase: 02-app-shell-triggers
    provides: BackupCoordinator, NotificationService, FSEventsWatcher, SchedulerTask, BackupEngine wired together

provides:
  - Structured os.log entries in all 5 backup lifecycle components
  - Console.app filter subsystem:com.abletonbackup shows full backup trace
  - Coordinator setup/guard/trigger/success/failure log coverage
  - Notification auth request and delivery logging
  - FSEvents .als change event logging
  - Scheduler fire logging
  - BackupEngine job start/filter/fan-out/verify/complete logging

affects: [03-settings-ui, 04-cloud-destinations, 05-history-ui, 06-git-lfs]

# Tech tracking
tech-stack:
  added: [OSLog (os.Logger via Apple OS ABI — no Package.swift change required)]
  patterns: [subsystem=com.abletonbackup with per-component categories; file-scope private logger for static structs and classes; actor-property logger for actors]

key-files:
  created: []
  modified:
    - Sources/BackupEngine/BackupEngine.swift
    - AbletonBackup/BackupCoordinator.swift
    - AbletonBackup/NotificationService.swift
    - AbletonBackup/FSEventsWatcher.swift
    - AbletonBackup/SchedulerTask.swift

key-decisions:
  - "Logger declared as private actor property in BackupEngine (actor isolation compatible) and as private property in BackupCoordinator class; file-scope private let for static-method structs (NotificationService) and standalone classes (FSEventsWatcher, SchedulerTask)"
  - "FSEventsWatcher.log(path:) nonisolated method added to bridge from C callback context to fsLogger — avoids accessing actor-isolated state from C callback"
  - "updateVersionStatus error logging added inside the helper itself rather than at each call site — DRY, single point for error capture before re-throw"
  - "Logger is Sendable — safe from any Swift 6 concurrency isolation domain without annotation"

patterns-established:
  - "subsystem=com.abletonbackup: all components share subsystem for Console.app filtering; category distinguishes component (BackupEngine, Coordinator, Notifications, FSEvents, Scheduler)"
  - "Privacy: public on all user-visible strings (project names, paths, error messages); default privacy on numeric counts"

requirements-completed: [APP-02, NOTIF-01, NOTIF-02]

# Metrics
duration: 8min
completed: 2026-02-27
---

# Phase 2 Plan 6: os.log Structured Logging Summary

**os.Logger added to all 5 backup lifecycle components (BackupEngine, BackupCoordinator, NotificationService, FSEventsWatcher, SchedulerTask) under subsystem com.abletonbackup for Console.app diagnosis of notification and guard failures**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-27T19:56:07Z
- **Completed:** 2026-02-27T20:04:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added OSLog import and category-specific Logger to all 5 components — zero build errors under Swift 6
- BackupCoordinator now logs every state machine transition: setup start, auth request, DB open path, guard failures (already-running and not-configured), trigger, success, and error
- NotificationService logs auth status check, request skip reason, grant/deny result, and per-notification delivery outcome with error
- FSEventsWatcher logs watch start URL, each .als path detected by the C callback, and stop on deinit
- SchedulerTask logs start with interval, each scheduled fire, and stop
- BackupEngine logs job start with project/destination IDs, incremental filter copy/skip counts, fan-out results, and final versionID/status; updateVersionStatus errors logged before re-throw

## Task Commits

Each task was committed atomically:

1. **Task 1: Add os.log to BackupEngine** - `8c53994` (feat)
2. **Task 2: Add os.log to BackupCoordinator, NotificationService, FSEventsWatcher, SchedulerTask** - `5334047` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `Sources/BackupEngine/BackupEngine.swift` - Added import OSLog, private logger, 5 log call sites + error logging in updateVersionStatus
- `AbletonBackup/BackupCoordinator.swift` - Added import OSLog, private logger property, 9 log call sites across setup() and runBackup()
- `AbletonBackup/NotificationService.swift` - Added import OSLog, file-scope notifLogger, 6 log call sites in auth, send, and post methods
- `AbletonBackup/FSEventsWatcher.swift` - Added import OSLog, file-scope fsLogger, log(path:) nonisolated method, 3 log call sites (init, C callback, deinit)
- `AbletonBackup/SchedulerTask.swift` - Added import OSLog, file-scope schedLogger, 3 log call sites (start, loop fire, stop)

## Decisions Made

- Logger declared as actor property for BackupEngine and class property for BackupCoordinator; file-scope `private let` for static-method struct (NotificationService) and top-level classes (FSEventsWatcher, SchedulerTask) — Logger is Sendable so any isolation domain works.
- `FSEventsWatcher.log(path:)` nonisolated method added as bridge between C callback and fsLogger — direct closure call from C context avoids any actor-isolation issue.
- Error logging placed inside `updateVersionStatus` rather than at each call site — DRY approach, single capture point before error is re-thrown to caller.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. All 5 files compiled under Swift 6 strict concurrency with zero errors on first build attempt.

## User Setup Required

None - no external service configuration required. To view logs, open Console.app and filter by subsystem: `com.abletonbackup`.

## Next Phase Readiness

- All backup lifecycle events are now visible in Console.app — ready to diagnose notification failures (gap 1) and silent guard failures (gap 2) during manual testing
- Logging infrastructure in place for all future phases; new components should follow the same subsystem/category pattern
- Phase 2 gap-closure complete: structured logs enable diagnosis without further code changes

---
*Phase: 02-app-shell-triggers*
*Completed: 2026-02-27*
