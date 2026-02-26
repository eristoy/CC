---
phase: 01-backup-engine
plan: 05
subsystem: backup-engine
tags: [swift, grdb, actor, integration-tests, incremental-backup, concurrency]

# Dependency graph
requires:
  - phase: 01-02
    provides: ProjectResolver.resolve(), needsCopy(), FileEntry, BackupJob, BackupJobResult
  - phase: 01-03
    provides: DestinationAdapter, LocalDestinationAdapter, FileCopyPipeline.computeChecksum()
  - phase: 01-04
    provides: VersionManager.newVersionID(), finalizeCopy(), markVerified(), markCorrupt(), pruneOldVersions()
  - phase: 01-01
    provides: AppDatabase.makeInMemory(), BackupVersion, BackupFileRecord, DestinationConfig, Project
provides:
  - BackupEngine actor (runJob, deduplication, full backup pipeline)
  - BackupEngineIntegrationTests (6 tests covering all Phase 1 success criteria)
affects:
  - Phase 2 (FSEvents watcher calls BackupEngine.runJob() when project changes)
  - Phase 3 (restore reads BackupVersion records; verification lifecycle is established here)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FileEntry cache (not DB-fetched BackupFileRecord) for incremental mtime comparison: avoids GRDB millisecond date truncation causing false-positive needsCopy() on unchanged files"
    - "Actor-local cache using [String: [String: FileEntry]] (projectID -> relativePath -> FileEntry): filesystem-precision mtime bypasses DB round-trip truncation"
    - "Task-based deduplication: runningJobs[projectID] = Task { executeJob() }; concurrent callers await existing.value"
    - "WAL write-barrier for fetching just-inserted records: pool.write (not pool.read) for step 7 allRecords fetch ensures committed data is visible"

key-files:
  created:
    - Tests/BackupEngineTests/BackupEngineIntegrationTests.swift
  modified:
    - Sources/BackupEngine/BackupEngine.swift

key-decisions:
  - "FileEntry cache over BackupFileRecord cache: GRDB stores Date as 'yyyy-MM-dd HH:mm:ss.SSS' (millisecond precision). Filesystem mtime has nanosecond precision. When stored and retrieved from DB, mtime is truncated. On second backup, entry.mtime (nanoseconds) > prev.sourceMtime (milliseconds truncated) returns true even for unchanged files — causing all files to copy. Fix: cache FileEntry objects (filesystem-precision mtime) in actor-local dict, build synthetic BackupFileRecord for needsCopy() comparison without DB round-trip."
  - "Full checksum verification (all files) over spot-check: integration tests verify all destination files. Phase 3 can add a 'deep verify' option to settings UI if performance becomes a concern for large projects."
  - "Merge strategy for FileEntry cache: nextCache = previousEntries (skipped files preserved) then override with filesToCopy entries (new copies). This ensures skipped files retain their cached FileEntry across backups."
  - "Concurrent deduplication via Task join: runningJobs stores Task<BackupJobResult, Error>. Second caller awaits existing.value — joins in-flight task rather than starting a new job."

patterns-established:
  - "GRDB date precision trap: any mtime/date comparison that round-trips through SQLite will lose sub-millisecond precision. Use in-actor caches with original values for comparisons, not DB-fetched values."
  - "pool.write for read-after-write: to avoid WAL snapshot isolation missing recently committed records, use pool.write (which uses the serial write queue) instead of pool.read when you need to see data just written by the current async context."

requirements-completed: [BACK-01, BACK-02, BACK-03, BACK-04, BACK-05, DEST-01]

# Metrics
duration: 95min
completed: 2026-02-26
---

# Phase 01 Plan 05: BackupEngine Integration Summary

**Swift actor orchestrating full backup pipeline with FileEntry-cache-based incremental skip, Task deduplication, and 6 integration tests covering all Phase 1 success criteria**

## Performance

- **Duration:** ~95 min (including extensive debugging of GRDB date precision bug)
- **Started:** 2026-02-26T~20:00:00Z (prior session)
- **Completed:** 2026-02-26T21:49:06Z
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified from Task 1 base)

