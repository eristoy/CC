# Phase 1: Backup Engine - Research

**Researched:** 2026-02-25
**Domain:** Swift file I/O, concurrency, checksums, versioned backup on macOS
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BACK-01 | App copies project folder + all collected samples to each configured destination | File copy pipeline (copyfile + FileManager), DestinationAdapter protocol, incremental comparison logic |
| BACK-02 | Backup is incremental — unchanged files are skipped | mtime+size comparison pattern; size-only is insufficient; full checksum too slow for skip decisions |
| BACK-03 | Each file is checksum-verified after copy to detect silent corruption | xxHash computed inline during copy; SHA-256 via CryptoKit as alternative; manifest stored in GRDB |
| BACK-04 | App retains N versions per project (configurable, default: 10) | Version lifecycle state machine in GRDB; retention count stored in configuration table |
| BACK-05 | App automatically prunes oldest versions when over limit | Write-then-cleanup pattern with SQLite commit log; never prune until new version is `verified` |
| DEST-01 | User can configure a local attached drive destination | LocalDestinationAdapter using APFS cloning (COPYFILE_CLONE) with HFS+ fallback; FileManager for non-APFS |
</phase_requirements>

---

## Summary

Phase 1 builds the pure-Swift backup engine with no UI: a file copy pipeline that is incremental, checksum-verified, versioned, and safely pruned. All six Phase 1 requirements map to well-understood macOS APIs with established patterns. The technology choices — GRDB 7 for persistence, Swift Concurrency (`actor` + `TaskGroup`) for the engine, `copyfile(COPYFILE_CLONE)` for local copies, and xxHash for fast inline checksums — are verifiable against official documentation and current Swift ecosystem practice.

The most important architectural decision is the **backup version lifecycle state machine**: `pending -> copying -> copy_complete -> verifying -> verified | corrupt`. Only `verified` versions count toward the retention limit or are eligible for pruning. This single constraint prevents two of the most dangerous failure modes (pruning before verification; treating a failed copy as success). The second most important decision is **incremental detection strategy**: compare `mtime + size` to decide whether to copy; compute a checksum during the actual copy to verify. Do not compute checksums on both source and destination to make the skip decision — that defeats the purpose of incremental backup.

GRDB 7 (released February 2026, requires Swift 6.1+ / Xcode 16.3+) is the correct version to target. It has full Swift 6 Sendable conformance and proper async/await integration, removing the `@unchecked Sendable` workarounds required in GRDB 6. Use `DatabasePool` (which automatically enables WAL mode) rather than `DatabaseQueue` to support concurrent reads from the future settings UI without blocking backup writes.

**Primary recommendation:** Build in this order — (1) GRDB schema + migrations, (2) `ProjectResolver` (folder walker), (3) `VersionManager` (ID generation + retention logic), (4) file copy + checksum pipeline, (5) `BackupEngine` actor orchestrating all four, (6) `LocalDestinationAdapter`. Test each layer with Swift Testing against a real temporary directory (not mocks).

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| GRDB.swift | 7.10.0 (Feb 2026) | SQLite persistence — schema, migrations, version history | Type-safe, WAL mode via DatabasePool, full Swift 6 Sendable, no ORM overhead |
| Swift Concurrency (actor + TaskGroup) | Built-in (Swift 6) | BackupEngine actor; concurrent destination fan-out via TaskGroup | Native, structured cancellation, actor serializes job management safely |
| Foundation FileManager | Built-in | Directory creation, attribute reading, copying on non-APFS | Standard macOS API for all file operations |
| copyfile(3) C API | Built-in (macOS) | APFS copy-on-write cloning — near-instant, space-efficient | `COPYFILE_CLONE` falls back to regular copy on non-APFS; `COPYFILE_CLONE_FORCE` does not fall back |
| CryptoKit SHA256 | Built-in (macOS 10.15+) | Fallback checksum if xxHash unavailable | First-party, zero dependencies, incremental `.update(data:)` API |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| xxHash-Swift (daisuke-t-jp) | Latest | XXH3-64 checksum — 31 GB/s vs SHA-256's 2.1 GB/s on Apple Silicon | Use for per-file integrity checksums during copy; speed is critical for large audio files |
| SwiftCopyfile (osy) | Latest (Apr 2024) | Swift async wrapper for copyfile with progress async sequence | Use if per-file byte-level progress reporting is needed; wraps the C copyfile API cleanly |
| Swift Testing | Built-in (Xcode 16) | Test framework with `@Test`, `@Suite`, parallel by default | Use for all Phase 1 unit tests; prefer over XCTest for new code |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| GRDB 7 DatabasePool | Core Data | Core Data heavier; GRDB has explicit schema, simpler migrations, WAL is automatic with DatabasePool |
| xxHash-Swift | CryptoKit SHA-256 | SHA-256 is ~15x slower on large files (2.1 GB/s vs 31 GB/s); use SHA-256 if removing external dependency is a priority |
| copyfile COPYFILE_CLONE | FileManager.copyItem | FileManager gives no progress, no sparse file support, no APFS clone path; SwiftCopyfile or direct copyfile is better |
| Swift Testing | XCTest | Both work; Swift Testing is the current direction; XCTest can coexist for migration |

