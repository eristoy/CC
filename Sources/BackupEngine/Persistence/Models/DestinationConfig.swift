import GRDB
import Foundation

/// The type of a backup destination.
///
/// Phase 1 implements `.local` only.
/// Enum designed for extensibility: phases 4-6 will add nas, icloud, github.
public enum DestinationType: String, Codable, Sendable {
    case local
    case nas
    case icloud
    case github
}

/// Configuration for a backup destination (where backups are stored).
///
/// retentionCount is stored per destination (not per project).
/// Default retentionCount: 10
public struct DestinationConfig: Codable, Sendable {
    public var id: String                   // UUID string
    public var type: DestinationType
    public var name: String
    public var rootPath: String
    public var retentionCount: Int
    public var createdAt: Date

    public init(
        id: String,
        type: DestinationType,
        name: String,
        rootPath: String,
        retentionCount: Int = 10,
        createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.rootPath = rootPath
        self.retentionCount = retentionCount
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformances

extension DestinationConfig: TableRecord {
    public static let databaseTableName = "destination"
}

extension DestinationConfig: FetchableRecord {}
extension DestinationConfig: PersistableRecord {}