## Accomplishments

- BackupEngine actor fully implemented: `runJob()`, deduplication via `Task` join, full pipeline (`executeJob()`) wiring ProjectResolver + DestinationAdapter + VersionManager + AppDatabase
- 6 integration tests created and passing, covering all Phase 1 success criteria:
  1. `fullBackupCopiesAllFiles` — BACK-01, DEST-01: full copy to local destination, verified status
  2. `secondBackupSkipsUnchangedFiles` — BACK-02: all 3 files skipped on second run
  3. `modifiedFileTriggersCopy` — BACK-02: only modified file copied, 2 skipped
  4. `checksumVerificationPassesForValidBackup` — BACK-03: checksums stored, status=verified
  5. `retentionPruning` — BACK-04, BACK-05: oldest version pruned after 4 backups with retentionCount=3
  6. `concurrentJobDeduplication`: both callers return same versionID, only 1 BackupVersion in DB
- All 41 tests pass (6 integration + 35 existing unit tests across 6 suites)
- Zero compiler warnings in final build

## Task Commits

Each task was committed atomically:

1. **Task 1 (implement BackupEngine actor)** - `1840a19` (feat)
2. **Task 2 (integration tests + date-precision fix)** - `edc2199` (feat)

## Files Created/Modified

- `Sources/BackupEngine/BackupEngine.swift` — BackupEngine actor with FileEntry cache, Task deduplication, full 12-step pipeline
- `Tests/BackupEngineTests/BackupEngineIntegrationTests.swift` — 6 integration tests covering all Phase 1 ROADMAP success criteria

## Decisions Made

**FileEntry cache over BackupFileRecord cache (critical correctness fix):**
GRDB encodes `Date` as `"yyyy-MM-dd HH:mm:ss.SSS"` (millisecond precision via `storageDateFormatter`). macOS filesystem `contentModificationDate` has nanosecond precision. When a `BackupFileRecord.sourceMtime` is stored in SQLite and retrieved, it is truncated to milliseconds. On the second backup, `entry.mtime` (from filesystem, nanosecond precision) is compared to `prev.sourceMtime` (from DB, millisecond precision). The sub-millisecond fractional difference makes `entry.mtime > prev.sourceMtime` return `true` even for unchanged files — causing all files to be "copied" on every backup.

Fix: The actor now maintains `fileEntryCache: [String: [String: FileEntry]]` (projectID → relativePath → FileEntry). FileEntry values have filesystem-precision mtime. On each backup, the incremental comparison builds a synthetic `BackupFileRecord` from the cached `FileEntry` — no DB round-trip, no precision loss.

**Full checksum verification per version:**
The verification pass (step 9) re-reads all destination file checksums and compares to stored values. This detects silent write corruption. A "spot-check" approach (one file per version) was considered but rejected in favor of full correctness.

**WAL write-barrier for step 7 fetch:**
Step 7 (fetching `allRecords` for manifest building) uses `pool.write` rather than `pool.read`. This ensures the records inserted in step 6 (inside `withThrowingTaskGroup`) are visible — WAL snapshot isolation on `pool.read` can miss writes committed after the snapshot was established.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 Sendable violation in withThrowingTaskGroup**
- **Found during:** Task 1 (building BackupEngine.swift)
- **Issue:** Variables `filesToCopy`, `versionID`, and `self.db` captured by nonisolated task group closure — Swift 6 strict concurrency error
- **Fix:** Created explicit local copies before task group: `let files = filesToCopySnapshot`, `let vid = versionID`, `let db = self.db` — all Sendable value types
- **Files modified:** Sources/BackupEngine/BackupEngine.swift
- **Committed in:** 1840a19

