import Foundation
import GRDB

/// Manages backup version lifecycle: ID generation and retention pruning.
///
/// Full implementation: plan 01-04 (BackupOrchestrator and VersionManager).
/// This stub satisfies compilation of VersionManagerTests.swift (TDD RED file for plan 01-04).
public enum VersionManager {

    /// Generate a new version ID with millisecond-precision timestamp + UUID prefix.
    ///
    /// Format: "yyyy-MM-dd'T'HHmmss.SSS-xxxxxxxx"
    /// Example: "2026-02-25T143022.456-a3f8b12c"
    ///
    /// IDs are lexicographically sortable by creation time.
    public static func newVersionID() -> String {
        return BackupVersion.makeID()
    }

    /// Prune backup versions beyond the retention count for a project/destination pair.
    ///
    /// Only `.verified` versions are candidates for pruning.
    /// Versions with a `versionLock` row are skipped.
    /// Corrupt, pending, copying, copy_complete, and verifying versions are never pruned.
    ///
    /// - Parameters:
    ///   - projectID: The project whose versions to prune.
    ///   - destinationID: The destination to prune versions for.
    ///   - retentionCount: Maximum number of verified versions to keep.
    ///   - destinationRootPath: Root path of the destination (for directory deletion).
    ///   - db: The DatabasePool to use for reads/writes.
    /// - Returns: Array of version IDs that were deleted.
    /// - Throws: On database or file system errors.
    public static func pruneOldVersions(
        for projectID: String,
        destinationID: String,
        retentionCount: Int,
        destinationRootPath: String,
        db: DatabasePool
    ) async throws -> [String] {
        // Stub — full implementation in plan 01-04.
        return []
    }
}
