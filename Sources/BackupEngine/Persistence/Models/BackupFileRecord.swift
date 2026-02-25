import GRDB
import Foundation

/// Per-file manifest entry for a backup version.
///
/// One record per file copied in a backup version. Checksum is null until the
/// verification pass completes.
public struct BackupFileRecord: Codable, Sendable {
    public var rowid: Int64?                // AUTOINCREMENT PRIMARY KEY
    public var versionID: String
    public var relativePath: String         // relative to project root
    public var sourceMtime: Date
    public var sourceSize: Int
    public var checksum: String?            // null until verified
    public var copied: Bool

    public init(
        rowid: Int64? = nil,
        versionID: String,
        relativePath: String,
        sourceMtime: Date,
        sourceSize: Int,
        checksum: String? = nil,
        copied: Bool = false
    ) {
        self.rowid = rowid
        self.versionID = versionID
        self.relativePath = relativePath
        self.sourceMtime = sourceMtime
        self.sourceSize = sourceSize
        self.checksum = checksum
        self.copied = copied
    }
}

// MARK: - GRDB Conformances

extension BackupFileRecord: TableRecord {
    public static let databaseTableName = "backupFileRecord"
}

extension BackupFileRecord: FetchableRecord {}
extension BackupFileRecord: PersistableRecord {
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .abort
    )
}
