import Foundation
import zlib

/// Errors that can be thrown by the low-level gzip decompress / compress helpers.
///
/// These are only thrown from the internal helper functions; the public
/// `ALSParser.parse(alsURL:projectDirectory:)` method returns a `ParseResult`
/// instead of throwing, so callers never need to catch these directly unless
/// they call `decompressGzip(_:)` directly.
public enum ALSParserError: Error {
    case gzipInitFailed(Int32)
    case gzipDecompressFailed(Int32)
    case gzipCompressFailed(Int32)
}

/// Parses a gzip-compressed Ableton Live Set (.als) file and classifies
/// the sample references it contains as external or internal.
///
/// Ableton Live Set files are gzip-compressed XML.  The XML contains
/// `<SampleRef><FileRef><Path Value="/abs/path/to/sample.wav"/></FileRef></SampleRef>`
/// nodes — the `Path` attribute carries the authoritative absolute path to each sample.
///
/// **External** samples are those whose path lies outside the project folder.
/// **Internal** samples are those already inside the project folder (Phase 1 already copies them).
///
/// If gzip decompression or XML parsing fails the method returns `.parseFailure`
/// rather than throwing, consistent with the "backup proceeds in fallback mode" policy.
public struct ALSParser {

    // MARK: - Public API

    /// Result of parsing an .als file.
    public enum ParseResult {
        /// Successfully parsed.  External and internal sample URL lists are provided.
        case success(external: [URL], internal_: [URL])

        /// The .als could not be parsed (not a gzip file, corrupt gzip, or invalid XML).
        /// The backup engine should proceed with plain folder copy (Phase 1 behavior).
        case parseFailure(reason: String)
    }

    /// Parse `alsURL` and classify its sample references relative to `projectDirectory`.
    ///
    /// - Parameters:
    ///   - alsURL: The .als file to parse (must be a gzip-compressed XML file).
    ///   - projectDirectory: The root folder of the Ableton project.  Samples whose
    ///     absolute path begins with this directory are classified as internal.
    /// - Returns: `.success(external:internal_:)` on success, `.parseFailure` on any error.
    public static func parse(alsURL: URL, projectDirectory: URL) -> ParseResult {
        // 1. Read raw bytes and verify the gzip magic bytes 0x1F 0x8B
        guard let compressedData = try? Data(contentsOf: alsURL),
              compressedData.count >= 2,
              compressedData[0] == 0x1F,
              compressedData[1] == 0x8B else {
            return .parseFailure(reason: "Could not read .als file or not a gzip file")
        }

        // 2. Decompress using system zlib with gzip mode (MAX_WBITS + 32).
        //    NOTE: NSData.decompressed(using:) uses raw DEFLATE, not gzip — do not use it.
        guard let xmlData = try? decompressGzip(compressedData) else {
            return .parseFailure(reason: "gzip decompression failed")
        }

        // 3. Parse XML with XMLDocument (DOM — required for path mutation in ALSRewriter).
        guard let doc = try? XMLDocument(data: xmlData, options: []) else {
            return .parseFailure(reason: "XML parse failed")
        }

        // 4. XPath: find ALL SampleRef/FileRef/Path nodes regardless of parent context.
        guard let pathNodes = try? doc.nodes(forXPath: "//SampleRef/FileRef/Path") else {
            return .parseFailure(reason: "XPath query failed")
        }

        // 5. Extract non-empty Path Value attributes.
        //    Pre-Live-11 files store paths as binary hex inside the Value attribute —
        //    those produce empty strings after UTF-8 decoding, so we skip them.
        let allPaths: [URL] = pathNodes.compactMap { node in
            guard let el = node as? XMLElement,
                  let value = el.attribute(forName: "Value")?.stringValue,
                  !value.isEmpty else { return nil }
            return URL(fileURLWithPath: value).resolvingSymlinksInPath()
        }

        // 6. Classify: external = path NOT under the project folder.
        //    Resolve symlinks on the project path so /var/... == /private/var/... on macOS.
        let resolvedProject = projectDirectory.resolvingSymlinksInPath().path
        var external: [URL] = []
        var internal_: [URL] = []
        for url in allPaths {
            // A sample is "internal" if its path starts with the project path + "/",
            // or if its path IS the project path (edge case: project IS the sample root).
            if url.path.hasPrefix(resolvedProject + "/") || url.path == resolvedProject {
                internal_.append(url)
            } else {
                external.append(url)
            }
        }

        return .success(external: external, internal_: internal_)
    }

    // MARK: - Gzip Decompress

    /// Decompress gzip-compressed `data` using system zlib.
    ///
    /// `inflateInit2_` with `MAX_WBITS + 32` instructs zlib to auto-detect the
    /// gzip header/trailer, which is required for `.als` files.
    ///
    /// - Throws: `ALSParserError.gzipInitFailed` or `ALSParserError.gzipDecompressFailed`.
    public static func decompressGzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        let initResult = inflateInit2_(
            &stream,
            MAX_WBITS + 32,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else { throw ALSParserError.gzipInitFailed(initResult) }
        defer { inflateEnd(&stream) }

        // Pre-allocate output buffer: 4x input size or 64 KiB minimum.
        var output = Data(count: max(data.count * 4, 65536))
        var status: Int32 = Z_OK

        // Set up the input pointer once — avail_in decrements as inflate progresses.
        try data.withUnsafeBytes { (inputPtr: UnsafeRawBufferPointer) throws in
            stream.next_in = UnsafeMutablePointer(
                mutating: inputPtr.bindMemory(to: Bytef.self).baseAddress!
            )
            stream.avail_in = uInt(data.count)

            while status == Z_OK {
                // Use a local variable to avoid overlapping-access exclusivity errors.
                let currentCapacity = output.count
                let written = Int(stream.total_out)
                output.withUnsafeMutableBytes { (outputPtr: UnsafeMutableRawBufferPointer) in
                    stream.next_out = outputPtr.bindMemory(to: Bytef.self).baseAddress!
                        .advanced(by: written)
                    stream.avail_out = uInt(currentCapacity) - uInt(written)
                    status = inflate(&stream, Z_SYNC_FLUSH)
                }
                // If output buffer is full, double it and continue inflating.
                if stream.avail_out == 0 { output.count *= 2 }
            }
        }

        guard status == Z_STREAM_END else {
            throw ALSParserError.gzipDecompressFailed(status)
        }
        output.count = Int(stream.total_out)
        return output
    }
}