**Installation (SPM Package.swift):**
```swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    .package(url: "https://github.com/daisuke-t-jp/xxHash-Swift.git", from: "1.0.0"),
    // Optional:
    .package(url: "https://github.com/osy/SwiftCopyfile.git", branch: "main"),
]
```

---

## Architecture Patterns

### Recommended Module Structure

```
Sources/
└── BackupEngine/               # Swift package target — no UI dependencies
    ├── BackupEngine.swift      # actor BackupEngine — orchestrator
    ├── BackupJob.swift         # struct BackupJob, BackupJobResult
    ├── ProjectResolver.swift   # walks project folder, returns [FileEntry]
    ├── VersionManager.swift    # generates versionIDs, enforces retention
    ├── FileCopyPipeline.swift  # copyfile + inline checksum computation
    ├── BackupManifest.swift    # per-version manifest (file list + checksums)
    ├── Destinations/
    │   ├── DestinationAdapter.swift    # protocol DestinationAdapter
    │   └── LocalDestinationAdapter.swift  # APFS clone + HFS+ fallback
    └── Persistence/
        ├── AppDatabase.swift   # DatabasePool setup, migrations
        ├── Schema.swift        # table definitions as GRDB Record types
        └── Models/
            ├── BackupVersion.swift
            ├── BackupFileRecord.swift
            └── DestinationConfig.swift

Tests/
└── BackupEngineTests/
    ├── ProjectResolverTests.swift
    ├── FileCopyPipelineTests.swift
    ├── VersionManagerTests.swift
    └── BackupEngineIntegrationTests.swift
```

### Pattern 1: BackupEngine as Swift Actor

**What:** The `BackupEngine` is a Swift `actor` that serializes job management. It ensures only one job runs per project simultaneously, while individual destination transfers run concurrently via `TaskGroup`.

**When to use:** Whenever a shared mutable state (running jobs, job queue) must be accessed from multiple async contexts.

```swift
// Source: Architecture research + Swift Concurrency documentation
actor BackupEngine {
    private var runningJobs: [ProjectID: Task<BackupJobResult, Error>] = [:]
    private let db: DatabasePool
    private let destinations: [DestinationAdapter]

    func runJob(for project: Project) async throws -> BackupJobResult {
        // Guard: skip if already running
        if let existing = runningJobs[project.id] {
            return try await existing.value
        }

        let task = Task {
            try await executeBackupJob(for: project)
        }
        runningJobs[project.id] = task
        defer { runningJobs.removeValue(forKey: project.id) }
        return try await task.value
    }

    private func executeBackupJob(for project: Project) async throws -> BackupJobResult {
        let files = try await ProjectResolver.resolve(at: project.path)
        let versionID = VersionManager.newVersionID()

        // Create pending version record
        try await db.write { db in
            try BackupVersion(id: versionID, projectID: project.id, status: .pending).insert(db)
        }

        // Fan out to destinations concurrently
        var results: [DestinationResult] = []
        try await withThrowingTaskGroup(of: DestinationResult.self) { group in
            for adapter in destinations {
                group.addTask {
                    try await adapter.transfer(files, versionID: versionID)
                }
            }
            for try await result in group {
                results.append(result)
            }
        }

        // Verify, finalize, prune
        try await finalizeVersion(versionID: versionID, results: results)
        try await VersionManager.pruneOldVersions(for: project.id, db: db)
        return BackupJobResult(versionID: versionID, destinationResults: results)
    }
}
```

