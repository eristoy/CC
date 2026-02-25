---
phase: 01-backup-engine
plan: 01
subsystem: database
tags: [grdb, sqlite, wal, swift6, persistence, schema, migrations]

# Dependency graph
requires: []
provides:
  - AppDatabase (DatabasePool factory with WAL mode, temp-file test variant)
  - GRDB v1_initial migration: destination, project, backupVersion, backupFileRecord, versionLock tables
  - BackupVersion + VersionStatus (7-state lifecycle enum)
  - BackupFileRecord (per-file manifest with checksum)
  - DestinationConfig + DestinationType (local/nas/icloud/github)
  - Project (UNIQUE path constraint, lastBackupAt)
affects:
  - 01-02-ProjectResolver (imports Project, BackupFileRecord)
  - 01-03-FileCopyPipeline (imports BackupVersion, BackupFileRecord, DestinationConfig)
  - 01-04-BackupOrchestrator (imports all model types, AppDatabase)
  - 01-05-RetentionEngine (imports BackupVersion, DestinationConfig)

# Tech tracking
tech-stack:
  added:
    - GRDB.swift 7.10.0 (SQLite ORM, WAL-mode DatabasePool)
    - xxHash-Swift 1.1.1 (fast checksums — resolved successfully)
  patterns:
    - GRDB DatabaseMigrator with versioned migrations (v1_initial)
    - Sendable model structs conforming to FetchableRecord + PersistableRecord + TableRecord
    - Temp-file DatabasePool for test isolation (WAL incompatible with :memory:)
    - VersionStatus enum with raw String values for SQLite TEXT column

key-files:
  created:
    - Package.swift
    - Sources/BackupEngine/Persistence/AppDatabase.swift
    - Sources/BackupEngine/Persistence/Schema.swift
    - Sources/BackupEngine/Persistence/Models/BackupVersion.swift
    - Sources/BackupEngine/Persistence/Models/VersionStatus.swift
    - Sources/BackupEngine/Persistence/Models/BackupFileRecord.swift
    - Sources/BackupEngine/Persistence/Models/DestinationConfig.swift
    - Sources/BackupEngine/Persistence/Models/Project.swift
    - Sources/BackupEngine/ProjectResolver.swift (stub for plan 01-02)
    - Sources/BackupEngine/BackupJob.swift
    - Tests/BackupEngineTests/AppDatabaseTests.swift
  modified: []

key-decisions:
  - "xxHash-Swift resolved successfully at 1.1.1 — included in Package.swift as planned"
  - "makeInMemory() uses temp file path (not :memory:) because DatabasePool WAL mode is incompatible with SQLite in-memory databases"
  - "VersionStatus defined in separate VersionStatus.swift file (not inside BackupVersion.swift) for clean import by ProjectResolver stub"
  - "ProjectResolver.swift stub created to satisfy compilation of pre-existing TDD RED test file (ProjectResolverTests.swift for plan 01-02)"
  - "BackupJob.swift stub types (VersionStatus, Project) removed — replaced by canonical Persistence/Models definitions"

patterns-established:
  - "GRDB models: struct conforming to TableRecord + FetchableRecord + PersistableRecord + Codable + Sendable"
  - "AppDatabase: static factory methods (makeShared/makeInMemory), private init, apply migrations in factory"
  - "Schema: enum with registerMigrations(in:) static method — pure migration registration, no state"
  - "Test isolation: AppDatabase.makeInMemory() creates unique UUID-named temp file per test"

requirements-completed:
  - BACK-04
  - DEST-01

# Metrics
duration: 6min
completed: 2026-02-25
---

# Phase 01 Plan 01: Schema and Persistence Foundation Summary

**GRDB 7.10.0 DatabasePool with WAL mode, versioned migration creating 5 tables, and 4 Sendable model types (BackupVersion/VersionStatus/BackupFileRecord/DestinationConfig/Project) with full GRDB record conformances**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-25T21:06:05Z
- **Completed:** 2026-02-25T21:12:23Z
- **Tasks:** 2
- **Files modified:** 12

## Accomplishments
- Swift package created with GRDB 7.10.0 and xxHash-Swift 1.1.1 (both resolved successfully)
- Complete v1_initial migration: destination, project, backupVersion, backupFileRecord, versionLock tables with correct FK constraints and the backupVersion composite index
- All 4 model types compile with GRDB record conformances and Swift 6 Sendable
- VersionStatus 7-state lifecycle enum (pending/copying/copy_complete/verifying/verified/corrupt/deleting) fully defined
- 6 AppDatabaseTests pass: migrations, CRUD on all tables, full version lifecycle state machine

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Swift package with GRDB 7 and project structure** - `690c743` (feat)
2. **Task 2: Define GRDB schema and all model types** - `80cfd34` (feat)

**Plan metadata:** (see final docs commit)

