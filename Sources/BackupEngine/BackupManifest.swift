import Foundation

/// A completed-version file inventory: records every file, its size, and its checksum.
///
/// Built by BackupEngine after transfer() completes. Passed to VersionManager.finalizeCopy()
/// to update the BackupVersion row (fileCount, totalBytes, status=copy_complete).
public struct BackupManifest: Sendable {
    public let versionID: String
    public let projectID: String
    public let destinationID: String
    public let files: [ManifestEntry]

    public var totalFiles: Int { files.count }
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    public init(
        versionID: String,
        projectID: String,
        destinationID: String,
        files: [ManifestEntry]
    ) {
        self.versionID = versionID
        self.projectID = projectID
        self.destinationID = destinationID
        self.files = files
    }
}

/// A single file entry inside a BackupManifest.
///
/// relativePath is relative to the project root (same as BackupFileRecord.relativePath).
public struct ManifestEntry: Sendable {
    public let relativePath: String
    public let size: Int64
    public let checksum: String

    public init(relativePath: String, size: Int64, checksum: String) {
        self.relativePath = relativePath
        self.size = size
        self.checksum = checksum
    }
}
