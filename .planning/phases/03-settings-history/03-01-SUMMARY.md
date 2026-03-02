---
phase: 03-settings-history
plan: 01
subsystem: database
tags: [grdb, swift6, swiftui, observable, fseventswatcher, migration]

# Dependency graph
requires:
  - phase: 02-app-shell-triggers
    provides: BackupCoordinator single-watcher model, FSEventsWatcher, AbletonPrefsReader, AppDatabase

provides:
  - WatchFolder GRDB model (id, path, name, addedAt, lastTriggeredAt) in BackupEngine module
  - v2_watch_folders GRDB migration in Schema.swift
  - BackupCoordinator.watchFolders: [WatchFolder] as @Observable state
  - BackupCoordinator.database: AppDatabase? accessor for GRDB ValueObservation
  - BackupCoordinator.addWatchFolder(url:) - inserts DB row, starts FSEventsWatcher
  - BackupCoordinator.removeWatchFolder(_:) - stops watcher, removes DB row
  - Bootstrap seeding: empty watchFolder table auto-populated from AbletonPrefsReader on first launch
  - lastTriggeredAt updated in DB on each .als change event

affects: [03-02-watch-folders-ui, 03-03-destinations-ui, 03-04-general-settings-ui, 03-05-history-view]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "DB-backed watcher dictionary: [String: FSEventsWatcher] keyed by path"
    - "Bootstrap pattern: count == 0 check → seed from AbletonPrefsReader, non-fatal if discovery fails"
    - "addWatchFolder/removeWatchFolder: DB write then in-memory state update pattern"
    - "lastTriggeredAt persistence: async DB save in handleALSChange after in-memory update"

key-files:
  created:
    - Sources/BackupEngine/Persistence/Models/WatchFolder.swift
  modified:
    - Sources/BackupEngine/Persistence/Schema.swift
    - AbletonBackup/BackupCoordinator.swift

key-decisions:
  - "GRDB import added to BackupCoordinator.swift (app target) to access Column type for fetchAll ordering"
  - "Bootstrap seeding is non-fatal: if AbletonPrefsReader returns nil, status=error but setup() continues so scheduler still starts"
  - "startWatcher(for:) has idempotency guard — watchers[url.path] == nil check prevents duplicate watchers"
  - "removeWatchFolder stops watcher BEFORE DB delete to prevent stray events during deletion"
  - "bootstrapProjectID/bootstrapDestID retained in Phase 3 — runBackup still uses Phase 2 single-project job logic; multi-destination is Phase 4+"

patterns-established:
  - "Watch folder add: DB write → in-memory append → startWatcher (in that order)"
  - "Watch folder remove: stop watcher first → DB delete → in-memory removeAll"
  - "lastTriggeredAt: update in-memory array first, then async persist to DB"

requirements-completed: [DISC-02, DISC-03]

# Metrics
duration: 8min
completed: 2026-03-02
---

# Phase 3 Plan 01: WatchFolder Model and Multi-Watcher BackupCoordinator Summary

**WatchFolder GRDB model with v2 migration and BackupCoordinator refactored from single-watcher to DB-backed multi-watcher with observable watchFolders state and add/remove methods**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-02T18:42:09Z
- **Completed:** 2026-03-02T18:50:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created WatchFolder GRDB model with full TableRecord/FetchableRecord/PersistableRecord conformances
- Added v2_watch_folders migration to Schema.swift — creates watchFolder table with UNIQUE path constraint
- Refactored BackupCoordinator from single `FSEventsWatcher?` to `[String: FSEventsWatcher]` dictionary
- Added `watchFolders: [WatchFolder]` as @Observable state — drives WatchFolders pane UI in Plans 02-04
- Added `database: AppDatabase?` computed accessor — enables History view GRDB ValueObservation
- Implemented `addWatchFolder(url:)` and `removeWatchFolder(_:)` with proper DB + watcher lifecycle management
- Bootstrap logic seeds watchFolder table from AbletonPrefsReader on first launch (empty DB)
- `handleALSChange` now updates `lastTriggeredAt` in both memory and DB on each .als file event

## Task Commits

Each task was committed atomically:

1. **Task 1: WatchFolder GRDB model and v2 migration** - `e502db9` (feat)
2. **Task 2: Refactor BackupCoordinator to multi-watcher DB-backed model** - `ac53bd6` (feat)

## Files Created/Modified

- `Sources/BackupEngine/Persistence/Models/WatchFolder.swift` - WatchFolder struct with GRDB conformances (id, path, name, addedAt, lastTriggeredAt)
- `Sources/BackupEngine/Persistence/Schema.swift` - Added v2_watch_folders migration after v1_initial
- `AbletonBackup/BackupCoordinator.swift` - Full refactor: multi-watcher, watchFolders observable state, add/remove methods, DB bootstrap

## Decisions Made

- **GRDB import in BackupCoordinator**: The `Column` type for `fetchAll` ordering required importing GRDB directly into the app target. This is consistent with BackupEngine module usage patterns.
- **Non-fatal bootstrap**: If `AbletonPrefsReader.discoverProjectsFolder()` returns nil on first launch, `status = .error(...)` is set but `setup()` continues — same resilience pattern established in Phase 2 (02-07 decision).
- **Idempotent startWatcher**: Guard `watchers[url.path] == nil` prevents duplicate watchers when called from both bootstrap and `addWatchFolder`.
- **Remove-then-delete order**: `removeWatchFolder` stops the FSEventsWatcher before the DB delete to avoid processing stray filesystem events during the removal window.
- **Phase 2 bootstrap logic preserved**: `bootstrapProjectID` and `bootstrapDestID` stay in `runBackup` — Phase 3 only adds multi-watcher infrastructure; multi-destination job dispatch is Phase 4+.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added GRDB import to BackupCoordinator.swift**
- **Found during:** Task 2 (BackupCoordinator refactor)
- **Issue:** `Column` type used in `WatchFolder.order(Column("addedAt").asc).fetchAll(db)` is defined in GRDB framework but was not imported — build error `cannot find 'Column' in scope`
- **Fix:** Added `import GRDB` to BackupCoordinator.swift imports
- **Files modified:** AbletonBackup/BackupCoordinator.swift
- **Verification:** BUILD SUCCEEDED after adding import
- **Committed in:** ac53bd6 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking import)
**Impact on plan:** Trivial one-line fix. No scope creep.

## Issues Encountered

None beyond the GRDB import above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- WatchFolder model and migration are ready — Phase 3 Plans 02-04 can build Settings UI against `watchFolders` and `addWatchFolder`/`removeWatchFolder`
- `database: AppDatabase?` accessor ready for Plan 05 History view GRDB ValueObservation
- All plan contracts fulfilled: `watchFolders: [WatchFolder]`, `database: AppDatabase?`, `addWatchFolder(url:)`, `removeWatchFolder(_:)`
- BUILD SUCCEEDED with no Swift 6 strict concurrency errors

---
*Phase: 03-settings-history*
*Completed: 2026-03-02*
