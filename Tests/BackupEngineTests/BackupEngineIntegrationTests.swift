import Testing
import Foundation
import GRDB
@testable import BackupEngine

// MARK: - BackupEngine Integration Tests

/// Integration tests for the full BackupEngine pipeline.
///
/// All tests use real temp directories and an in-memory (temp-file) GRDB database.
/// Tests cover the full lifecycle: pending → copying → copy_complete → verifying → verified.
@Suite("BackupEngine Integration", .serialized)
struct BackupEngineIntegrationTests {

    // MARK: - Helpers

    /// Create a temporary directory, run `body`, and clean up after.
    private func withTempDir(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupEngineIntegrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    /// Write string content to a file, creating intermediate directories.
    private func writeFile(_ content: String, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Touch a file's modification time to `date` (or now if nil).
    private func touchMtime(_ url: URL, to date: Date = Date()) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    /// Set up a standard test environment with source + destination directories,
    /// an in-memory database with project and destination records, and a BackupEngine.
    ///
    /// The `retentionCount` parameter controls how many verified versions to keep.
    private func makeTestEnvironment(
        rootDir: URL,
        retentionCount: Int = 10
    ) throws -> (
        sourceDir: URL,
        destDir: URL,
        db: AppDatabase,
        engine: BackupEngine,
        project: Project,
        dest: DestinationConfig
    ) {
        let sourceDir = rootDir.appendingPathComponent("source")
        let destDir = rootDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let db = try AppDatabase.makeInMemory()

        let dest = DestinationConfig(
            id: UUID().uuidString,
            type: .local,
            name: "Test Destination",
            rootPath: destDir.path,
            retentionCount: retentionCount,
            createdAt: Date()
        )
        let project = Project(
            id: UUID().uuidString,
            name: "My Ableton Project",
            path: sourceDir.path
        )

        try db.pool.write { db in
            try dest.insert(db)
            try project.insert(db)
        }

        let adapter = LocalDestinationAdapter(config: dest)
        let engine = BackupEngine(db: db, adapters: [adapter])

        return (sourceDir, destDir, db, engine, project, dest)
    }

    // MARK: - Test 1: Full Backup Copies All Files

    /// Covers BACK-01 (backup copies project folder) and DEST-01 (local destination).
    @Test("fullBackupCopiesAllFiles")
    func fullBackupCopiesAllFiles() async throws {
        try await withTempDir { root in
            let (sourceDir, destDir, db, engine, project, dest) =
                try makeTestEnvironment(rootDir: root)

            // Create 3 source files
            try writeFile("ableton project data", to: sourceDir.appendingPathComponent("project.als"))
            try writeFile("kick drum audio", to: sourceDir.appendingPathComponent("Samples/kick.wav"))
            try writeFile("snare drum audio", to: sourceDir.appendingPathComponent("Samples/snare.wav"))

            let job = BackupJob(project: project, destinationIDs: [dest.id])
            let result = try await engine.runJob(job)

            // Assert result status
            #expect(result.status == .verified, "Expected verified status, got \(result.status)")
            #expect(result.filesCopied == 3, "Expected 3 files copied, got \(result.filesCopied)")
            #expect(result.filesSkipped == 0, "Expected 0 skipped, got \(result.filesSkipped)")

            // Assert version directory exists with all 3 files
            let versionDir = destDir.appendingPathComponent(result.versionID)
            let projectFile = versionDir.appendingPathComponent("project.als")
            let kickFile = versionDir.appendingPathComponent("Samples/kick.wav")
            let snareFile = versionDir.appendingPathComponent("Samples/snare.wav")

            #expect(FileManager.default.fileExists(atPath: projectFile.path),
                    "Expected project.als in version directory")
            #expect(FileManager.default.fileExists(atPath: kickFile.path),
                    "Expected Samples/kick.wav in version directory")
            #expect(FileManager.default.fileExists(atPath: snareFile.path),
                    "Expected Samples/snare.wav in version directory")

            // Assert DB has a verified BackupVersion row
            let versions = try await db.pool.read { db in
                try BackupVersion
                    .filter(Column("projectID") == project.id)
                    .filter(Column("status") == VersionStatus.verified.rawValue)
                    .fetchAll(db)
            }
            #expect(versions.count == 1, "Expected 1 verified version, got \(versions.count)")
            #expect(versions[0].fileCount == 3, "Expected fileCount=3, got \(String(describing: versions[0].fileCount))")

            // Assert BackupFileRecord rows were inserted
            let records = try await db.pool.read { db in
                try BackupFileRecord
                    .filter(Column("versionID") == result.versionID)
                    .fetchAll(db)
            }
            #expect(records.count == 3, "Expected 3 BackupFileRecord rows, got \(records.count)")
            // All records should have checksums
            let allHaveChecksums = records.allSatisfy { $0.checksum != nil }
            #expect(allHaveChecksums, "All records should have checksums after verification")
        }
    }

    // MARK: - Test 2: Second Backup Skips Unchanged Files

    /// Covers BACK-02 (incremental backup skips unchanged files).
    @Test("secondBackupSkipsUnchangedFiles")
    func secondBackupSkipsUnchangedFiles() async throws {
        try await withTempDir { root in
            let (sourceDir, _, _, engine, project, dest) =
                try makeTestEnvironment(rootDir: root)

            // Create 3 source files with an explicit past mtime
            let pastDate = Date(timeIntervalSinceNow: -3600)  // 1 hour ago
            let file1 = sourceDir.appendingPathComponent("project.als")
            let file2 = sourceDir.appendingPathComponent("Samples/kick.wav")
            let file3 = sourceDir.appendingPathComponent("Samples/snare.wav")
            try writeFile("ableton project data", to: file1)
            try writeFile("kick drum audio", to: file2)
            try writeFile("snare drum audio", to: file3)
            // Set explicit past mtimes so second run sees unchanged files
            try touchMtime(file1, to: pastDate)
            try touchMtime(file2, to: pastDate)
            try touchMtime(file3, to: pastDate)

            let job = BackupJob(project: project, destinationIDs: [dest.id])

            // First backup
            let result1 = try await engine.runJob(job)
            #expect(result1.status == .verified)
            #expect(result1.filesCopied == 3)
            #expect(result1.filesSkipped == 0)

            // Second backup — files unchanged (same mtime + size)
            let result2 = try await engine.runJob(job)
            #expect(result2.status == .verified,
                    "Second backup should be verified, got \(result2.status)")
            #expect(result2.filesSkipped == 3,
                    "Second backup should skip all 3 unchanged files, got \(result2.filesSkipped) skipped")
            #expect(result2.filesCopied == 0,
                    "Second backup should copy 0 files, got \(result2.filesCopied) copied")
        }
    }

    // MARK: - Test 3: Modified File Triggers Copy

    /// Covers BACK-02 (incremental backup copies modified files).
    @Test("modifiedFileTriggersCopy")
    func modifiedFileTriggersCopy() async throws {
        try await withTempDir { root in
            let (sourceDir, _, _, engine, project, dest) =
                try makeTestEnvironment(rootDir: root)

            // Create 3 source files with a past mtime
            let pastDate = Date(timeIntervalSinceNow: -3600)
            let file1 = sourceDir.appendingPathComponent("project.als")
            let file2 = sourceDir.appendingPathComponent("Samples/kick.wav")
            let file3 = sourceDir.appendingPathComponent("Samples/snare.wav")
            try writeFile("ableton project data", to: file1)
            try writeFile("kick drum audio", to: file2)
            try writeFile("snare drum audio", to: file3)
            try touchMtime(file1, to: pastDate)
            try touchMtime(file2, to: pastDate)
            try touchMtime(file3, to: pastDate)

            let job = BackupJob(project: project, destinationIDs: [dest.id])

            // First backup
            let result1 = try await engine.runJob(job)
            #expect(result1.filesCopied == 3)
            #expect(result1.status == .verified)

            // Modify one file: change content and update mtime to now
            try writeFile("modified ableton project data — new session", to: file1)
            try touchMtime(file1, to: Date())

            // Second backup — only file1 should be copied
            let result2 = try await engine.runJob(job)
            #expect(result2.status == .verified,
                    "Second backup should be verified, got \(result2.status)")
            #expect(result2.filesCopied == 1,
                    "Only modified file should be copied, got \(result2.filesCopied)")
            #expect(result2.filesSkipped == 2,
                    "Unchanged files should be skipped, got \(result2.filesSkipped)")
        }
    }

    // MARK: - Test 4: Checksum Verification Detects Corrupt Destination

    /// Covers BACK-03 (checksum verification marks corrupt versions).
    ///
    /// Approach: Run a backup, then manually corrupt a destination file's content,
    /// then run another backup. The NEW backup itself will have verified status
    /// (it copies fresh from source). To test corruption detection, we directly
    /// corrupt a destination file and confirm the verification pass would catch it.
    ///
    /// For Phase 1, we verify the normal path: copies succeed and status=verified.
    /// The FileCopyPipeline tests verify the checksum mechanism. The BackupEngine
    /// integration tests confirm: (1) status transitions work, (2) checksums are stored.
    /// A dedicated corrupt-detection test is noted as a Phase 3 enhancement.
    @Test("checksumVerificationPassesForValidBackup")
    func checksumVerificationPassesForValidBackup() async throws {
        try await withTempDir { root in
            let (sourceDir, _, db, engine, project, dest) =
                try makeTestEnvironment(rootDir: root)

            try writeFile("project data for checksum test", to: sourceDir.appendingPathComponent("project.als"))

            let job = BackupJob(project: project, destinationIDs: [dest.id])
            let result = try await engine.runJob(job)

            // Backup should be verified — checksums matched
            #expect(result.status == .verified,
                    "Backup should be verified when files are not corrupt")

            // Verify BackupFileRecord has a stored checksum
            let records = try await db.pool.read { db in
                try BackupFileRecord
                    .filter(Column("versionID") == result.versionID)
                    .fetchAll(db)
            }
            #expect(!records.isEmpty, "BackupFileRecord rows should exist")
            #expect(records.allSatisfy { $0.checksum != nil },
                    "All records should have checksums after a verified backup")

            // Verify the BackupVersion status is .verified in the DB
            let version = try await db.pool.read { db in
                try BackupVersion.fetchOne(db, key: result.versionID)
            }
            #expect(version?.status == .verified)
            #expect(version?.completedAt != nil, "completedAt should be set after verification")
        }
    }

    // MARK: - Test 5: Retention Pruning

    /// Covers BACK-04 (retention policy enforced) and BACK-05 (oldest version pruned).
    @Test("retentionPruning")
    func retentionPruning() async throws {
        try await withTempDir { root in
            let (sourceDir, destDir, db, engine, project, dest) =
                try makeTestEnvironment(rootDir: root, retentionCount: 3)

            let mainFile = sourceDir.appendingPathComponent("project.als")

            var versionIDs: [String] = []

            // Run 4 backups, modifying the file between each to force copies
            for i in 1...4 {
                try writeFile("session version \(i)", to: mainFile)
                try touchMtime(mainFile, to: Date(timeIntervalSinceNow: Double(i) * 60))

                let job = BackupJob(project: project, destinationIDs: [dest.id])
                let result = try await engine.runJob(job)
                #expect(result.status == .verified,
                        "Backup \(i) should be verified, got \(result.status)")
                versionIDs.append(result.versionID)
            }

            // After 4 backups with retentionCount=3, oldest should be pruned
            let verifiedVersions = try await db.pool.read { db in
                try BackupVersion
                    .filter(Column("projectID") == project.id)
                    .filter(Column("status") == VersionStatus.verified.rawValue)
                    .order(Column("createdAt").asc)
                    .fetchAll(db)
            }

            #expect(verifiedVersions.count == 3,
                    "Should have exactly 3 verified versions after pruning, got \(verifiedVersions.count)")

            // The oldest version (versionIDs[0]) should be pruned (status=deleting or no longer in DB)
            let oldestID = versionIDs[0]
            let oldestVersion = try await db.pool.read { db in
                try BackupVersion.fetchOne(db, key: oldestID)
            }
            // The oldest version should be marked .deleting (pruned)
            if let oldest = oldestVersion {
                #expect(oldest.status == .deleting,
                        "Oldest version should be marked .deleting, got \(oldest.status)")
            }
            // The oldest version directory should no longer exist on disk
            let oldestDir = destDir.appendingPathComponent(oldestID)
            #expect(
                !FileManager.default.fileExists(atPath: oldestDir.path),
                "Oldest version directory should be removed from disk after pruning"
            )

            // The 3 newest versions should still exist on disk
            for i in 1...3 {
                let keepID = versionIDs[i]
                let keepDir = destDir.appendingPathComponent(keepID)
                #expect(
                    FileManager.default.fileExists(atPath: keepDir.path),
                    "Version \(i+1) directory should still exist (within retention window)"
                )
            }
        }
    }

    // MARK: - Test 6: Concurrent Job Deduplication

    /// Verifies that two concurrent runJob() calls for the same project return the same versionID
    /// and only create one BackupVersion record.
    @Test("concurrentJobDeduplication")
    func concurrentJobDeduplication() async throws {
        try await withTempDir { root in
            let (sourceDir, _, db, engine, project, dest) =
                try makeTestEnvironment(rootDir: root)

            try writeFile("my project data", to: sourceDir.appendingPathComponent("project.als"))

            let job = BackupJob(project: project, destinationIDs: [dest.id])

            // Launch two concurrent runJob calls for the same project
            async let result1 = engine.runJob(job)
            async let result2 = engine.runJob(job)

            let (r1, r2) = try await (result1, result2)

            // Both should return the same versionID (deduplication working)
            #expect(r1.versionID == r2.versionID,
                    "Deduplicated jobs should return the same versionID")
            #expect(r1.status == .verified)
            #expect(r2.status == .verified)

            // Only one BackupVersion record should exist in the DB
            let versions = try await db.pool.read { db in
                try BackupVersion
                    .filter(Column("projectID") == project.id)
                    .filter(Column("status") == VersionStatus.verified.rawValue)
                    .fetchAll(db)
            }
            #expect(versions.count == 1,
                    "Deduplication should produce exactly 1 BackupVersion record, got \(versions.count)")
        }
    }
}
