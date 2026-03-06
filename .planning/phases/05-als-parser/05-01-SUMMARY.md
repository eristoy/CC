---
phase: 05-als-parser
plan: 01
subsystem: audio-parsing
tags: [als, ableton, gzip, zlib, xml, xmldocument, grdb, swift]

# Dependency graph
requires:
  - phase: 01-backup-engine
    provides: BackupVersion GRDB model and Schema migration infrastructure

provides:
  - ALSParser: gzip decompress + XPath sample extraction + external/internal classification
  - ALSRewriter: XMLDocument path mutation + gzip re-compression to Samples/Imported/ layout
  - SampleCollection: Sendable result type capturing collected and missing sample metadata
  - Schema v3_als_sample_tracking migration adding 5 columns to backupVersion table
  - BackupVersion extended with 5 ALS sample fields (all with defaults, no breaking changes)

affects:
  - 05-als-parser/05-02 (BackupEngine integration that consumes all types built here)

# Tech tracking
tech-stack:
  added: [system zlib via import zlib, Foundation XMLDocument]
  patterns:
    - "ParseResult enum (success/parseFailure) — never throws from public API, always returns a result"
    - "zlib inflate/deflate with MAX_WBITS+32/+16 for gzip auto-detect and gzip output"
    - "Exclusive-access fix: capture local capacity constants before entering withUnsafeMutableBytes nested inside withUnsafeBytes"

key-files:
  created:
    - Sources/BackupEngine/ALS/ALSParser.swift
    - Sources/BackupEngine/ALS/ALSRewriter.swift
    - Sources/BackupEngine/ALS/SampleCollection.swift
  modified:
    - Sources/BackupEngine/Persistence/Schema.swift
    - Sources/BackupEngine/Persistence/Models/BackupVersion.swift

key-decisions:
  - "ALSParser.parse() returns ParseResult (not throws) — backup engine always gets a usable result and decides how to proceed"
  - "importedRelativePath preserves full absolute path as subfolder under Samples/Imported/ (collision-free, mirrors Ableton's Collect All and Save)"
  - "zlib inflateInit2_ with MAX_WBITS+32 (gzip auto-detect) — NSData.decompressed uses raw DEFLATE which does not work for .als files"
  - "Swift exclusive-access fix: use local let variables to snapshot buffer capacity before nested withUnsafeMutableBytes call"
  - "BackupVersion new fields all have defaults — existing DB rows and init call sites compile without changes"

patterns-established:
  - "ALS directory under Sources/BackupEngine/ALS/ for all Ableton-specific parsing types"
  - "ParseResult enum pattern: .success with associated values, .parseFailure with reason string"

requirements-completed: [PRSR-01, PRSR-02]

# Metrics
duration: 3min
completed: 2026-03-06
---

# Phase 05 Plan 01: ALS Parser Foundation Summary

**Gzip decompress + XPath sample extraction (ALSParser), XMLDocument path mutation + gzip re-compression (ALSRewriter), Sendable SampleCollection result type, GRDB v3 migration with 5 ALS columns, and BackupVersion model extension — all compiling cleanly under Swift 6**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-06T19:51:46Z
- **Completed:** 2026-03-06T19:55:14Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Three new Swift files in Sources/BackupEngine/ALS/ implementing the complete ALS parsing and rewriting foundation
- Schema v3_als_sample_tracking migration adds 5 columns to backupVersion with safe defaults for existing rows
- BackupVersion model extended with 5 ALS fields (collectedSampleCount, collectedSamplePaths, missingSampleCount, missingSamplePaths, hasParseWarning) plus JSON encode/decode helpers — no breaking changes to existing call sites

## Task Commits

Each task was committed atomically:

1. **Task 1: ALS types — ALSParser, ALSRewriter, SampleCollection** - `f1ec2fb` (feat)
2. **Task 2: Schema v3 migration + BackupVersion model extension** - `c7d76df` (feat)

## Files Created/Modified

- `Sources/BackupEngine/ALS/SampleCollection.swift` - Sendable result type with collectedPaths, missingPaths, hasParseWarning, plus .empty and .parseFailure static instances
- `Sources/BackupEngine/ALS/ALSParser.swift` - Gzip decompress via system zlib (inflateInit2_ MAX_WBITS+32), XPath extraction of //SampleRef/FileRef/Path, external/internal classification relative to project directory; decompressGzip() exposed as public for ALSRewriter to reuse
- `Sources/BackupEngine/ALS/ALSRewriter.swift` - importedRelativePath() maps /abs/path to Samples/Imported/abs/path; rewriteAndCompress() mutates FileRef Path/RelativePath/RelativePathType in XMLDocument then re-gzips with deflateInit2_ MAX_WBITS+16; compressGzip() internal helper
- `Sources/BackupEngine/Persistence/Schema.swift` - v3_als_sample_tracking migration (third migration) alters backupVersion table with 5 new columns
- `Sources/BackupEngine/Persistence/Models/BackupVersion.swift` - 5 new fields with defaults; init updated with defaulted parameters; encodePaths/decodePaths static helpers for JSON-in-TEXT column pattern

## Decisions Made

- `ALSParser.parse()` returns `ParseResult` (not throws) so the backup engine always receives a usable result and applies fallback policy at the call site — consistent with the "backup always proceeds" requirement
- `importedRelativePath()` preserves the full original absolute path as a subfolder tree under `Samples/Imported/` (e.g. `Samples/Imported/Users/eric/Music/Drums/kick.wav`) — zero collision risk, identical to Ableton's own Collect All and Save behavior
- Used `inflateInit2_` with `MAX_WBITS + 32` for gzip auto-detection — `NSData.decompressed(using: .zlib)` would use raw DEFLATE and fail on .als files
- Swift 6 exclusive-access error in nested `withUnsafeBytes`/`withUnsafeMutableBytes` fixed by capturing local `let` capacity snapshots before entering the inner closure, so the outer borrow and inner mutation do not overlap

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Swift 6 exclusive-access error in zlib closure nesting**
- **Found during:** Task 1 (ALSParser / ALSRewriter implementation)
- **Issue:** Nesting `output.withUnsafeMutableBytes` inside `data.withUnsafeBytes` caused "overlapping accesses to 'output'" compile error under Swift 6's exclusivity enforcement
- **Fix:** Captured `currentCapacity = output.count` and `written = Int(stream.total_out)` as local `let` constants before the inner closure, then used those instead of referencing `output.count` inside the closure. Same pattern applied to ALSRewriter.compressGzip.
- **Files modified:** Sources/BackupEngine/ALS/ALSParser.swift, Sources/BackupEngine/ALS/ALSRewriter.swift
- **Verification:** BUILD SUCCEEDED after fix
- **Committed in:** f1ec2fb (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug/compile error)
**Impact on plan:** Required for Swift 6 compilation. No behavioral change, no scope creep.

## Issues Encountered

- Swift 6 exclusive-access enforcement requires non-overlapping borrows in nested `withUnsafeBytes` / `withUnsafeMutableBytes` — the plan's zlib snippet pattern was correct in intent but needed a minor structural adjustment for Swift 6

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All three ALS types (ALSParser, ALSRewriter, SampleCollection) are ready to be consumed by Plan 02 (BackupEngine integration)
- Schema v3 migration is registered and will run automatically via DatabaseMigrator on next app launch
- BackupVersion has all 5 ALS fields with backward-compatible defaults

---
*Phase: 05-als-parser*
*Completed: 2026-03-06*
