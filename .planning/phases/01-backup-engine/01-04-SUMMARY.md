---
phase: 01-backup-engine
plan: 04
subsystem: database
tags: [swift, grdb, tdd, retention, pruning, versioning]

# Dependency graph
requires:
  - phase: 01-01
    provides: BackupVersion, VersionStatus, VersionLock schema, AppDatabase.makeInMemory()
provides:
  - VersionManager with newVersionID(), pruneOldVersions(), finalizeCopy(), markVerified(), markCorrupt()
  - BackupManifest and ManifestEntry value types for per-version file inventory
  - Full TDD test suite: 9 tests covering version ID and all retention edge cases
affects:
  - 01-05 (BackupEngine actor calls VersionManager.newVersionID() and pruneOldVersions())
  - Phase 3 (restore uses VersionLock; locked version skipping already handled)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Write-then-cleanup: mark status=deleting in DB write transaction before any disk deletion"
    - "Walk-and-collect pruning: iterate all verified versions oldest-first, skip locked, collect until excessCount — correct when locked versions are in the pruning window"
    - "Stateless manager enum: VersionManager has no stored state — all state lives in DatabasePool"

key-files:
  created:
    - Sources/BackupEngine/VersionManager.swift
    - Sources/BackupEngine/BackupManifest.swift
    - Tests/BackupEngineTests/VersionManagerTests.swift
  modified: []

key-decisions:
  - "Corrupt versions: kept in DB with status=corrupt, NOT counted toward retention limit, never pruned — user may inspect them; future history UI (Phase 3) will surface with warning indicator"
  - "Version ID format: yyyy-MM-dd'T'HHmmss.SSS-xxxxxxxx (no colons in time component) — delegates to BackupVersion.makeID() which uses DateFormatter with UTC locale"
  - "Locked version walk-and-collect: simple prefix filter was incorrect — when locked versions fall in the pruning window, walk all verified versions (oldest first) and collect up to excessCount non-locked candidates"
  - "Write-then-cleanup crash safety: status=deleting set in single DB write transaction before any FileManager.removeItem — on crash, deleting rows are reprocessed at next launch (BackupEngine's responsibility)"

patterns-established:
  - "TDD RED via stub: VersionManager existed as a stub before 01-04 (added by WIP commit), providing correct GREEN-when-implemented behavior. 6 of 9 tests failed (stubs return []) confirming RED."
  - "async/await DB reads in Swift Testing: db.pool.read in async test context requires await keyword (GRDB 7 async API)"

requirements-completed: [BACK-04, BACK-05]

# Metrics
duration: 6min
completed: 2026-02-25
---

# Phase 01 Plan 04: VersionManager TDD Summary

**VersionManager with collision-safe millisecond-precision version IDs and retention pruning — only verified versions count, corrupt versions preserved, locked versions skipped via walk-and-collect**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-25T21:24:42Z
- **Completed:** 2026-02-25T21:30:22Z
- **Tasks:** 2
- **Files modified:** 3 (2 created, 1 overwritten from stub)

## Accomplishments

- BackupManifest and ManifestEntry pure value types created for per-version file inventory
- VersionManagerTests.swift with all 9 required test cases covering ID generation, retention under/at/over limit, corrupt exclusion, locked version skipping, and non-verified immunity
- VersionManager.pruneOldVersions() fully implemented with write-then-cleanup pattern and correct walk-and-collect logic for locked version handling
- All 9 tests GREEN, BackupEngine builds clean with zero errors

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Write failing VersionManager tests** - `8aee91b` (test)
2. **Task 2 (GREEN): Implement VersionManager** - `6654ba5` (feat)

_Note: TDD plan — RED commit establishes failing tests, GREEN commit makes them pass_

## Files Created/Modified

- `Sources/BackupEngine/BackupManifest.swift` - BackupManifest and ManifestEntry value types
- `Sources/BackupEngine/VersionManager.swift` - Full VersionManager implementation (was stub)
- `Tests/BackupEngineTests/VersionManagerTests.swift` - 9 test cases for RED/GREEN cycle

