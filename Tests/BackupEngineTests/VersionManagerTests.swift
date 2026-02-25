import Testing
import Foundation
import GRDB
@testable import BackupEngine

// MARK: - Helpers

/// Seed a database with a project and destination, returning their IDs.
private func seedProjectAndDestination(db: AppDatabase) throws -> (projectID: String, destID: String) {
    let projectID = UUID().uuidString
    let destID = UUID().uuidString
    let project = Project(id: projectID, name: "Test Set", path: "/Music/TestSet-\(projectID)")
    let dest = DestinationConfig(
        id: destID,
        type: .local,
        name: "Test Drive",
        rootPath: "/tmp/backup-\(destID)",
        retentionCount: 10,
        createdAt: Date()
    )
    try db.pool.write { db in
        try dest.insert(db)
        try project.insert(db)
    }
    return (projectID, destID)
}

/// Insert N verified versions for the given (projectID, destinationID) pair.
/// Versions are spaced 1 second apart to guarantee ordering.
private func insertVerifiedVersions(
    count: Int,
    projectID: String,
    destID: String,
    db: AppDatabase,
    baseDate: Date = Date(timeIntervalSince1970: 1_700_000_000)
) throws -> [String] {
    var ids: [String] = []
    for i in 0..<count {
        let createdAt = baseDate.addingTimeInterval(Double(i))
        let id = BackupVersion.makeID(at: createdAt)
        let version = BackupVersion(
            id: id,
            projectID: projectID,
            destinationID: destID,
            status: .verified,
            createdAt: createdAt,
            completedAt: createdAt
        )
        try db.pool.write { db in try version.insert(db) }
        ids.append(id)
    }
    return ids
}

/// Insert a version with a specific status.
private func insertVersion(
    status: VersionStatus,
    projectID: String,
    destID: String,
    db: AppDatabase,
    offset: TimeInterval = 0
) throws -> String {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_000 + offset)
    let id = BackupVersion.makeID(at: baseDate)
    let version = BackupVersion(
        id: id,
        projectID: projectID,
        destinationID: destID,
        status: status,
        createdAt: baseDate,
        completedAt: status == .verified || status == .corrupt ? baseDate : nil
    )
    try db.pool.write { db in try version.insert(db) }
    return id
}

/// Lock a version by inserting a versionLock row.
private func lockVersion(id: String, db: AppDatabase) throws {
    try db.pool.write { db in
        try db.execute(
            sql: "INSERT INTO versionLock (versionID, lockedSince) VALUES (?, ?)",
            arguments: [id, Date()]
        )
    }
}

// MARK: - Test Suite

@Suite("VersionManager")
struct VersionManagerTests {

    // MARK: Version ID Generation

    @Test("newVersionID: two rapid calls produce different IDs")
    func testNewVersionIDUniqueness() {
        let id1 = VersionManager.newVersionID()
        let id2 = VersionManager.newVersionID()
        #expect(id1 != id2, "Two rapid calls to newVersionID() must produce distinct IDs")
    }

    @Test("newVersionID: IDs are lexicographically ordered — earlier call sorts lower")
    func testNewVersionIDLexicographicOrder() async throws {
        let id1 = VersionManager.newVersionID()
        // Small sleep to guarantee different millisecond timestamp
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        let id2 = VersionManager.newVersionID()
        #expect(id1 < id2, "Earlier ID must be lexicographically less than later ID")
    }

    @Test("newVersionID: format matches yyyy-MM-dd'T'HHmmss.SSS-XXXXXXXX pattern")
    func testNewVersionIDFormat() {
        let id = VersionManager.newVersionID()
        // Expected: "2026-02-25T143022.456-a3f8b12c"
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{6}\.\d{3}-[a-f0-9]{8}$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(id.startIndex..., in: id)
        let match = regex?.firstMatch(in: id, range: range)
        #expect(match != nil, "ID '\(id)' does not match expected format 'YYYY-MM-DDTHHmmss.SSS-xxxxxxxx'")
    }

    // MARK: Pruning — Basic Retention