**2. [Rule 1 - Bug] GRDB millisecond date truncation causing false-positive needsCopy()**
- **Found during:** Task 2 (integration test `secondBackupSkipsUnchangedFiles` failed intermittently)
- **Issue:** `BackupFileRecord.sourceMtime` stored via GRDB as `"yyyy-MM-dd HH:mm:ss.SSS"` (milliseconds). Filesystem `contentModificationDate` has nanosecond precision. Second backup: `entry.mtime (nanoseconds) > prev.sourceMtime (milliseconds)` returns `true` even for unchanged files. All 3 files copied when 0 expected.
- **Investigation:** Debug prints confirmed cache had correct entries and paths matched. Added `ObjectIdentifier(self)` to confirm separate actors per test. Root cause: GRDB `Date.databaseValue` calls `storageDateFormatter.string(from: self)` using `"yyyy-MM-dd HH:mm:ss.SSS"` format — confirmed by reading `/GRDB/Core/Support/Foundation/Date.swift`.
- **Fix:** Replaced `previousManifestCache: [String: [BackupFileRecord]]` with `fileEntryCache: [String: [String: FileEntry]]`. Comparison uses original filesystem-precision `FileEntry.mtime` values — no DB round-trip. Synthetic `BackupFileRecord` built from cached `FileEntry` for `needsCopy()` call.
- **Files modified:** Sources/BackupEngine/BackupEngine.swift
- **Committed in:** edc2199

**3. [Rule 1 - Bug] Unused variable warning in test 4**
- **Found during:** Task 2 build output
- **Issue:** `destDir` bound but never used in `checksumVerificationPassesForValidBackup`
- **Fix:** Changed `destDir` to `_` in the tuple destructuring
- **Files modified:** Tests/BackupEngineTests/BackupEngineIntegrationTests.swift
- **Committed in:** edc2199

---

**Total deviations:** 3 auto-fixed (all Rule 1 bugs)

**Most significant:** The GRDB date precision bug (#2) caused all incremental backup tests to fail intermittently. The fix is architecturally sound — filesystem-precision FileEntry values in actor-local cache permanently solve the problem without changing any public API. This pattern should be applied anywhere DB-stored dates are used in comparisons.

## Phase 1 Completion

All 5 ROADMAP success criteria for Phase 1 are verified by passing integration tests:

| Criterion | Test | Status |
|-----------|------|--------|
| BACK-01: Backup copies project folder to versioned snapshot | `fullBackupCopiesAllFiles` | PASS |
| BACK-02: Second backup skips unchanged files (incremental) | `secondBackupSkipsUnchangedFiles`, `modifiedFileTriggersCopy` | PASS |
| BACK-03: Checksum verification detects corruption | `checksumVerificationPassesForValidBackup` | PASS |
| BACK-04: Retention count respected after N+1 backups | `retentionPruning` | PASS |
| BACK-05: Oldest version pruned automatically | `retentionPruning` | PASS |
| DEST-01: Local attached drive configured as destination | `fullBackupCopiesAllFiles` | PASS |

**Phase 1 is complete. Phase 2 (FSEvents watcher + app shell) can proceed.**

## Known Limitations (Deferred)

- **Corruption detection test:** The integration tests verify the *happy path* (no corruption). The test plan noted a corruption detection test — this is covered by `FileCopyPipelineTests.checksumDetectsCorruption`. A dedicated BackupEngine-level corruption test (manually corrupt destination, verify BackupEngine catches it on next run) is deferred to Phase 3 "deep verify" feature.
- **Spot-check vs. full verification:** Currently re-reads all destination checksums. Phase 3 can add a "deep verify" toggle in settings if verification becomes a bottleneck for large (5-20 GB) projects.
- **`deleting` status cleanup on startup:** BackupEngine should re-process `status=deleting` versions at startup (crash recovery). Currently deferred — no app shell exists yet (Phase 2 wires this up).

## Self-Check: PASSED

- FOUND: Sources/BackupEngine/BackupEngine.swift
- FOUND: Tests/BackupEngineTests/BackupEngineIntegrationTests.swift
- FOUND commit: 1840a19 (feat(01-05): implement BackupEngine actor)
- FOUND commit: edc2199 (feat(01-05): add BackupEngine integration tests and fix date-precision incremental skip bug)
- All 41 tests pass (6 integration + 35 unit) — confirmed via `swift test` output
- `swift build --target BackupEngine`: 0 errors, 0 warnings

---
*Phase: 01-backup-engine*
*Completed: 2026-02-26*
