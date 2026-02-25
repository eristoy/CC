import Foundation

/// A file entry discovered during project folder traversal.
///
/// Passed through the backup pipeline: from ProjectResolver → FileCopyPipeline → BackupManifest.
/// `relativePath` uses "/" separator with no leading slash, relative to the project root.
public struct FileEntry: Sendable, Equatable {
    /// Path relative to the project root directory.
    /// e.g., root=/tmp/MyProject, file=/tmp/MyProject/Samples/kick.wav → "Samples/kick.wav"
    public let relativePath: String
    /// Absolute source URL for this file.
    public let url: URL
    /// File size in bytes.
    public let size: Int64
    /// Last modification date from file system attributes.
    public let mtime: Date

    public init(relativePath: String, url: URL, size: Int64, mtime: Date) {
        self.relativePath = relativePath
        self.url = url
        self.size = size
        self.mtime = mtime
    }
}

/// Walks a project directory and returns typed FileEntry values for backup.
///
/// This is a pure I/O component: stateless, synchronous, no side effects.
/// All filtering (hidden files, directories) happens here before files reach the pipeline.
public struct ProjectResolver {

    /// Walk the directory at `rootURL` recursively and return a FileEntry for every
    /// non-hidden regular file found at any depth.
    ///
    /// Inclusion rules:
    /// - Include: regular files at any depth
    /// - Exclude: directories (only files in results)
    /// - Exclude: hidden files (names starting with ".")
    ///
    /// `relativePath` is relative to `rootURL`, using "/" separator, no leading slash.
    ///
    /// All operations are synchronous — local file system only.
    ///
    /// - Parameter rootURL: The directory to walk.
    /// - Returns: Array of FileEntry values, one per qualifying file. Order is not guaranteed.
    /// - Throws: If the enumerator cannot be created or resource values cannot be read.
    public static func resolve(at rootURL: URL) throws -> [FileEntry] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        // Resolve the canonical absolute path for the root directory.
        // This is essential on macOS where FileManager.temporaryDirectory returns
        // /var/folders/... but the real path is /private/var/folders/... (symlink).
        // Both rootURL and each fileURL must use the same resolution so the prefix
        // strip produces a correct relative path.
        let resolvedRootURL = rootURL.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: resolvedRootURL,
            includingPropertiesForKeys: keys,
            options: []  // no skipping — full recursive walk through all subdirectories
        ) else {
            // Enumerator returns nil only if resolvedRootURL is not a valid directory
            return []
        }

        // Build a normalized root path string with no trailing slash.
        var rootPath = resolvedRootURL.path
        if rootPath.hasSuffix("/") { rootPath = String(rootPath.dropLast()) }

        var entries: [FileEntry] = []

        for case let fileURL as URL in enumerator {
            // Read resource values for this URL in a single system call
            let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))

            // Skip directories — only include regular files
            guard resourceValues.isRegularFile == true else { continue }

            // Skip hidden files (names starting with ".") — e.g., .DS_Store, .hidden
            guard resourceValues.isHidden == false else { continue }

            // Extract file metadata
            let size = Int64(resourceValues.fileSize ?? 0)
            let mtime = resourceValues.contentModificationDate ?? Date.distantPast

            // Resolve the file URL to match the resolved root, then compute relative path.
            let resolvedFileURL = fileURL.resolvingSymlinksInPath()
            let absolutePath = resolvedFileURL.path
            let relativePath: String
            if absolutePath.hasPrefix(rootPath + "/") {
                // Strip "rootPath/" prefix to get the relative component
                relativePath = String(absolutePath.dropFirst(rootPath.count + 1))
            } else if absolutePath.hasPrefix(rootPath) {
                // Edge case: file is at root level (no subdirectory)
                let suffix = String(absolutePath.dropFirst(rootPath.count))
                relativePath = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix
            } else {
                // Fallback: should not happen with a correctly resolved enumerator
                relativePath = fileURL.lastPathComponent
            }

            entries.append(FileEntry(
                relativePath: relativePath,
                url: resolvedFileURL,
                size: size,
                mtime: mtime
            ))
        }

        return entries
    }

    /// Determines whether a file needs to be copied by comparing its current metadata
    /// against the previous backup record.
    ///
    /// Uses mtime + size comparison — does NOT compute source-side checksum.
    /// Computing source checksum reads every byte of every file and eliminates incremental benefit.
    ///
    /// Returns `true` (copy needed) when:
    /// - `previousRecord` is nil → new file, never backed up
    /// - `entry.size` differs from `previousRecord.sourceSize` → file changed
    /// - `entry.mtime` is newer than `previousRecord.sourceMtime` → file modified
    ///
    /// Returns `false` (skip) when size AND mtime match (file is unchanged).
    ///
    /// - Parameters:
    ///   - entry: Current FileEntry from ProjectResolver.
    ///   - previousRecord: The BackupFileRecord from the most recent verified backup, or nil.
    /// - Returns: true if the file should be copied; false if it can be safely skipped.
    public static func needsCopy(entry: FileEntry, previousRecord: BackupFileRecord?) -> Bool {
        guard let prev = previousRecord else {
            return true  // new file — always copy
        }
        // Copy if size changed or mtime is newer
        return entry.size != Int64(prev.sourceSize) || entry.mtime > prev.sourceMtime
    }
}
