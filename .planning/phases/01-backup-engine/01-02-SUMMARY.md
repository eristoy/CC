---
phase: 01-backup-engine
plan: 02
subsystem: file-io
tags: [swift6, filesystem, filemanager, incremental-backup, tdd, swift-testing]

# Dependency graph
requires:
  - phase: 01-backup-engine/01-01
    provides: BackupFileRecord (sourceSize/sourceMtime for needsCopy comparison), Project model type
provides:
  - FileEntry struct (relativePath, url, size, mtime) — unit of work through backup pipeline
  - ProjectResolver.resolve(at:) — recursive directory walker, excludes hidden files and directories
  - ProjectResolver.needsCopy(entry:previousRecord:) — mtime+size incremental skip heuristic
  - BackupJob struct (project + destinationIDs) — input to BackupEngine.runJob()
  - BackupJobResult struct (versionID, filesCopied, filesSkipped, totalBytes, status, destinationResults)
  - DestinationResult struct (destinationID, status, errorMessage)
affects:
  - 01-03-FileCopyPipeline (imports FileEntry, uses ProjectResolver.resolve)
  - 01-05-BackupEngine (imports BackupJob, BackupJobResult, ProjectResolver)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - TDD RED→GREEN cycle with Swift Testing (@Test, @Suite) against real temp directories
    - FileManager.enumerator with URLResourceKey batch reads (isRegularFile, isHidden, fileSize, contentModificationDate)
    - resolvingSymlinksInPath() on both root and file URLs before relative path computation (macOS /var→/private/var)
    - Incremental skip: mtime > prev.sourceMtime OR size != prev.sourceSize (no source-side checksum)

key-files:
  created:
    - Sources/BackupEngine/ProjectResolver.swift
    - Sources/BackupEngine/BackupJob.swift
    - Tests/BackupEngineTests/ProjectResolverTests.swift
  modified:
    - Sources/BackupEngine/ProjectResolver.swift (stub → full implementation)

key-decisions:
  - "Plan 01-01 models were already built (no stubs needed) — BackupJob.swift uses Project and VersionStatus from Persistence/Models directly"
  - "resolvingSymlinksInPath() required on macOS — FileManager.temporaryDirectory returns /var/folders/... but real path is /private/var/folders/... causing relative path strip to fail"
  - "FileEntry conforms to Equatable per plan interface spec (addition from spec)"
  - "needsCopy uses Int64 cast for BackupFileRecord.sourceSize (stored as Int in GRDB model, compared against Int64 FileEntry.size)"

patterns-established:
  - "ProjectResolver: pure struct with static methods — no state, synchronous, local filesystem only"
  - "Directory walking: FileManager.enumerator(at:includingPropertiesForKeys:options:[]) with no skip options for full recursive traversal"
  - "relativePath: rootURL.resolvingSymlinksInPath().path prefix-stripped, leading slash removed"
  - "Test isolation: UUID-named temp dir per test, defer cleanup with try? removeItem"

requirements-completed:
  - BACK-01
  - BACK-02

# Metrics
duration: 8min
completed: 2026-02-25
---

# Phase 01 Plan 02: ProjectResolver and BackupJob Contract Types Summary

**Recursive directory walker with mtime+size incremental skip heuristic, tested with Swift Testing against real temp directories (11 tests, all pass)**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-25T21:06:22Z
- **Completed:** 2026-02-25T21:14:00Z
- **Tasks:** 2 (RED + GREEN TDD cycle)
- **Files modified:** 3

## Accomplishments
- ProjectResolver.resolve(at:) walks directories recursively via FileManager.enumerator, excludes hidden files and directory entries, returns correct FileEntry with relativePath/url/size/mtime
- ProjectResolver.needsCopy(entry:previousRecord:) implements mtime+size comparison — no source-side checksum (preserves incremental performance)
- BackupJob, BackupJobResult, DestinationResult contract types defined using real 01-01 model types (no stubs needed)
- 11 Swift Testing tests cover all specified behaviors: empty dir, flat, nested, hidden exclusion, dir exclusion, size, mtime, needsCopy x4

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Write failing tests for ProjectResolver and BackupJob types** - `80cfd34` (feat, as part of 01-01 commit)
2. **Task 2 (GREEN): Implement ProjectResolver to pass all tests** - `f27b22f` (feat)

**Plan metadata:** (this commit)

_Note: Task 1 RED state was committed as part of the 01-01 executor's final commit (80cfd34) which included BackupJob.swift, ProjectResolver.swift stub, and ProjectResolverTests.swift. The RED state was confirmed: resolve() returned [] causing 7 of 11 tests to fail._

## Files Created/Modified
- `/Users/eric/dev/CC/Sources/BackupEngine/ProjectResolver.swift` — full implementation: recursive walk, symlink resolution, relativePath computation, needsCopy with mtime+size
- `/Users/eric/dev/CC/Sources/BackupEngine/BackupJob.swift` — BackupJob/DestinationResult/BackupJobResult using real Project and VersionStatus from 01-01 models
- `/Users/eric/dev/CC/Tests/BackupEngineTests/ProjectResolverTests.swift` — 11 Swift Testing tests covering all behavior cases from plan specification

## Decisions Made
- **No stubs needed**: Plan 01-01 was already executed before this plan ran, so BackupJob.swift uses the real Project and VersionStatus model types instead of temporary stubs. The "TEMP" stubs planned in the task were never needed.
- **resolvingSymlinksInPath() required**: macOS `FileManager.temporaryDirectory` returns `/var/folders/...` but the actual file system path is `/private/var/folders/...` (symlink). Without resolving symlinks before computing relative paths, the prefix strip fails and all relativePaths return just the filename. Fixed by calling `.resolvingSymlinksInPath()` on both rootURL and each fileURL from the enumerator.
- **FileEntry Equatable**: Added `Equatable` conformance per the plan's interface spec (the plan defines `FileEntry: Sendable, Equatable`). The stub had only `Sendable`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] macOS symlink resolution breaks relative path computation**
- **Found during:** Task 2 (running tests — "Nested directory" and "Directory entries excluded" tests failed)
- **Issue:** `FileManager.temporaryDirectory.path` = `/var/folders/...` but enumerator yields URLs with resolved path `/private/var/folders/...`. String prefix-strip of rootPath from fileURL.path failed silently, returning just the filename as relativePath.
- **Fix:** Call `.resolvingSymlinksInPath()` on rootURL before creating enumerator; also resolve each fileURL from enumerator before computing relativePath. Enumerator is created with the resolved root URL so all enumerated paths are consistent.
- **Files modified:** Sources/BackupEngine/ProjectResolver.swift
- **Verification:** All 11 ProjectResolverTests pass including nested path tests
- **Committed in:** f27b22f (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Auto-fix was necessary for correctness. The symlink issue is a macOS-specific behavior that affects all tests using FileManager.temporaryDirectory.

## Issues Encountered
- macOS /var vs /private/var symlink: `FileManager.temporaryDirectory` returns a non-resolved symlink path. The enumerator's yielded URLs are on the resolved real path. This caused a mismatch in the prefix-strip relative path computation. Resolved by calling `.resolvingSymlinksInPath()` before passing rootURL to the enumerator.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- FileEntry and ProjectResolver exported from BackupEngine target — ready for FileCopyPipeline (01-03)
- BackupJob and BackupJobResult defined — ready for BackupEngine orchestrator (01-05)
- needsCopy function tested and verified — incremental skip logic is correct
- All 17 tests pass (11 ProjectResolver + 6 AppDatabase)

---
*Phase: 01-backup-engine*
*Completed: 2026-02-25*
