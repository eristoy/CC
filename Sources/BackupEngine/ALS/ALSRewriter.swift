import Foundation
import zlib

/// Rewrites an Ableton Live Set (.als) file so that all external sample references
/// point to their new locations inside `Samples/Imported/` in the backup project folder,
/// then gzip-compresses the result and writes it to the specified output URL.
///
/// This mirrors Ableton's own "Collect All and Save" layout:
/// - External samples are placed at `<backupProject>/Samples/Imported/<full-original-path>`
/// - The .als is updated with the new relative and absolute paths
/// - The output .als is self-contained and fully openable on any machine that has the backup
public struct ALSRewriter {

    // MARK: - Path Mapping

    /// The relative path from the project root where an external sample will be stored.
    ///
    /// The full original absolute path is preserved as a subfolder structure under
    /// `Samples/Imported/` to guarantee uniqueness across all possible source locations.
    ///
    /// Example:
    /// - Input:  `/Users/eric/Music/Drums/kick.wav`
    /// - Output: `Samples/Imported/Users/eric/Music/Drums/kick.wav`
    public static func importedRelativePath(for sampleURL: URL) -> String {
        let path = sampleURL.path  // e.g. "/Users/eric/Music/Drums/kick.wav"
        // Strip leading "/" to turn the absolute path into a relative subfolder path.
        let stripped = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return "Samples/Imported/" + stripped
    }

    // MARK: - Public API

    /// Rewrite all external sample FileRef paths in the .als to point to their
    /// `Samples/Imported/<full-path>` location in the backup, then gzip-compress
    /// and write the result to `outputURL`.
    ///
    /// Only paths listed in `externalSamples` are rewritten — internal samples and
    /// samples not present in the list are left unchanged.
    ///
    /// - Parameters:
    ///   - alsURL: Original .als file to read, decompress, and parse.
    ///   - externalSamples: External sample URLs that were collected and placed in
    ///     `<backupProjectURL>/Samples/Imported/`.
    ///   - backupProjectURL: Root of the backed-up project folder.
    ///   - outputURL: Destination path for the rewritten, re-compressed .als file.
    /// - Throws: `ALSRewriterError.cannotReadSource` if the source cannot be read,
    ///   or `ALSParserError` variants if gzip decompression/compression fails,
    ///   or `XMLDocument` errors if XML parsing fails,
    ///   or file-system errors if writing fails.
    public static func rewriteAndCompress(
        alsURL: URL,
        externalSamples: [URL],
        backupProjectURL: URL,
        outputURL: URL
    ) throws {
        // 1. Read + decompress + parse (same steps as ALSParser, but we need a mutable doc).
        guard let compressedData = try? Data(contentsOf: alsURL) else {
            throw ALSRewriterError.cannotReadSource
        }
        let xmlData = try ALSParser.decompressGzip(compressedData)
        let doc = try XMLDocument(data: xmlData, options: [])

        // 2. Build a lookup: original absolute path string -> new relative path from .als root.
        //    The .als lives at <backupProjectURL>/<name>.als (project root level), so the
        //    relative path from the .als to Samples/Imported/<...> is just Samples/Imported/<...>.
        var pathMapping: [String: String] = [:]
        for url in externalSamples {
            let relPath = importedRelativePath(for: url)
            pathMapping[url.path] = relPath
        }

        // 3. Mutate FileRef elements whose Path Value is in the mapping.
        let fileRefNodes = (try? doc.nodes(forXPath: "//SampleRef/FileRef")) ?? []
        for node in fileRefNodes {
            guard let fileRef = node as? XMLElement else { continue }

            // Only rewrite if this FileRef's Path is one of the collected external samples.
            guard let pathEl = fileRef.elements(forName: "Path").first,
                  let pathValue = pathEl.attribute(forName: "Value")?.stringValue,
                  !pathValue.isEmpty,
                  let relPath = pathMapping[pathValue] else { continue }

            // New absolute path inside the backup folder (for Ableton to find the file).
            let newAbsPath = backupProjectURL.appendingPathComponent(relPath).path
            pathEl.attribute(forName: "Value")?.stringValue = newAbsPath

            // New relative path from the .als location (relative-to-document mode).
            if let relPathEl = fileRef.elements(forName: "RelativePath").first {
                relPathEl.attribute(forName: "Value")?.stringValue = relPath
            }

            // RelativePathType = 1 means relative-to-document (standard portable format).
            if let relTypeEl = fileRef.elements(forName: "RelativePathType").first {
                relTypeEl.attribute(forName: "Value")?.stringValue = "1"
            }
        }

        // 4. Serialize back to XML bytes, preserving original XML declaration and structure.
        let rewrittenXML = doc.xmlData(options: .nodePreserveAll)

        // 5. Re-gzip with deflateInit2_ (MAX_WBITS + 16 = gzip format with header/trailer).
        let compressed = try compressGzip(rewrittenXML)

        // 6. Write to the output location.
        try compressed.write(to: outputURL)
    }

    // MARK: - Gzip Compress

    /// Compress `data` using gzip format via system zlib.
    ///
    /// `deflateInit2_` with `MAX_WBITS + 16` produces a proper gzip file
    /// (with gzip header and CRC32 trailer), which Ableton Live requires.
    ///
    /// - Throws: `ALSParserError.gzipCompressFailed` if compression fails.
    static func compressGzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        let initResult = deflateInit2_(
            &stream,
            6,                    // compression level (1=fast, 9=best, 6=default)
            Z_DEFLATED,
            MAX_WBITS + 16,       // +16 = gzip format (not raw DEFLATE)
            8,                    // memory level (default)
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else { throw ALSParserError.gzipCompressFailed(initResult) }
        defer { deflateEnd(&stream) }

        // Output buffer: compressed data is always <= input + gzip overhead (~18 bytes header/trailer + 64 bytes slack).
        var output = Data(count: data.count + 64)
        // Set up input pointer first, then access output separately to avoid exclusivity errors.
        let inputCapacity = data.count
        try data.withUnsafeBytes { (inputPtr: UnsafeRawBufferPointer) throws in
            stream.next_in = UnsafeMutablePointer(
                mutating: inputPtr.bindMemory(to: Bytef.self).baseAddress!
            )
            stream.avail_in = uInt(inputCapacity)
            let outputCapacity = output.count
            output.withUnsafeMutableBytes { (outputPtr: UnsafeMutableRawBufferPointer) in
                stream.next_out = outputPtr.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(outputCapacity)
                _ = deflate(&stream, Z_FINISH)
            }
        }
        output.count = Int(stream.total_out)
        return output
    }
}

/// Errors thrown by `ALSRewriter`.
public enum ALSRewriterError: Error {
    /// The source .als file could not be read from disk.
    case cannotReadSource
}
