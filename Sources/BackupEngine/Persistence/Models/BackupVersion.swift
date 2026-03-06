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

    // MARK: - ALS Sample Tracking (v3 schema — Phase 5)

    /// Number of external samples successfully collected into Samples/Imported/.
    public var collectedSampleCount: Int

    /// JSON array of collected sample path strings (absolute paths on source machine).
    /// Use `BackupVersion.decodePaths(_:)` to decode.  Nil if no external samples were collected.
    public var collectedSamplePaths: String?

    /// Number of external samples that could not be found (missing/offline at backup time).
    public var missingSampleCount: Int

    /// JSON array of missing sample path strings (absolute paths on source machine).
    /// Use `BackupVersion.decodePaths(_:)` to decode.  Nil if no samples were missing.
    public var missingSamplePaths: String?

    /// true if the .als file could not be parsed.  Backup proceeded with plain folder copy.
    public var hasParseWarning: Bool

    public init(
        id: String,
        projectID: String,
        destinationID: String,
        status: VersionStatus = .pending,
        fileCount: Int? = nil,
        totalBytes: Int? = nil,
        createdAt: Date,
        completedAt: Date? = nil,
        errorMessage: String? = nil,
        collectedSampleCount: Int = 0,
        collectedSamplePaths: String? = nil,
        missingSampleCount: Int = 0,
        missingSamplePaths: String? = nil,
        hasParseWarning: Bool = false
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
        self.collectedSampleCount = collectedSampleCount
        self.collectedSamplePaths = collectedSamplePaths
        self.missingSampleCount = missingSampleCount
        self.missingSamplePaths = missingSamplePaths
        self.hasParseWarning = hasParseWarning
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

    // MARK: - Path JSON Helpers

    /// Encode an array of sample URLs to a JSON string for storage in the database.
    ///
    /// Example: `[URL(fileURLWithPath: "/Users/eric/Music/kick.wav")]`
    /// → `"[\"/Users/eric/Music/kick.wav\"]"`
    public static func encodePaths(_ urls: [URL]) -> String? {
        let paths = urls.map(\.path)
        return (try? JSONSerialization.data(withJSONObject: paths))
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Decode a JSON path string from the database back to an array of path strings.
    ///
    /// Returns an empty array if `json` is nil or cannot be decoded.
    public static func decodePaths(_ json: String?) -> [String] {
        guard let json,
              let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return array
    }
}

// MARK: - GRDB Conformances

extension BackupVersion: TableRecord {
    public static let databaseTableName = "backupVersion"
}

extension BackupVersion: FetchableRecord {}
extension BackupVersion: PersistableRecord {}
