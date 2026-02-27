---
phase: 02-app-shell-triggers
plan: "04"
subsystem: ui
tags: [swift, swiftui, fsevents, grdb, notifications, smappservice, menubarextra]

# Dependency graph
requires:
  - phase: 02-app-shell-triggers/02-01
    provides: BackupCoordinator skeleton, AbletonBackupApp entry point, MenuBarView placeholder
  - phase: 02-app-shell-triggers/02-02
    provides: FSEventsWatcher (ALS file change detection), AbletonPrefsReader (project folder discovery)
  - phase: 02-app-shell-triggers/02-03
    provides: NotificationService (success/failure banners), SchedulerTask (periodic backup), LoginItemManager (SMAppService)
  - phase: 01-backup-engine
    provides: BackupEngine actor, AppDatabase (GRDB), BackupJob, Project, DestinationConfig, LocalDestinationAdapter
provides:
  - BackupCoordinator: complete @Observable @MainActor orchestrator wiring all Phase 2 components
  - BackupStatus: idle/running/error enum with SF Symbol names (Equatable)
  - BackupTrigger: fsEvent/scheduled/manual enum
  - MenuBarView: full menu with status, last backup time, Back Up Now, Launch at Login, Quit
  - End-to-end flow: ALS save -> FSEvents -> BackupCoordinator -> BackupEngine -> Notification
affects:
  - 03-settings-ui
  - All future phases that extend BackupCoordinator

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@Observable @MainActor class for SwiftUI state binding in MenuBarExtra"
    - "FSEvents callback bridged to @MainActor via Task { @MainActor [weak self] in ... }"
    - "BackupEngine initialized at setup() time with bootstrap adapter (adapters field is private)"
    - "Bootstrap pattern: Phase 2 uses single hardcoded project/destination; Phase 3 replaces with settings UI"
    - "Idempotent GRDB upserts (save() call) for bootstrap project and destination across app launches"
    - "guard case .idle = status else { return } for coordinator-level concurrency deduplication"

key-files:
  created: []
  modified:
    - AbletonBackup/BackupCoordinator.swift
    - AbletonBackup/Views/MenuBarView.swift
    - AbletonBackup/AbletonBackupApp.swift

key-decisions:
  - "BackupEngine.adapters is private — LocalDestinationAdapter must be passed at init time, not added later; addAdapter extension approach from plan rejected"
  - "Project uses path: String (not rootURL: URL); DestinationConfig uses name: String, rootPath: String, type: DestinationType (enum); createdAt: Date required — actual Phase 1 schema differs from plan interfaces"
  - "BackupStatus and BackupTrigger made internal (not public) — app target, not a library; LoginItemManager is internal so coordinator cannot be public"
  - "BackupStatus: Equatable conformance added inline (not as separate extension) to support .disabled(coordinator.status == .running) in MenuBarView"
  - "AbletonBackupApp label simplified to single Label expression — switch over status cases was unnecessary"
  - "db reference stored as BackupCoordinator.db: AppDatabase? for project upserts in runBackup() — engine.db is private"

patterns-established:
  - "Bootstrap project ID: 'bootstrap-project', bootstrap destination ID: 'bootstrap-local' — stable keys for idempotent upserts"
  - "CoordinatorError enum for structured internal error handling"

requirements-completed: [APP-02, TRIG-01, TRIG-02, TRIG-03, DISC-01, NOTIF-01, NOTIF-02, APP-03]

# Metrics
duration: 2min
completed: 2026-02-27
---

# Phase 2 Plan 04: App Shell Integration Summary

**BackupCoordinator wires BackupEngine + FSEventsWatcher + SchedulerTask + NotificationService + LoginItemManager into complete end-to-end menu bar app with Phase 2 bootstrap**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-27T19:09:14Z
- **Completed:** 2026-02-27T19:11:45Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Complete BackupCoordinator: GRDB setup, FSEvents watcher, scheduler, notifications, login item all wired
- Full MenuBarView: status icon + text, last backup time (relative format), Back Up Now (disabled while running), Launch at Login toggle with requiresApproval handling
- xcodebuild BUILD SUCCEEDED for all Phase 2 Swift files under Swift 6 strict concurrency

## Task Commits

Each task was committed atomically:

