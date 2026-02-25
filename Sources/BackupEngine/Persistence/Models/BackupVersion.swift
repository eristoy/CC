import GRDB
import Foundation

/// A versioned snapshot of an Ableton project backup.
///
/// ID format: "{ISO8601-ms}-{UUID-prefix-8}"
///   e.g., "2026-02-25T143022.456-a3f8b12c"
///
/// Only `verified` versions count toward retention limit or are eligible for pruning/restore.
public struct BackupVersion: Codable, Sendable {
    public var id: String                   // e.g., "2026-02-25T143022.456-a3f8b12c"
    public var projectID: String
    public var destinationID: String
    public var status: VersionStatus
    public var fileCount: Int?              // set when copy_complete
    public var totalBytes: Int?             // set when copy_complete
    public var createdAt: Date
    public var completedAt: Date?           // set when verified or corrupt
    public var errorMessage: String?

    public init(
        id: String,
        projectID: String,
        destinationID: String,
        status: VersionStatus = .pending,
        fileCount: Int? = nil,
        totalBytes: Int? = nil,
        createdAt: Date,
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.destinationID = destinationID
        self.status = status
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }

    /// Generate a new version ID with millisecond-precision timestamp + UUID prefix.
    public static func makeID(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timestamp = formatter.string(from: date)
        let uuidPrefix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)
        return "\(timestamp)-\(uuidPrefix)"
    }
}

// MARK: - GRDB Conformances

extension BackupVersion: TableRecord {
    public static let databaseTableName = "backupVersion"
}

extension BackupVersion: FetchableRecord {}
extension BackupVersion: PersistableRecord {}
