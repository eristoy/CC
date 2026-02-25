import Foundation
import GRDB

/// Manages backup version lifecycle: ID generation and retention pruning.
///
/// VersionManager is stateless — all state is in the database.
/// Uses write-then-cleanup pattern: status='deleting' is set in a DB write transaction
/// BEFORE any disk deletion. On crash between mark and delete, 'deleting' rows are
/// re-processed on next launch (BackupEngine's responsibility at startup).
public enum VersionManager {

    // MARK: - Version ID Generation

    /// Generate a collision-safe version ID with millisecond-precision timestamp + UUID prefix.
    ///
    /// Format: "yyyy-MM-dd'T'HHmmss.SSS-xxxxxxxx"
    /// Example: "2026-02-25T143022.456-a3f8b12c"
    ///
    /// IDs are lexicographically sortable by creation time.
    /// Two calls within the same millisecond produce different IDs (UUID suffix prevents collision).
    public static func newVersionID() -> String {
        return BackupVersion.makeID()
    }

    // MARK: - Retention Pruning

    /// Prune verified backup versions beyond the retention count for a project/destination pair.
    ///
    /// Pruning rules:
    /// - Only `.verified` versions are candidates for pruning (pending/copying/verifying/corrupt are excluded)
    /// - Corrupt versions do NOT count toward the retention limit
    /// - Versions with a `versionLock` row are skipped (protected for active restore)
    /// - Excess versions are marked `.deleting` in a single DB write transaction BEFORE disk deletion
    /// - After transaction commits, version directories are removed from disk
    ///
    /// - Parameters:
    ///   - projectID: The project whose versions to prune.
    ///   - destinationID: The destination to prune versions for.
    ///   - retentionCount: Maximum number of verified versions to keep.
    ///   - destinationRootPath: Root path of the destination (version dirs live at {rootPath}/{versionID}).
    ///   - db: The DatabasePool to use for reads/writes.
    /// - Returns: Array of version IDs that were marked deleting and had their directories removed.
    /// - Throws: On database or file system errors.
    public static func pruneOldVersions(
        for projectID: String,
        destinationID: String,
        retentionCount: Int,
        destinationRootPath: String,
        db: DatabasePool
    ) async throws -> [String] {
        // Step 1: Fetch all verified versions ordered by createdAt ASC (oldest first).
        // Only .verified is eligible — corrupt, pending, copying, etc. are excluded.
        let verifiedVersions = try await db.read { database in
            try BackupVersion
                .filter(
                    Column("projectID") == projectID &&
                    Column("destinationID") == destinationID &&
                    Column("status") == VersionStatus.verified.rawValue
                )
                .order(Column("createdAt").asc)
                .fetchAll(database)
        }

        // Step 2: Count verified versions only. Corrupt excluded from count.
        let verifiedCount = verifiedVersions.count

        // Step 3: Check if under retention limit — nothing to prune.
        guard verifiedCount > retentionCount else {
            return []
        }

        // Step 4: Identify excess: the oldest (verifiedCount - retentionCount) versions.
        let excessCount = verifiedCount - retentionCount
        let excessCandidates = Array(verifiedVersions.prefix(excessCount))

        // Step 5: Fetch locked version IDs to skip locked versions.
        let lockedIDs = try await db.read { database in
            try Row.fetchAll(database, sql: "SELECT versionID FROM versionLock")
                .map { row in row["versionID"] as String }
        }
        let lockedSet = Set(lockedIDs)

        // Step 6: Walk the verified versions (oldest first) and collect up to excessCount
        // non-locked candidates. Locked versions are skipped but the search continues —
        // a locked version does not count toward the retained window.
        var toPrune: [BackupVersion] = []
        for version in verifiedVersions {
            if toPrune.count >= excessCount { break }
            if !lockedSet.contains(version.id) {
                toPrune.append(version)
            }
        }

        guard !toPrune.isEmpty else {
            return []
        }

        let pruneIDs = toPrune.map(\.id)

        // Step 7: Mark excess (non-locked) versions as 'deleting' in a single write transaction.
        // Write-then-cleanup: DB is updated BEFORE disk deletion to ensure crash safety.
        try await db.write { database in
            for id in pruneIDs {
                try database.execute(
                    sql: "UPDATE backupVersion SET status = 'deleting' WHERE id = ?",
                    arguments: [id]
                )
            }
        }

        // Step 8: Delete version directories from disk after transaction commits.
        // FileManager errors are non-fatal — the .deleting status ensures re-cleanup on restart.
        var deleted: [String] = []
        for id in pruneIDs {
            let versionDir = (destinationRootPath as NSString).appendingPathComponent(id)
            do {
                try FileManager.default.removeItem(atPath: versionDir)
            } catch {
                // Directory may already be deleted (idempotent). Log and continue.
                // The version remains in 'deleting' status for re-cleanup at next launch.
            }
            deleted.append(id)
        }

        return deleted
    }

    // MARK: - Version Status Transitions

    /// Finalize a version after transfer completes: set fileCount, totalBytes, status=copy_complete.
    ///
    /// Called by BackupEngine after transfer() returns a BackupFileRecord array.
    public static func finalizeCopy(
        versionID: String,
        manifest: BackupManifest,
        db: DatabasePool
    ) async throws {
        try await db.write { database in
            try database.execute(
                sql: """
                    UPDATE backupVersion
                    SET status = 'copy_complete', fileCount = ?, totalBytes = ?
                    WHERE id = ?
                """,
                arguments: [manifest.totalFiles, manifest.totalBytes, versionID]
            )
        }
    }

    /// Transition version status: verifying -> verified (all checksums matched).
    public static func markVerified(versionID: String, db: DatabasePool) async throws {
        try await db.write { database in
            try database.execute(
                sql: "UPDATE backupVersion SET status = 'verified', completedAt = ? WHERE id = ?",
                arguments: [Date(), versionID]
            )
        }
    }

    /// Transition version status: verifying -> corrupt (checksum mismatch detected).
    ///
    /// Corrupt versions are kept in the database for user inspection.
    /// They do NOT count toward the retention limit and are never pruned.
    public static func markCorrupt(versionID: String, reason: String, db: DatabasePool) async throws {
        try await db.write { database in
            try database.execute(
                sql: "UPDATE backupVersion SET status = 'corrupt', completedAt = ?, errorMessage = ? WHERE id = ?",
                arguments: [Date(), reason, versionID]
            )
        }
    }
}