## Files Created/Modified
- `/Users/eric/dev/CC/Package.swift` - SPM manifest: swift-tools-version 6.0, macOS 13+, GRDB 7.10.0 + xxHash-Swift 1.1.1
- `/Users/eric/dev/CC/Sources/BackupEngine/Persistence/AppDatabase.swift` - DatabasePool factory, WAL mode, temp-file test variant
- `/Users/eric/dev/CC/Sources/BackupEngine/Persistence/Schema.swift` - DatabaseMigrator v1_initial with all 5 tables
- `/Users/eric/dev/CC/Sources/BackupEngine/Persistence/Models/BackupVersion.swift` - GRDB record + makeID() factory
- `/Users/eric/dev/CC/Sources/BackupEngine/Persistence/Models/VersionStatus.swift` - 7-state lifecycle enum
- `/Users/eric/dev/CC/Sources/BackupEngine/Persistence/Models/BackupFileRecord.swift` - per-file manifest, AUTOINCREMENT, UNIQUE(versionID,relativePath)
- `/Users/eric/dev/CC/Sources/BackupEngine/Persistence/Models/DestinationConfig.swift` - destination record + DestinationType enum
- `/Users/eric/dev/CC/Sources/BackupEngine/Persistence/Models/Project.swift` - project with UNIQUE path
- `/Users/eric/dev/CC/Sources/BackupEngine/ProjectResolver.swift` - compilation stub (full impl: plan 01-02)
- `/Users/eric/dev/CC/Sources/BackupEngine/BackupJob.swift` - BackupJob/DestinationResult/BackupJobResult contract types (stubs removed)
- `/Users/eric/dev/CC/Tests/BackupEngineTests/AppDatabaseTests.swift` - 6 passing tests
- `/Users/eric/dev/CC/.gitignore` - excludes .build/, .DS_Store, Xcode state

## Decisions Made
- **xxHash-Swift included**: Package resolved at 1.1.1 without issues. No CryptoKit fallback needed.
- **makeInMemory() uses temp file, not :memory:**: DatabasePool requires a real file path to activate WAL mode. SQLite's `:memory:` path is incompatible with WAL. Each test call creates a unique UUID-named temp file in `FileManager.default.temporaryDirectory`.
- **VersionStatus in separate file**: Placed in its own `VersionStatus.swift` rather than nested inside `BackupVersion.swift` to avoid import confusion when other types need to reference it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] DatabasePool WAL mode incompatible with :memory: path**
- **Found during:** Task 2 (running AppDatabaseTests)
- **Issue:** `DatabasePool(path: ":memory:")` throws "SQLite error 1: could not activate WAL Mode at path: :memory:" — WAL mode requires a real file
- **Fix:** `makeInMemory()` now creates a unique temp file via `FileManager.default.temporaryDirectory` + UUID + `.db` extension. Each call is isolated.
- **Files modified:** Sources/BackupEngine/Persistence/AppDatabase.swift
- **Verification:** All 6 AppDatabaseTests pass
- **Committed in:** 80cfd34 (Task 2 commit)

**2. [Rule 1 - Bug] Duplicate type declarations blocked compilation**
- **Found during:** Task 2 (first build attempt)
- **Issue:** Pre-existing `BackupJob.swift` contained stub `VersionStatus` and `Project` definitions marked "TEMP: replace when 01-01 completes". These conflicted with the canonical model types I created.
- **Fix:** Removed stub type definitions from BackupJob.swift; kept only the BackupJob/DestinationResult/BackupJobResult contract types.
- **Files modified:** Sources/BackupEngine/BackupJob.swift
- **Verification:** Build succeeds with no duplicate-declaration errors
- **Committed in:** 80cfd34 (Task 2 commit)

**3. [Rule 3 - Blocking] Pre-existing ProjectResolverTests.swift blocked test compilation**
- **Found during:** Task 2 (test execution)
- **Issue:** `Tests/BackupEngineTests/ProjectResolverTests.swift` (TDD RED phase for plan 01-02) references `ProjectResolver` and `FileEntry` types that didn't exist, preventing the entire test target from compiling.
- **Fix:** Created `Sources/BackupEngine/ProjectResolver.swift` with stub implementations of `ProjectResolver.resolve(at:)` and `ProjectResolver.needsCopy(entry:previousRecord:)` and `FileEntry` struct. Stubs return empty/default values. Full implementation is plan 01-02's TDD task.
- **Files modified:** Sources/BackupEngine/ProjectResolver.swift (new)
- **Verification:** Test target compiles; AppDatabaseTests pass; ProjectResolverTests compile (will intentionally fail behavior assertions in 01-02)
- **Committed in:** 80cfd34 (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking)
**Impact on plan:** All auto-fixes necessary for correctness and compilation. No scope creep. ProjectResolver stub is explicitly expected by plan 01-02's TDD RED workflow.

## Issues Encountered
- GRDB 7's DatabasePool API has no no-argument initializer (unlike earlier versions). The plan's `DatabasePool()` example doesn't compile — must use `DatabasePool(path:)`. Linter caught this and corrected AppDatabase.swift to use `path: ":memory:"` (which was then further fixed to temp-file due to WAL incompatibility).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All model types exportable from BackupEngine target
- AppDatabase migrations tested and passing
- BackupJob/BackupJobResult contract types defined
- ProjectResolver stub in place — plan 01-02 can immediately add the full implementation over the stub
- xxHash-Swift available for plan 01-03 FileCopyPipeline checksum implementation

## Self-Check: PASSED

All files found. All commits verified.

| Item | Status |
|------|--------|
| Package.swift | FOUND |
| AppDatabase.swift | FOUND |
| Schema.swift | FOUND |
| BackupVersion.swift | FOUND |
| VersionStatus.swift | FOUND |
| BackupFileRecord.swift | FOUND |
| DestinationConfig.swift | FOUND |
| Project.swift | FOUND |
| AppDatabaseTests.swift | FOUND |
| 01-01-SUMMARY.md | FOUND |
| commit 690c743 | FOUND |
| commit 80cfd34 | FOUND |

---
*Phase: 01-backup-engine*
*Completed: 2026-02-25*