1. **Task 1: Complete BackupCoordinator — wire all components** - `39fbc99` (feat)
2. **Task 2: Complete MenuBarView and wire notification auth in App entry** - `9e3c172` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `AbletonBackup/BackupCoordinator.swift` - Complete orchestrator: GRDB init, FSEvents watcher, scheduler, runBackup(), LoginItemManager
- `AbletonBackup/Views/MenuBarView.swift` - Full menu: status, backup time, Back Up Now, Launch at Login, Quit
- `AbletonBackup/AbletonBackupApp.swift` - Simplified MenuBarExtra label to single Label expression

## Decisions Made

- **BackupEngine.adapters is private:** The plan's `addAdapter` extension approach was not viable because `adapters` is declared `private var`. Fixed by initializing `BackupEngine` with the `LocalDestinationAdapter` at `setup()` time before assigning to `self.engine`. This is the correct approach for Phase 2.

- **Phase 1 schema differs from plan interfaces:** The plan's code used `rootURL: URL` for `Project` and `label`, `rootURL`, `type: "local"` (String) for `DestinationConfig`. Actual schema: `Project.path: String`, `DestinationConfig.name: String`, `DestinationConfig.rootPath: String`, `DestinationConfig.type: DestinationType` (enum), `DestinationConfig.createdAt: Date` (required). Fixed before first compile.

- **Access control:** `BackupStatus`, `BackupTrigger`, and `BackupCoordinator` made `internal` (no `public` modifier) because `LoginItemManager` is internal and the target is an app, not a library.

- **BackupStatus: Equatable:** Added directly to the `BackupStatus` enum declaration (`enum BackupStatus: Sendable, Equatable`) rather than as a separate extension, which would have needed to be in MenuBarView.swift or risk duplication.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] BackupEngine.adapters is private — addAdapter extension not viable**
- **Found during:** Task 1 (BackupCoordinator implementation)
- **Issue:** Plan proposed `extension BackupEngine { func addAdapter(...) }` but `adapters` is `private var` — compiler would reject the extension
- **Fix:** Initialize `BackupEngine(db: database, adapters: [adapter])` at `setup()` time with the bootstrap adapter already built, before assigning to `self.engine`
- **Files modified:** AbletonBackup/BackupCoordinator.swift
- **Verification:** BUILD SUCCEEDED
- **Committed in:** 39fbc99 (Task 1 commit)

**2. [Rule 1 - Bug] Project and DestinationConfig field names differ from plan interface spec**
- **Found during:** Task 1 (BackupCoordinator implementation, before first compile)
- **Issue:** Plan used `Project(id:name:rootURL:)` and `DestinationConfig(id:type:label:rootURL:retentionCount:)` but actual Phase 1 models use `path: String`, `name: String`, `rootPath: String`, `type: DestinationType`, `createdAt: Date`
- **Fix:** Read source files and adjusted all initializers to match actual field names
- **Files modified:** AbletonBackup/BackupCoordinator.swift
- **Verification:** BUILD SUCCEEDED
- **Committed in:** 39fbc99 (Task 1 commit)

**3. [Rule 1 - Bug] public access on BackupCoordinator caused compile error**
- **Found during:** Task 1 (first build attempt)
- **Issue:** `public let loginItemManager = LoginItemManager()` fails: "property cannot be declared public because its type 'LoginItemManager' uses an internal type"
- **Fix:** Removed all `public` modifiers from BackupStatus, BackupTrigger, BackupCoordinator — app target not library
- **Files modified:** AbletonBackup/BackupCoordinator.swift
- **Verification:** BUILD SUCCEEDED after change
- **Committed in:** 39fbc99 (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 1 — code correctness)
**Impact on plan:** All fixes required for compilation. No scope creep. Architecture unchanged — plan's intent fully realized.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 2 is fully functional: save .als file → FSEvents → backup → notification
- Scheduled backup fires every 3600 seconds automatically
- Manual backup via "Back Up Now" button in menu
- Menu bar icon changes: waveform (idle) → arrow.triangle.2.circlepath (running) → exclamationmark.triangle.fill (error)
- Phase 3 (Settings UI) will replace bootstrap hardcoded project/destination with user-configured values
- Phase 3 should reinitialize BackupEngine with user-configured adapters (replace bootstrap adapter)

---
*Phase: 02-app-shell-triggers*
*Completed: 2026-02-27*