### Pattern 2: File Copy with Inline Checksum

**What:** Copy each file in chunks; feed each chunk to the hasher simultaneously. This computes the checksum at zero additional I/O cost — no second read pass.

**When to use:** Every file copy in the backup pipeline. Never compute checksum separately from the copy.

```swift
// Source: Pitfalls research (Pitfall 7) + CryptoKit incremental hashing docs
func copyFileWithChecksum(source: URL, destination: URL) throws -> String {
    // Try APFS clone first (near-instant, copy-on-write)
    // COPYFILE_CLONE falls back to regular copy on non-APFS — use this, not CLONE_FORCE
    let state = copyfile_state_alloc()
    defer { copyfile_state_free(state) }
    let cloneResult = copyfile(source.path, destination.path, state, COPYFILE_CLONE | COPYFILE_ALL)

    if cloneResult == 0 {
        // Cloning succeeded — compute checksum from destination (clone is instant)
        return try computeChecksum(of: destination)
    }

    // Clone failed (non-APFS or cross-device) — chunked copy with inline hashing
    var hasher = SHA256()     // or XXH3 from xxHash-Swift
    let chunkSize = 8 * 1024 * 1024  // 8 MB chunks

    let input = try FileHandle(forReadingFrom: source)
    let output = try FileHandle(forWritingTo: destination)
    defer { try? input.close(); try? output.close() }

    while true {
        let chunk = try input.read(upToCount: chunkSize)
        guard !chunk.isEmpty else { break }
        try output.write(contentsOf: chunk)
        hasher.update(data: chunk)
    }

    let digest = hasher.finalize()
    return digest.map { String(format: "%02hhx", $0) }.joined()
}
```

### Pattern 3: Version Lifecycle State Machine

**What:** Every backup version has a status column in SQLite. The lifecycle is strictly ordered. Pruning and restore eligibility check status.

**When to use:** Every state transition in the backup pipeline must go through this machine.

```
pending -> copying -> copy_complete -> verifying -> verified
                                               -> corrupt
```

GRDB schema column: `status TEXT NOT NULL DEFAULT 'pending'`

Valid transitions (enforce in VersionManager, not in the adapter):
- `pending` → `copying`: when transfer starts
- `copying` → `copy_complete`: when all bytes written
- `copy_complete` → `verifying`: when checksum verification begins
- `verifying` → `verified`: when all checksums match
- `verifying` → `corrupt`: when any checksum mismatch detected
- Only `verified` versions are eligible for restore
- Only `verified` versions count toward the retention limit
- Only prune after the new version reaches `verified`

### Pattern 4: Incremental Skip Detection

**What:** Compare `mtime + size` against the previous version's manifest to decide whether to copy. Do NOT compute source checksum to make the skip decision — that reads every byte of every file and eliminates the incremental benefit.

**Decision logic:**
```swift
struct FileEntry {
    let relativePath: String
    let size: Int64
    let mtime: Date
}

func shouldCopy(current: FileEntry, previous: BackupFileRecord?) -> Bool {
    guard let prev = previous else { return true }       // new file
    if current.size != prev.sourceSize { return true }   // size changed
    if current.mtime > prev.sourceMtime { return true }  // modified
    return false                                          // skip
}
```

This matches rsync's default behavior (`--archive` without `--checksum`): mtime+size for skip decisions, checksum only for verification after copy.

### Pattern 5: GRDB 7 Schema + Migrations

**What:** Use `DatabasePool` (auto-enables WAL mode) and `DatabaseMigrator` for versioned schema evolution.

