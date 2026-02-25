import Foundation
import Darwin
import xxHash_Swift

// MARK: - FileCopyPipeline

/// Stateless namespace for low-level file copy operations.
///
/// The two code paths:
/// - **APFS clone path**: `COPYFILE_CLONE` is attempted first. On APFS this is a
///   near-instant, space-efficient copy-on-write clone. On non-APFS (ExFAT, HFS+),
///   macOS automatically falls back to a regular copy. After a successful clone,
///   the destination file is read once to compute the checksum.
/// - **Chunked copy path**: Used when `copyfile()` returns a non-zero error code.
///   Reads the source in 8 MB chunks, writes each chunk to the destination, and
///   feeds each chunk into the XXH64 streaming hasher inline — zero extra I/O.
///
/// Checksum algorithm: xxHash64 (XXH64) via xxHash-Swift 1.1.1.
/// xxHash64 is significantly faster than SHA-256 for large audio files and is
/// sufficient for integrity verification (not a cryptographic use case).
/// Output format: lowercase hex string (16 hex digits for 64-bit hash).
public enum FileCopyPipeline {

    /// Chunk size for both the chunked-copy path and the post-clone checksum read.
    static let chunkSize = 8 * 1024 * 1024  // 8 MB

    // MARK: - Public API

    /// Copy a file from `source` to `destination`, returning an xxHash64 hex checksum.
    ///
    /// The copy attempts an APFS clone first (COPYFILE_CLONE, which auto-falls-back to
    /// a regular copy on non-APFS). On error, falls back to a manual chunked copy with
    /// inline hashing.
    ///
    /// Intermediate directories for `destination` are created automatically.
    ///
    /// - Parameters:
    ///   - source: URL of the file to copy.
    ///   - destination: Target URL (will be created; any existing file is overwritten).
    /// - Returns: Lowercase hex xxHash64 of the destination file's content.
    /// - Throws: If the destination directory cannot be created, or if the copy fails.
    public static func copyFileWithChecksum(
        source: URL,
        destination: URL
    ) throws -> String {
        // Ensure destination directory exists
        let destDir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: destDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Remove existing file at destination (copyfile does not overwrite by default
        // on some configurations; remove first for deterministic behavior).
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        // Attempt APFS clone (auto-fallback to regular copy on non-APFS/ExFAT).
        // COPYFILE_CLONE_FORCE is intentionally NOT used — it fails on non-APFS without fallback.
        let cloneResult = source.withUnsafeFileSystemRepresentation { srcPath -> Int32 in
            guard let srcPath else { return -1 }
            return destination.withUnsafeFileSystemRepresentation { dstPath -> Int32 in
                guard let dstPath else { return -1 }
                return copyfile(srcPath, dstPath, nil, copyfile_flags_t(COPYFILE_CLONE | COPYFILE_ALL))
            }
        }

        if cloneResult == 0 {
            // Clone succeeded — compute checksum from destination (one read; acceptable
            // because the clone was near-instant and the checksum read is necessary anyway).
            return try computeChecksum(of: destination)
        }

        // Clone failed (cross-device, permissions error, etc.) — use chunked copy
        // with inline hashing (no extra read needed after copy).
        return try chunkedCopyWithChecksum(source: source, destination: destination)
    }

    // MARK: - Checksum Computation

    /// Compute an xxHash64 checksum of a file by reading it in chunks.
    ///
    /// Used after a successful APFS clone (one read from the destination).
    /// - Parameter url: File to hash.
    /// - Returns: Lowercase hex xxHash64 string.
    static func computeChecksum(of url: URL) throws -> String {
        let hasher = XXH64()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(chunk)
        }
        return hasher.digestHex()
    }

    // MARK: - Chunked Copy

    /// Copy `source` to `destination` in 8 MB chunks, hashing inline.
    ///
    /// - Parameters:
    ///   - source: Source file URL.
    ///   - destination: Destination file URL (must not exist; parent directory must exist).
    /// - Returns: Lowercase hex xxHash64 of the copied content.
    /// - Throws: On any I/O error.
    private static func chunkedCopyWithChecksum(source: URL, destination: URL) throws -> String {
        let hasher = XXH64()

        let readHandle = try FileHandle(forReadingFrom: source)
        defer { try? readHandle.close() }

        // Create destination file for writing
        FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: nil)
        let writeHandle = try FileHandle(forWritingTo: destination)
        defer { try? writeHandle.close() }

        while true {
            guard let chunk = try readHandle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            // Hash inline — no extra read needed after copy
            hasher.update(chunk)
            try writeHandle.write(contentsOf: chunk)
        }

        return hasher.digestHex()
    }
}
