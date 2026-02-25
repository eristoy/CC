import Foundation

/// A backup destination adapter that writes to a locally attached drive or directory.
///
/// Directory structure on disk:
/// ```
/// {config.rootPath}/
///   {versionID}/
///     {relativePath}          ← preserves source directory structure
///     Samples/kick.wav
///     Samples/snare.wav
///     MyProject.als
/// ```
///
/// This is the Phase 1 implementation of DestinationAdapter.
/// Phases 4-6 will add NASDestinationAdapter, iCloudDestinationAdapter, and GitHubDestinationAdapter.
public struct LocalDestinationAdapter: DestinationAdapter {

    // MARK: - DestinationAdapter Properties

    public let id: String
    public let config: DestinationConfig

    // MARK: - Initialization

    public init(config: DestinationConfig) {
        self.id = config.id
        self.config = config
    }

    // MARK: - DestinationAdapter Implementation

    /// Copy files to a versioned directory on the local destination.
    ///
    /// Creates `{rootPath}/{versionID}/` and copies each file preserving its relative path.
    /// Each file is copied via FileCopyPipeline.copyFileWithChecksum (APFS clone or chunked fallback).
    /// Progress is reported after each file completes.
    ///
    /// - Parameters:
    ///   - files: Files to copy (from ProjectResolver.resolve).
    ///   - versionID: Backup version identifier — used as the version directory name.
    ///   - progress: Called after each file with cumulative transfer stats.
    /// - Returns: BackupFileRecord array with checksums set, one per copied file.
    /// - Throws: On file system errors (directory creation failure, copy failure).
    public func transfer(
        _ files: [FileEntry],
        versionID: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws -> [BackupFileRecord] {
        let rootURL = URL(fileURLWithPath: config.rootPath)
        // Version directory: {rootPath}/{versionID}/
        let versionDir = rootURL.appendingPathComponent(versionID)
        try FileManager.default.createDirectory(
            at: versionDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var records: [BackupFileRecord] = []
        records.reserveCapacity(files.count)

        for (index, file) in files.enumerated() {
            // Destination preserves relative path structure under the version directory
            let destURL = versionDir.appendingPathComponent(file.relativePath)

            let checksum = try FileCopyPipeline.copyFileWithChecksum(
                source: file.url,
                destination: destURL
            )

            records.append(BackupFileRecord(
                rowid: nil,
                versionID: versionID,
                relativePath: file.relativePath,
                sourceMtime: file.mtime,
                sourceSize: Int(file.size),
                checksum: checksum,
                copied: true
            ))

            progress(TransferProgress(
                relativePath: file.relativePath,
                bytesCopied: file.size,
                totalFiles: files.count,
                completedFiles: index + 1
            ))
        }

        return records
    }

    /// Prune backup versions beyond the retention count for a project.
    ///
    /// This is a documented stub for Phase 1. Pruning is orchestrated by VersionManager (plan 01-04),
    /// which marks versions as `.deleting` before calling this method.
    ///
    /// For now this is a no-op — safe because nothing is deleted until VersionManager confirms it.
    /// Full implementation: plan 01-04 will define the pruning contract and call this method.
    public func pruneVersions(beyond retentionCount: Int, for projectID: String) async throws {
        // TODO: implement in plan 01-04 when VersionManager defines the pruning contract.
        // Implementation outline:
        //   1. List subdirectories of rootPath sorted by name (ISO8601-sortable version IDs)
        //   2. Filter to directories marked for deletion by VersionManager (status=.deleting in DB)
        //   3. Delete those directories from disk
        // No-op is safe: nothing is deleted until VersionManager marks the version as deleting.
    }

    /// Check whether the destination root directory exists and is reachable.
    ///
    /// - Returns: `.available` if `config.rootPath` exists; `.unavailable(reason:)` otherwise.
    public func probe() async -> DestinationStatus {
        let rootURL = URL(fileURLWithPath: config.rootPath)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: rootURL.path,
            isDirectory: &isDirectory
        )
        if exists && isDirectory.boolValue {
            return .available
        } else if exists {
            return .unavailable(reason: "Path exists but is not a directory: \(config.rootPath)")
        } else {
            return .unavailable(reason: "Directory does not exist: \(config.rootPath)")
        }
    }
}