```swift
// Source: GRDB 7 official documentation + groue/GRDB.swift README
import GRDB

final class AppDatabase {
    let pool: DatabasePool

    static func makeShared() throws -> AppDatabase {
        let dbPath = // Application Support directory
        let pool = try DatabasePool(path: dbPath)
        let db = AppDatabase(pool: pool)
        try db.applyMigrations()
        return db
    }

    private func applyMigrations() throws {
        var migrator = DatabaseMigrator()

        // Development mode: wipe on schema change (remove in production)
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initial") { db in
            // destinations
            try db.create(table: "destination") { t in
                t.primaryKey("id", .text)  // UUID string
                t.column("type", .text).notNull()  // "local"
                t.column("name", .text).notNull()
                t.column("rootPath", .text).notNull()
                t.column("retentionCount", .integer).notNull().defaults(to: 10)
                t.column("createdAt", .datetime).notNull()
            }

            // projects
            try db.create(table: "project") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("path", .text).notNull().unique()
                t.column("lastBackupAt", .datetime)
            }

            // backup versions
            try db.create(table: "backupVersion") { t in
                t.primaryKey("id", .text)  // ISO8601 timestamp + project slug
                t.column("projectID", .text).notNull().references("project", onDelete: .cascade)
                t.column("destinationID", .text).notNull().references("destination", onDelete: .cascade)
                t.column("status", .text).notNull().defaults(to: "pending")
                    // pending | copying | copy_complete | verifying | verified | corrupt
                t.column("fileCount", .integer)
                t.column("totalBytes", .integer)
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)
                t.column("errorMessage", .text)
            }

            // per-file manifest records
            try db.create(table: "backupFileRecord") { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("versionID", .text).notNull().references("backupVersion", onDelete: .cascade)
                t.column("relativePath", .text).notNull()
                t.column("sourceMtime", .datetime).notNull()
                t.column("sourceSize", .integer).notNull()
                t.column("checksum", .text)  // null until verified
                t.column("copied", .boolean).notNull().defaults(to: false)
                t.uniqueKey(["versionID", "relativePath"])
            }

            // version locks (for safe pruning during restore)
            try db.create(table: "versionLock") { t in
                t.column("versionID", .text).notNull().references("backupVersion", onDelete: .cascade)
                t.column("lockedSince", .datetime).notNull()
                t.primaryKey(["versionID"])
            }
        }

        try migrator.migrate(pool)
    }
}
```

### Pattern 6: DestinationAdapter Protocol

**What:** A protocol that all destination types conform to. Phase 1 only implements `LocalDestinationAdapter`. Designed to extend cleanly to NAS (Phase 4) and cloud (Phase 5) without changing the engine.

```swift
protocol DestinationAdapter: Sendable {
    var id: String { get }
    var config: DestinationConfig { get }

    /// Copy files to the destination for a given version.
    /// Reports progress via AsyncStream.
    func transfer(
        _ files: [FileEntry],
        versionID: String,
        progress: @escaping (TransferProgress) -> Void
    ) async throws -> DestinationResult

    /// Prune versions beyond retention count.
    func pruneVersions(keeping: Int, for projectID: String) async throws

    /// Check if destination is reachable (fast, < 3s timeout).
    func probe() async -> DestinationStatus
}

// Phase 1 implementation
struct LocalDestinationAdapter: DestinationAdapter {
    let id: String
    let config: DestinationConfig

    func transfer(_ files: [FileEntry], versionID: String,
                  progress: @escaping (TransferProgress) -> Void) async throws -> DestinationResult {
        let versionDir = config.rootURL
            .appendingPathComponent(config.projectSlug)
            .appendingPathComponent(versionID)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)

        var manifest: [BackupFileRecord] = []
        for file in files {
            let dest = versionDir.appendingPathComponent(file.relativePath)
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let checksum = try copyFileWithChecksum(source: file.url, destination: dest)
            manifest.append(BackupFileRecord(
                relativePath: file.relativePath,
                sourceMtime: file.mtime,
                sourceSize: file.size,
                checksum: checksum
            ))
            progress(TransferProgress(file: file, bytesCopied: file.size))
        }
        return DestinationResult(versionID: versionID, manifest: manifest)
    }
}
```

### Pattern 7: Version Pruning (Write-Then-Cleanup)

**What:** Never delete a version until the new version is `verified`. Use a "pending deletion" pattern in SQLite so a crash during pruning is recoverable.