    @Test("pruneOldVersions: 5 verified versions, retentionCount=10 — nothing pruned")
    func testPruneNothingWhenUnderRetention() async throws {
        let db = try AppDatabase.makeInMemory()
        let (projectID, destID) = try seedProjectAndDestination(db: db)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prune-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let ids = try insertVerifiedVersions(count: 5, projectID: projectID, destID: destID, db: db)
        // Create fake version dirs so FileManager.removeItem doesn't crash
        for id in ids {
            let versionDir = (tempDir as NSString).appendingPathComponent(id)
            try FileManager.default.createDirectory(atPath: versionDir, withIntermediateDirectories: true)
        }

        let deleted = try await VersionManager.pruneOldVersions(
            for: projectID,
            destinationID: destID,
            retentionCount: 10,
            destinationRootPath: tempDir,
            db: db.pool
        )

        #expect(deleted.isEmpty, "Expected nothing pruned when verified count (5) <= retentionCount (10)")

        // Verify DB has all 5 versions still as verified
        let remaining = try await db.pool.read { db in
            try BackupVersion
                .filter(Column("projectID") == projectID && Column("destinationID") == destID && Column("status") == VersionStatus.verified.rawValue)
                .fetchAll(db)
        }
        #expect(remaining.count == 5)
    }

    @Test("pruneOldVersions: 11 verified versions, retentionCount=10 — 1 oldest deleted, 10 remain")
    func testPruneOneVersionWhenOverRetention() async throws {
        let db = try AppDatabase.makeInMemory()
        let (projectID, destID) = try seedProjectAndDestination(db: db)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prune-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let ids = try insertVerifiedVersions(count: 11, projectID: projectID, destID: destID, db: db)
        for id in ids {
            let versionDir = (tempDir as NSString).appendingPathComponent(id)
            try FileManager.default.createDirectory(atPath: versionDir, withIntermediateDirectories: true)
        }

        let deleted = try await VersionManager.pruneOldVersions(
            for: projectID,
            destinationID: destID,
            retentionCount: 10,
            destinationRootPath: tempDir,
            db: db.pool
        )

        #expect(deleted.count == 1, "Expected exactly 1 version pruned (11 - 10 = 1)")
        #expect(deleted[0] == ids[0], "Oldest version (index 0) should be pruned first")

        // Verify 10 remain as verified, 1 as deleting
        let verified = try await db.pool.read { db in
            try BackupVersion
                .filter(Column("projectID") == projectID && Column("destinationID") == destID && Column("status") == VersionStatus.verified.rawValue)
                .fetchAll(db)
        }
        #expect(verified.count == 10)
    }

    @Test("pruneOldVersions: 12 verified versions, retentionCount=10 — 2 oldest deleted, 10 remain")
    func testPruneTwoVersionsWhenOverRetentionByTwo() async throws {
        let db = try AppDatabase.makeInMemory()
        let (projectID, destID) = try seedProjectAndDestination(db: db)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prune-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let ids = try insertVerifiedVersions(count: 12, projectID: projectID, destID: destID, db: db)
        for id in ids {
            let versionDir = (tempDir as NSString).appendingPathComponent(id)
            try FileManager.default.createDirectory(atPath: versionDir, withIntermediateDirectories: true)
        }

        let deleted = try await VersionManager.pruneOldVersions(
            for: projectID,
            destinationID: destID,
            retentionCount: 10,
            destinationRootPath: tempDir,
            db: db.pool
        )

        #expect(deleted.count == 2, "Expected exactly 2 versions pruned (12 - 10 = 2)")
        #expect(deleted.contains(ids[0]), "Oldest version (index 0) should be pruned")
        #expect(deleted.contains(ids[1]), "Second oldest version (index 1) should be pruned")

        let verified = try await db.pool.read { db in
            try BackupVersion
                .filter(Column("projectID") == projectID && Column("destinationID") == destID && Column("status") == VersionStatus.verified.rawValue)
                .fetchAll(db)
        }
        #expect(verified.count == 10)
    }

    // MARK: Pruning — Corrupt Versions

    @Test("pruneOldVersions: corrupt versions excluded from count — 8 verified + 3 corrupt, retention=10 → nothing pruned")
    func testCorruptVersionsExcludedFromRetentionCount() async throws {
        let db = try AppDatabase.makeInMemory()
        let (projectID, destID) = try seedProjectAndDestination(db: db)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prune-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Insert 8 verified and 3 corrupt versions (total 11, but only 8 are verified)
        let verifiedIDs = try insertVerifiedVersions(count: 8, projectID: projectID, destID: destID, db: db)
        for i in 0..<3 {
            let corruptID = try insertVersion(
                status: .corrupt,
                projectID: projectID,
                destID: destID,
                db: db,
                offset: Double(100 + i)  // Different offset to avoid ID collision
            )
            let versionDir = (tempDir as NSString).appendingPathComponent(corruptID)
            try FileManager.default.createDirectory(atPath: versionDir, withIntermediateDirectories: true)
        }
        for id in verifiedIDs {
            let versionDir = (tempDir as NSString).appendingPathComponent(id)
            try FileManager.default.createDirectory(atPath: versionDir, withIntermediateDirectories: true)
        }

        let deleted = try await VersionManager.pruneOldVersions(
            for: projectID,
            destinationID: destID,
            retentionCount: 10,
            destinationRootPath: tempDir,
            db: db.pool
        )

        #expect(deleted.isEmpty, "Corrupt versions don't count toward retention — 8 verified < 10, so nothing pruned")

        // Corrupt versions must still exist
        let corruptVersions = try await db.pool.read { db in
            try BackupVersion
                .filter(Column("projectID") == projectID && Column("destinationID") == destID && Column("status") == VersionStatus.corrupt.rawValue)
                .fetchAll(db)
        }
        #expect(corruptVersions.count == 3, "Corrupt versions must be preserved (never pruned)")
    }

