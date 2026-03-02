import GRDB
import Foundation

/// A watched folder record — one row per directory being monitored for Ableton project changes.
///
/// GRDB model conformances:
/// - `TableRecord`: maps to "watchFolder" SQLite table
/// - `FetchableRecord`: read rows from DB
/// - `PersistableRecord`: insert/update/delete rows in DB
public struct WatchFolder: Codable, Sendable, Identifiable, Hashable {
    /// UUID string primary key.
    public var id: String
    /// Absolute filesystem path. UNIQUE — enforced by DB constraint.
    public var path: String
    /// Human-readable name — typically `url.lastPathComponent`.
    public var name: String
    /// When this folder was added to the watch list.
    public var addedAt: Date
    /// When an .als change in this folder last triggered a backup. Nil until first trigger.
    public var lastTriggeredAt: Date?

    public init(
        id: String = UUID().uuidString,
        path: String,
        name: String,
        addedAt: Date = Date(),
        lastTriggeredAt: Date? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.addedAt = addedAt
        self.lastTriggeredAt = lastTriggeredAt
    }
}

extension WatchFolder: TableRecord {
    public static let databaseTableName = "watchFolder"
}

extension WatchFolder: FetchableRecord {}
extension WatchFolder: PersistableRecord {}