```swift
func pruneOldVersions(for projectID: String, keeping retentionCount: Int, db: DatabasePool) async throws {
    try await db.write { db in
        // Fetch verified versions, oldest first
        let versions = try BackupVersion
            .filter(Column("projectID") == projectID)
            .filter(Column("status") == "verified")
            .order(Column("createdAt").asc)
            .fetchAll(db)

        let excess = versions.dropLast(retentionCount)
        for version in excess {
            // Check for active lock (restore in progress)
            let locked = try VersionLock
                .filter(Column("versionID") == version.id)
                .fetchOne(db)
            guard locked == nil else { continue }

            // Mark as pending deletion before touching disk
            try db.execute(sql: "UPDATE backupVersion SET status = 'deleting' WHERE id = ?",
                           arguments: [version.id])
        }
    }

    // Now delete from disk (outside the write transaction)
    // On crash here, 'deleting' rows are cleaned on next launch
}
```

### Anti-Patterns to Avoid

- **Using `COPYFILE_CLONE_FORCE` for local backup**: It fails on non-APFS destinations (ExFAT-formatted drives are common for audio producers). Use `COPYFILE_CLONE` (auto-fallback) instead.
- **Computing source checksum to decide whether to copy**: This reads every byte of every file, destroying incremental performance. Use mtime+size for skip decisions, checksum only after copying.
- **Using `DatabaseQueue` instead of `DatabasePool`**: `DatabaseQueue` does not automatically enable WAL mode. With WAL, the future settings window can read backup history concurrently with an ongoing backup write.
- **Pruning before verification**: A backup marked `verified` failed and was deleted, leaving zero valid versions. The state machine prevents this only if you enforce the rule that pruning checks for `verified` status.
- **Storing destination root path as a bookmark instead of raw path in Phase 1**: Phase 1 is non-sandboxed; raw paths work. Security-scoped bookmarks are only needed if distributing via Mac App Store (explicitly deferred).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQLite schema management | Custom migration tracking table | GRDB `DatabaseMigrator` | Migration ordering, applied-once guarantees, dev-mode schema wipe — all handled |
| Per-file checksum during copy | Custom chunked read loop with SHA | CryptoKit `SHA256` incremental or xxHash-Swift | Both have incremental `.update(data:)` API; no second read pass needed |
| APFS copy-on-write | Custom copy path detection | `copyfile(COPYFILE_CLONE)` | OS handles APFS detection and fallback; `copyfile` is the documented API |
| Concurrent destination fan-out | OperationQueue with manual dependencies | Swift `withThrowingTaskGroup` | Structured cancellation, natural async/await integration, cleaner error propagation |
| Version directory naming | UUID or counter | ISO8601 timestamp string | Human-readable, sortable, no DB lookup needed to determine order from filesystem |

**Key insight:** The GRDB migration system, copyfile API, and CryptoKit are each solving problems with significant hidden complexity (crash recovery, filesystem differences, hash algorithm correctness). None should be re-implemented.

---

## Common Pitfalls

### Pitfall 1: COPYFILE_CLONE_FORCE Fails on ExFAT/HFS+ Destinations

**What goes wrong:** Audio producers commonly format external drives as ExFAT for Windows compatibility or as HFS+. `COPYFILE_CLONE_FORCE` returns an error on non-APFS volumes instead of falling back to a regular copy.

**Why it happens:** `COPYFILE_CLONE_FORCE` specifically means "clone or fail"; `COPYFILE_CLONE` means "clone or fall back to regular copy." Easy to confuse the two flags.

**How to avoid:** Use `COPYFILE_CLONE` (without `FORCE`). Verify the fallback behavior in tests by running against a test directory on a non-APFS volume or by forcing the clone to fail.

**Warning signs:** Backups to ExFAT-formatted drives fail immediately with error `ENOTSUP` or `EXDEV`.

### Pitfall 2: mtime Granularity Causes False "Unchanged" Decisions

**What goes wrong:** HFS+ has 1-second mtime granularity. If two saves happen within the same second, the second save's file will have the same mtime as the first backup, and the incremental check will skip it.

