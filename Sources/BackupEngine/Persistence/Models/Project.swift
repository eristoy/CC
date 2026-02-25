import GRDB
import Foundation

/// An Ableton Live project being backed up.
///
/// `path` is unique — each project has exactly one path on disk.
/// `lastBackupAt` is updated when a backup version reaches `verified` status.
public struct Project: Codable, Sendable {
    public var id: String                   // UUID string
    public var name: String
    public var path: String                 // UNIQUE — absolute path to .als project root
    public var lastBackupAt: Date?

    public init(
        id: String,
        name: String,
        path: String,
        lastBackupAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.lastBackupAt = lastBackupAt
    }
}

// MARK: - GRDB Conformances

extension Project: TableRecord {
    public static let databaseTableName = "project"
}

extension Project: FetchableRecord {}
extension Project: PersistableRecord {}
