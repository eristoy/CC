import Foundation

// MARK: - Supporting Types

/// Progress reported per file during a transfer operation.
public struct TransferProgress: Sendable {
    /// Relative path of the file currently being transferred.
    public let relativePath: String
    /// Bytes copied so far for this file (equals file size when complete).
    public let bytesCopied: Int64
    /// Total number of files in this transfer batch.
    public let totalFiles: Int
    /// Number of files fully transferred so far (including current).
    public let completedFiles: Int

    public init(relativePath: String, bytesCopied: Int64, totalFiles: Int, completedFiles: Int) {
        self.relativePath = relativePath
        self.bytesCopied = bytesCopied
        self.totalFiles = totalFiles
        self.completedFiles = completedFiles
    }
}

/// Availability status returned by DestinationAdapter.probe().
public enum DestinationStatus: Sendable {
    /// Destination is reachable and ready for transfers.
    case available
    /// Destination cannot be reached; includes a human-readable explanation.
    case unavailable(reason: String)
}

// MARK: - Protocol

/// An abstraction over a backup destination (local drive, NAS, iCloud, GitHub LFS).
///
/// Phase 1 implements LocalDestinationAdapter only.
/// Phases 4-6 add NAS, iCloud, and GitHub LFS adapters conforming to this protocol.
///
/// All conforming types must be Sendable (transfer is called from an async context).
public protocol DestinationAdapter: Sendable {
    /// Unique identifier matching DestinationConfig.id.
    var id: String { get }

    /// The configuration record for this destination.
    var config: DestinationConfig { get }

    /// Copy files to the destination for a given backup version.
    ///
    /// - Parameters:
    ///   - files: The files to transfer (from ProjectResolver).
    ///   - versionID: Unique ID for this backup version (used as directory name).
    ///   - progress: Called after each file completes. May be called from any thread.
    /// - Returns: An array of BackupFileRecord with checksums set (one per file copied).
    /// - Throws: On I/O error during copy.
    func transfer(
        _ files: [FileEntry],
        versionID: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws -> [BackupFileRecord]

    /// Prune backup versions beyond the retention count for a project.
    ///
    /// Pruning is orchestrated by VersionManager (plan 01-04).
    /// This method is called after VersionManager marks a version as `.deleting`.
    ///
    /// - Parameters:
    ///   - retentionCount: Maximum number of versions to keep.
    ///   - projectID: The project whose old versions should be pruned.
    /// - Throws: On I/O error during deletion.
    func pruneVersions(beyond retentionCount: Int, for projectID: String) async throws

    /// Check whether this destination is reachable. Must complete within 3 seconds.
    ///
    /// - Returns: `.available` if the destination is ready; `.unavailable(reason:)` otherwise.
    func probe() async -> DestinationStatus
}