**Why it happens:** mtime comparison assumes sub-second precision. HFS+ doesn't provide it.

**How to avoid:** For the initial Phase 1 scope (local APFS destinations), this is not a problem — APFS has nanosecond mtime precision. Document the HFS+ limitation. For robustness, also compare file size; HFS+ granularity only causes false negatives if both mtime AND size are identical.

**Warning signs:** Unit tests on a real HFS+ volume show files that changed in rapid succession being incorrectly skipped.

### Pitfall 3: Large Backup Version Table Without Index

**What goes wrong:** Queries like "find all verified versions for project X, oldest first" become slow as backup history grows. A project backed up every hour accumulates thousands of version rows per year.

**Why it happens:** GRDB creates tables without indexes by default. Queries on `projectID + status` with `ORDER BY createdAt` need a covering index.

**How to avoid:** Add indexes in the initial migration:
```swift
try db.create(indexOn: "backupVersion", columns: ["projectID", "status", "createdAt"])
```

**Warning signs:** Settings window shows version history loading slowly after 6+ months of use.

### Pitfall 4: Version ID Collision on Rapid Consecutive Backups

**What goes wrong:** If the version ID is generated from `ISO8601` truncated to seconds, two backups triggered within the same second produce the same ID, causing a SQLite unique constraint violation.

**Why it happens:** Manual backup + FSEvents event can fire within milliseconds of each other.

**How to avoid:** Use millisecond or nanosecond ISO8601: `DateFormatter` with format `"yyyy-MM-dd'T'HH:mm:ss.SSS"`. Or append a UUID suffix: `"\(timestamp)-\(UUID().uuidString.prefix(8))"`.

**Warning signs:** Unit test that triggers two rapid backups gets a SQLite UNIQUE constraint error on the second insert.

### Pitfall 5: Pruning Corrupt Versions

**What goes wrong:** If a version is marked `corrupt`, it is still counted toward the retention limit and gets pruned like any other old version — but the user may want to be notified that a corrupt version existed, not silently deleted.

**How to avoid:** Decide policy explicitly during planning: either (a) corrupt versions do not count toward the retention limit and are kept for inspection, or (b) corrupt versions are pruned immediately and a persistent notification is stored. For Phase 1, recommend policy (a) with a note in the backup history UI.

---

## Code Examples

### GRDB DatabasePool Setup (WAL mode automatic)

```swift
// Source: GRDB.swift README + groue/GRDB.swift Documentation
import GRDB

let pool = try DatabasePool(path: dbPath)
// DatabasePool automatically enables WAL mode on open.
// Concurrent reads allowed; writes serialized by GRDB internally.
```

### DatabaseMigrator Registration

```swift
// Source: GRDB.swift documentation (DatabaseMigrator)
var migrator = DatabaseMigrator()
migrator.registerMigration("v1_initial") { db in
    try db.create(table: "backupVersion") { t in
        t.primaryKey("id", .text)
        t.column("status", .text).notNull().defaults(to: "pending")
        t.column("createdAt", .datetime).notNull()
        // ...
    }
}
try migrator.migrate(pool)
```

### Incremental File Decision

```swift
// Source: rsync mtime+size approach (see rsync manual); standard backup tool pattern
func needsCopy(entry: FileEntry, previousRecord: BackupFileRecord?) -> Bool {
    guard let prev = previousRecord else { return true }
    return entry.size != prev.sourceSize || entry.mtime > prev.sourceMtime
}
```

### xxHash-Swift Incremental (during copy loop)

```swift
// Source: daisuke-t-jp/xxHash-Swift README — streaming API
import xxHash_Swift

var hasher = XXH64()          // or XXH3() for xxh3-64
while let chunk = read(chunkSize) {
    write(chunk)
    hasher.update(chunk)
}
let digest = hasher.digest()  // UInt64
let hex = String(format: "%016llx", digest)
```

### CryptoKit SHA256 Incremental (no external dependency)

```swift
// Source: Apple CryptoKit documentation
import CryptoKit

var hasher = SHA256()
while let chunk = readNextChunk(8 * 1024 * 1024) {
    hasher.update(data: chunk)
}
let digest = hasher.finalize()
let hex = digest.map { String(format: "%02hhx", $0) }.joined()
```

