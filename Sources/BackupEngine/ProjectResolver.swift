import Foundation

/// A file entry discovered during project folder traversal.
///
/// Full implementation in plan 01-02 (TDD).
public struct FileEntry: Sendable {
    public let relativePath: String
    public let url: URL
    public let size: Int64
    public let mtime: Date

    public init(relativePath: String, url: URL, size: Int64, mtime: Date) {
        self.relativePath = relativePath
        self.url = url
        self.size = size
        self.mtime = mtime
    }
}

/// Walks a project directory and returns typed FileEntry values.
///
/// Full implementation in plan 01-02 (TDD).
public enum ProjectResolver {

    /// Walk the directory at `url` and return a FileEntry for every file recursively.
    /// Excludes directories and hidden files (dot-prefixed names).
    public static func resolve(at url: URL) throws -> [FileEntry] {
        // Stub — full implementation in plan 01-02
        return []
    }

    /// Returns true if the file needs to be copied (new file, size changed, or mtime newer).
    /// Returns false if the file is unchanged (same size and mtime as previous record).
    public static func needsCopy(entry: FileEntry, previousRecord: BackupFileRecord?) -> Bool {
        // Stub — full implementation in plan 01-02
        guard let record = previousRecord else { return true }
        return entry.size != Int64(record.sourceSize) || entry.mtime != record.sourceMtime
    }
}