## Decisions Made

**Corrupt version policy confirmed:** Corrupt versions are kept in the DB with `status=corrupt`. They are NOT counted toward the retention limit and are never pruned. The rationale: users may want to inspect why a version was corrupt. Phase 3 history UI will surface them with a warning indicator. Re-backup should be triggered by BackupEngine, not VersionManager.

**Version ID format confirmed:** `"yyyy-MM-dd'T'HHmmss.SSS-xxxxxxxx"` — no colons in the time component (`:` is not filename-safe on some systems). Delegates to `BackupVersion.makeID()` which uses `DateFormatter` with UTC locale and `en_US_POSIX` locale for guaranteed POSIX formatting.

**Walk-and-collect for locked versions:** A simple `prefix(excessCount).filter(!locked)` approach was incorrect. When the oldest versions are locked, they fall inside the pruning window but cannot be deleted. The correct implementation walks all verified versions (oldest first) and collects up to `excessCount` non-locked candidates — skipping locked versions without reducing the collection budget.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed async/await in test DB reads**
- **Found during:** Task 1 (writing test file)
- **Issue:** `db.pool.read` in async test functions requires `await` in GRDB 7 strict concurrency mode — Swift 6 resolves to the async overload in async contexts
- **Fix:** Updated all `db.pool.read` calls in async test functions to use `try await db.pool.read`
- **Files modified:** Tests/BackupEngineTests/VersionManagerTests.swift
- **Verification:** Compiler errors resolved, all tests compile cleanly
- **Committed in:** 8aee91b (Task 1 commit)

**2. [Rule 1 - Bug] Fixed walk-and-collect locked version pruning logic**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** Initial implementation used `prefix(excessCount).filter(!locked)` — when oldest version is locked, the entire pruning window collapses to empty and nothing gets pruned (test: 11 verified, 1 locked → expected ids[1] deleted, actual: nothing deleted)
- **Fix:** Replaced with walk-and-collect loop: iterate all verified versions oldest-first, skip locked, collect until excessCount candidates found
- **Files modified:** Sources/BackupEngine/VersionManager.swift
- **Verification:** Test "locked version skipped even when excess" passes; all 9 tests GREEN
- **Committed in:** 6654ba5 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 bugs)
**Impact on plan:** Both fixes necessary for correctness. Walk-and-collect fix is critical — the naive implementation would silently fail to prune when any excess candidate is locked.

## Issues Encountered

- WIP commit from prior session had already created VersionManager stub and 01-03 implementation files. The stub satisfied compilation so the TDD RED phase showed 3 ID tests passing (stub delegates to BackupVersion.makeID()) and 6 pruning tests failing (stub returns []). This is an acceptable RED state per the plan — the important constraint is that pruning tests fail.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- VersionManager.newVersionID() ready for BackupEngine actor integration (plan 01-05)
- VersionManager.pruneOldVersions() ready to wire into post-verification cleanup in BackupEngine
- BackupManifest ready for BackupEngine to build after transfer() completes
- finalizeCopy(), markVerified(), markCorrupt() ready for BackupEngine state machine

## Self-Check: PASSED

- FOUND: Sources/BackupEngine/VersionManager.swift
- FOUND: Sources/BackupEngine/BackupManifest.swift
- FOUND: Tests/BackupEngineTests/VersionManagerTests.swift
- FOUND: .planning/phases/01-backup-engine/01-04-SUMMARY.md
- FOUND commit: 8aee91b (test(01-04): add failing VersionManager tests)
- FOUND commit: 6654ba5 (feat(01-04): implement VersionManager)
- All 9 VersionManagerTests pass (GREEN confirmed)
- swift build --target BackupEngine: 0 errors, 0 warnings

---
*Phase: 01-backup-engine*
*Completed: 2026-02-25*