### Swift Testing Pattern for File System Tests

```swift
// Source: Swift Testing documentation (Xcode 16)
import Testing
import Foundation

@Suite("FileCopyPipeline")
class FileCopyPipelineTests {
    let tempDirectory: URL

    init() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    @Test func copiesFileAndProducesChecksum() throws {
        let sourceFile = tempDirectory.appendingPathComponent("test.wav")
        let destFile = tempDirectory.appendingPathComponent("dest/test.wav")
        // Write known content
        try Data("hello audio".utf8).write(to: sourceFile)
        let checksum = try copyFileWithChecksum(source: sourceFile, destination: destFile)
        #expect(FileManager.default.fileExists(atPath: destFile.path))
        #expect(!checksum.isEmpty)
    }
}
```

### Version Directory Structure on Disk

```
/Volumes/BackupDrive/
└── AbletonBackups/
    └── MyProject/
        ├── 2026-02-25T143022.456-a3f8b12c/   ← verified version
        │   ├── MyProject.als
        │   └── Samples/
        │       └── Imported/
        │           └── kick.wav
        └── 2026-02-25T091500.123-9d2e7a1f/   ← older verified version
```

Version directory name format: `{ISO8601-ms}-{UUID-prefix-8}` — human-readable, collision-safe, sortable.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| XCTest for all Swift tests | Swift Testing (`@Test`, `@Suite`) | Xcode 16 / WWDC24 | Parallel by default, struct-based, better async support |
| GRDB 6 with @unchecked Sendable workarounds | GRDB 7 (full Sendable, Swift 6 compiler required) | Feb 2026 (v7.10.0) | Clean Swift 6 concurrency, no suppression warnings |
| DatabaseQueue + manual WAL PRAGMA | DatabasePool (WAL automatic) | GRDB 4+ | Concurrent reads during backup writes, no extra setup |
| SHA-256 for all integrity checks | xxHash3 for speed, SHA-256 as fallback | ~2022 (xxHash v0.8+) | 15x speed difference matters for multi-GB audio files |
| OperationQueue for concurrency | Swift actor + TaskGroup | Swift 5.5 (2021) | Structured cancellation, no manual queue management |

**Deprecated/outdated:**
- `NSTask`: Replaced by `Process` (same class, renamed). Don't use NSTask — compiler will reject it.
- `FileManager.copyItem(at:to:)` for large files: Use `copyfile` C API directly for progress + APFS cloning.
- GRDB 6 for new projects: Requires `@unchecked Sendable` hacks with Swift 6; start with GRDB 7.

---

## Open Questions

1. **xxHash-Swift package maintenance status**
   - What we know: `daisuke-t-jp/xxHash-Swift` supports XXH32/XXH64/XXH3-64/XXH3-128, has SPM support, requires Swift 5.0+
   - What's unclear: Last commit date / active maintenance; whether it targets Swift 6 with Sendable conformances
   - Recommendation: Before adopting, check GitHub for recent commits. If maintenance is stale, use CryptoKit SHA-256 instead — the performance difference (15x) is less important than a reliable dependency for Phase 1.

2. **checksum algorithm choice: per-file or per-chunk?**
   - What we know: Per-file checksum is standard for backup manifests; per-chunk would allow resumable verification
   - What's unclear: Whether Phase 1 needs chunk-level checksums (needed for streaming resume on cloud destinations in later phases)
   - Recommendation: Store per-file checksums in Phase 1. Design `BackupFileRecord` with a `checksum TEXT` column. Phase 4/5 can add `chunks BLOB` or a separate chunk table if resumable upload verification is needed.

3. **Corrupt version policy**
   - What we know: The state machine produces `corrupt` status; pruning logic needs to handle it
   - What's unclear: User-visible behavior — should corrupt versions appear in history? Be auto-deleted? Trigger a re-backup?
   - Recommendation: Keep corrupt versions in the DB with status `corrupt`, do not count them toward retention limit, surface them in history with a warning icon. Auto-trigger a re-backup notification. Define this policy in the plan, not during implementation.

