---
phase: 05-als-parser
plan: 02
subsystem: backup-engine
tags: [als, ableton, samples, notifications, swift6, grdb]

# Dependency graph
requires:
  - phase: 05-01
    provides: ALSParser, ALSRewriter, SampleCollection, BackupVersion ALS schema fields

provides:
  - ALS parse-before-copy integrated into BackupEngine.executeJob as Step 0
  - External samples copied to Samples/Imported/<full-original-path> at each destination
  - Rewritten (path-remapped, re-gzipped) .als in backup versionDir
  - backupVersion DB rows updated with all 5 ALS sample columns after each job
  - NotificationService.sendMissingSamplesWarning and sendALSParseWarning methods
  - NotificationDelegate.didReceive posts navigateToVersion to NotificationCenter
  - BackupJobResult.sampleCollection exposes ALS outcome to callers

affects: [05-03, history-ui, backup-coordinator]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "BackupEngine returns SampleCollection in BackupJobResult; coordinator (app layer) dispatches notifications — keeps BackupEngine module free of UserNotifications dependency"
    - "sampleCollection computed as let (not var) to satisfy Swift 6 concurrent-capture exclusivity in TaskGroup closures"
    - "versionID assigned before step 0 (ALS parse) so it can be referenced in notifications before DB rows exist"

key-files:
  created: []
  modified:
    - AbletonBackup/NotificationService.swift
    - Sources/BackupEngine/BackupEngine.swift
    - Sources/BackupEngine/BackupJob.swift
    - AbletonBackup/BackupCoordinator.swift

key-decisions:
  - "NotificationService stays in app target; BackupEngine returns SampleCollection in BackupJobResult and BackupCoordinator sends notifications — BackupEngine module cannot import UserNotifications from app target"
  - "sampleCollection computed as let using immediately-invoked closure to satisfy Swift 6 Sendable / concurrent-capture rules in TaskGroup"
  - "versionID moved before step 0 (was before step 4) so parse-failure and missing-sample notifications carry the correct versionID before any file writes"
  - "External sample copy and ALS rewrite run after the main TaskGroup fan-out; no structural changes to LocalDestinationAdapter required"

patterns-established:
  - "Engine-layer results carry all metadata (SampleCollection); app-layer coordinator dispatches side effects (notifications) — clean module boundary"

requirements-completed: [PRSR-01, PRSR-02]

# Metrics
duration: 5min
completed: 2026-03-06
---

# Phase 05 Plan 02: ALS Pipeline Integration Summary

**ALS parse-before-copy wired into BackupEngine: external samples collected into Samples/Imported/, .als rewritten and re-gzipped, DB rows updated, and coordinator dispatches missing-sample / parse-failure notifications via BackupJobResult**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-06T19:58:33Z
- **Completed:** 2026-03-06T20:03:01Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- NotificationService gained `sendMissingSamplesWarning` and `sendALSParseWarning` with versionID userInfo; `NotificationDelegate.didReceive` now posts `navigateToVersion` to `NotificationCenter` on tap; `Notification.Name.navigateToVersion` defined
- BackupEngine.executeJob: versionID moved before step 0; ALSParser.parse called before any file copy; external samples copied to `Samples/Imported/<full-path>` at each destination; `ALSRewriter.rewriteAndCompress` replaces the .als in backup; all 5 ALS DB columns persisted after step 12
- BackupJobResult carries `sampleCollection`; BackupCoordinator inspects it and sends appropriate notifications — preserving clean module boundary (BackupEngine does not import UserNotifications)

## Task Commits

Each task was committed atomically:

1. **Task 1: NotificationService — add missing-sample and parse-warning notifications** - `ac31bf7` (feat)
2. **Task 2: BackupEngine + LocalDestinationAdapter — ALS pipeline integration** - `19f364a` (feat)

## Files Created/Modified

- `AbletonBackup/NotificationService.swift` — Added sendMissingSamplesWarning, sendALSParseWarning, didReceive handler, Notification.Name.navigateToVersion
- `Sources/BackupEngine/BackupEngine.swift` — ALS Step 0 parse, external sample copy + rewrite, DB persist, versionID moved early
- `Sources/BackupEngine/BackupJob.swift` — BackupJobResult.sampleCollection field added
- `AbletonBackup/BackupCoordinator.swift` — Sends ALS notifications from BackupJobResult after runJob

## Decisions Made

- **Module boundary preserved**: NotificationService lives in the app target and cannot be imported by the BackupEngine Swift package. The plan described BackupEngine calling NotificationService directly, but that would require moving NotificationService into the package or creating a cross-module import. Used the existing coordinator pattern instead: BackupEngine returns `SampleCollection` in `BackupJobResult`, and `BackupCoordinator` sends notifications — matching how `sendBackupSuccess`/`sendBackupFailure` are already dispatched.
- **`let sampleCollection` via immediately-invoked closure**: Swift 6 disallows capturing `var` bindings in concurrent TaskGroup closures. Computed the final `SampleCollection` value in a single synchronous closure (no concurrency) before the TaskGroup, satisfying the exclusivity checker.
- **versionID hoisted before step 0**: Notifications include the versionID for tap navigation. Moving the assignment before the ALS parse means the correct ID is available in `sampleCollection` context returned in `BackupJobResult`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] NotificationService module boundary — moved notification dispatch to BackupCoordinator**
- **Found during:** Task 2 (BackupEngine ALS pipeline integration)
- **Issue:** Plan specified `BackupEngine` calling `NotificationService.sendALSParseWarning(...)` directly, but `NotificationService` is in the `AbletonBackup` app target and cannot be imported from the `BackupEngine` Swift package module — compiler error "cannot find NotificationService in scope"
- **Fix:** Added `sampleCollection: SampleCollection` to `BackupJobResult`; `BackupCoordinator.runBackup()` inspects the result and dispatches notifications using the same pattern already used for `sendBackupSuccess`/`sendBackupFailure`
- **Files modified:** `Sources/BackupEngine/BackupJob.swift`, `AbletonBackup/BackupCoordinator.swift`
- **Verification:** BUILD SUCCEEDED; notifications fire with correct versionID from coordinator
- **Committed in:** `19f364a` (Task 2 commit)

**2. [Rule 1 - Bug] Swift 6 concurrent-capture exclusivity on `var sampleCollection`**
- **Found during:** Task 2 (BackupEngine ALS pipeline integration)
- **Issue:** `var sampleCollection` captured in `db.pool.write` concurrent closure caused Swift 6 "reference to captured var in concurrently-executing code" error
- **Fix:** Refactored to compute `sampleCollection` as `let` using an immediately-invoked closure that evaluates the `ALSParser.parse` result in a single synchronous expression
- **Files modified:** `Sources/BackupEngine/BackupEngine.swift`
- **Verification:** BUILD SUCCEEDED with no Swift 6 concurrency warnings
- **Committed in:** `19f364a` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 - bug fixes for compiler errors)
**Impact on plan:** Both fixes necessary for correct compilation under Swift 6. Functional behavior matches plan intent exactly — ALS parse before copy, notifications sent with versionID, same timing semantics.

## Issues Encountered

None beyond the two auto-fixed compiler errors documented above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- ALS pipeline fully active for every backup job
- BackupVersion DB rows populated with sample metadata — ready for Phase 05-03 history UI display
- `Notification.Name.navigateToVersion` defined — ready for HistoryView to subscribe and navigate

---
*Phase: 05-als-parser*
*Completed: 2026-03-06*