    // MARK: Pruning — Locked Versions

    @Test("pruneOldVersions: locked version skipped even when excess — 11 verified, 1 locked → locked is kept, 10 remain verified")
    func testLockedVersionSkippedDuringPruning() async throws {
        let db = try AppDatabase.makeInMemory()
        let (projectID, destID) = try seedProjectAndDestination(db: db)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prune-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Insert 11 verified versions
        let ids = try insertVerifiedVersions(count: 11, projectID: projectID, destID: destID, db: db)
        for id in ids {
            let versionDir = (tempDir as NSString).appendingPathComponent(id)
            try FileManager.default.createDirectory(atPath: versionDir, withIntermediateDirectories: true)
        }

        // Lock the OLDEST version (the one that would normally be pruned)
        let lockedID = ids[0]
        try lockVersion(id: lockedID, db: db)

        let deleted = try await VersionManager.pruneOldVersions(
            for: projectID,
            destinationID: destID,
            retentionCount: 10,
            destinationRootPath: tempDir,
            db: db.pool
        )

        // The locked version must NOT be deleted. The next oldest (ids[1]) should be deleted instead.
        #expect(!deleted.contains(lockedID), "Locked version must not be pruned")
        #expect(deleted.count == 1, "Exactly 1 non-locked excess version should be pruned")
        #expect(deleted[0] == ids[1], "The second-oldest (first non-locked excess) should be pruned")

        // The locked version should still be verified
        let lockedVersion = try await db.pool.read { db in
            try BackupVersion.fetchOne(db, key: lockedID)
        }
        #expect(lockedVersion?.status == .verified, "Locked version must remain verified")
    }

    // MARK: Pruning — Non-Verified Statuses

    @Test("pruneOldVersions: only verified versions are candidates — pending/copying/verifying are not pruned")
    func testOnlyVerifiedVersionsAreCandidates() async throws {
        let db = try AppDatabase.makeInMemory()
        let (projectID, destID) = try seedProjectAndDestination(db: db)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prune-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Insert 5 verified + non-verified statuses that should never be pruned
        let verifiedIDs = try insertVerifiedVersions(count: 5, projectID: projectID, destID: destID, db: db)
        let nonVerifiedStatuses: [VersionStatus] = [.pending, .copying, .copy_complete, .verifying]
        for (i, status) in nonVerifiedStatuses.enumerated() {
            let id = try insertVersion(
                status: status,
                projectID: projectID,
                destID: destID,
                db: db,
                offset: Double(200 + i)
            )
            let versionDir = (tempDir as NSString).appendingPathComponent(id)
            try FileManager.default.createDirectory(atPath: versionDir, withIntermediateDirectories: true)
        }
        for id in verifiedIDs {
            let versionDir = (tempDir as NSString).appendingPathComponent(id)
            try FileManager.default.createDirectory(atPath: versionDir, withIntermediateDirectories: true)
        }

        let deleted = try await VersionManager.pruneOldVersions(
            for: projectID,
            destinationID: destID,
            retentionCount: 10,
            destinationRootPath: tempDir,
            db: db.pool
        )

        #expect(deleted.isEmpty, "Non-verified versions must not be pruned; only 5 verified < 10, so nothing pruned")

        // Verify all non-verified statuses remain intact
        for status in nonVerifiedStatuses {
            let count = try await db.pool.read { db in
                try BackupVersion
                    .filter(Column("projectID") == projectID && Column("destinationID") == destID && Column("status") == status.rawValue)
                    .fetchCount(db)
            }
            #expect(count == 1, "Status \(status.rawValue) version must not be pruned")
        }
    }
}