4. **GRDB actor isolation for the engine**
   - What we know: `DatabasePool` is `Sendable` in GRDB 7; async read/write methods work from any actor context
   - What's unclear: Whether `BackupEngine` actor holding a `DatabasePool` requires any additional annotation in Swift 6 strict concurrency mode
   - Recommendation: Use `let pool: DatabasePool` (not `var`) inside the actor; `DatabasePool` is `Sendable`, so this should satisfy Swift 6 without `@unchecked Sendable`.

---

## Sources

### Primary (HIGH confidence)
- [GRDB.swift GitHub](https://github.com/groue/GRDB.swift) — version 7.10.0 (Feb 2026), DatabasePool WAL mode, DatabaseMigrator API, Swift 6 requirements
- [GRDB 7 Migration Guide](https://github.com/groue/GRDB.swift/blob/master/Documentation/GRDB7MigrationGuide.md) — breaking changes, Sendable conformance, task cancellation behavior
- [GRDB "GRDB 7 is out" Swift Forums](https://forums.swift.org/t/grdb-7-is-out/77465) — release confirmation, Swift 6.1+ requirement, Xcode 16.3+
- [Apple CryptoKit SHA256 docs](https://developer.apple.com/documentation/cryptokit/sha256) — incremental hashing API
- [copyfile(3) man page](https://keith.github.io/xcode-man-pages/copyfile.3.html) — COPYFILE_CLONE vs COPYFILE_CLONE_FORCE fallback semantics
- [APFS copy-on-write article — Wade Tregaskis](https://wadetregaskis.com/copy-on-write-on-apfs/) — confirms COPYFILE_CLONE auto-fallback, COPYFILE_CLONE_FORCE does not fall back
- [SwiftCopyfile (osy/SwiftCopyfile)](https://github.com/osy/SwiftCopyfile) — Swift async wrapper for copyfile with progress async sequence, Apr 2024
- Architecture research (`.planning/research/ARCHITECTURE.md`) — BackupEngine actor pattern, TaskGroup fan-out, component interaction
- Pitfalls research (`.planning/research/PITFALLS.md`) — version cleanup race conditions, integrity verification lifecycle, large file memory pitfalls

### Secondary (MEDIUM confidence)
- [xxHash-Swift (daisuke-t-jp)](https://github.com/daisuke-t-jp/xxHash-Swift) — XXH3 support, streaming API, SPM support confirmed; Swift 6 Sendable status unverified
- [SHA-256 Alternatives 2025 — devtoolspro.org](https://devtoolspro.org/articles/sha256-alternatives-faster-hash-functions-2025/) — xxHash3 31 GB/s vs SHA-256 2.1 GB/s on Apple M3 Pro (web search, single source)
- [Swift Testing lifecycle — Swift with Majid](https://swiftwithmajid.com/2024/10/29/introducing-swift-testing-lifecycle/) — init/deinit pattern for setup/teardown
- [rsync manual](https://download.samba.org/pub/rsync/rsync.1) — mtime+size for skip decisions, --checksum for verification: industry standard incremental backup pattern
- [DatabaseMigrator Structure Reference](https://groue.github.io/GRDB.swift/docs/5.12/Structs/DatabaseMigrator.html) — registerMigration API (older version docs, pattern unchanged in v7)

### Tertiary (LOW confidence)
- [Use Fast Data Algorithms — jolynch.github.io](https://jolynch.github.io/posts/use_fast_data_algorithms/) — backup performance numbers for xxhash vs sha256 (single blog post, unverified but plausible)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — GRDB 7 version and requirements verified against official release; copyfile semantics from Apple man pages; CryptoKit from Apple docs
- Architecture: HIGH — Actor + TaskGroup pattern from architecture research; state machine from pitfalls research; both documented with specific API references
- Pitfalls: HIGH — Pitfalls drawn from project pitfalls research with specific warning signs and prevention strategies
- xxHash performance: MEDIUM — Speed numbers from web search, single source; relative advantage over SHA-256 is consistent across sources

**Research date:** 2026-02-25
**Valid until:** 2026-08-25 (stable APIs — GRDB 7 just released; swift-xxh3 package ecosystem is the main thing to re-verify)
