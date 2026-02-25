import Testing
import Foundation
@testable import BackupEngine

@Suite("LocalDestinationAdapter")
struct LocalDestinationAdapterTests {

    // MARK: - Helpers

    /// Create an isolated temp directory, resolving symlinks (macOS /var → /private/var).
    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let dir = base.appendingPathComponent("LocalAdapterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Build a minimal DestinationConfig pointing at `rootPath`.
    private func makeConfig(rootPath: String) -> DestinationConfig {
        DestinationConfig(
            id: UUID().uuidString,
            type: .local,
            name: "Test Destination",
            rootPath: rootPath,
            retentionCount: 10,
            createdAt: Date()
        )
    }

    /// Create a file at `url` with the given UTF-8 string content.
    private func createFile(_ url: URL, content: String = "test content") throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }

    /// Build a FileEntry for a file that already exists on disk.
    private func makeFileEntry(url: URL, relativePath: String) throws -> FileEntry {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = Int64((attrs[.size] as? Int) ?? 0)
        let mtime = (attrs[.modificationDate] as? Date) ?? Date()
        return FileEntry(relativePath: relativePath, url: url, size: size, mtime: mtime)
    }

    // MARK: - Tests

    @Test("transfer creates version directory and copies files")
    func transferCreatesVersionDirectory() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Source directory with 2 files
        let sourceDir = tmp.appendingPathComponent("source")
        let file1 = sourceDir.appendingPathComponent("track.als")
        let file2 = sourceDir.appendingPathComponent("Samples/kick.wav")
        try createFile(file1, content: "ableton project data")
        try createFile(file2, content: "audio sample data")

        // Destination root
        let destRoot = tmp.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)

        let config = makeConfig(rootPath: destRoot.path)
        let adapter = LocalDestinationAdapter(config: config)

        let files = [
            try makeFileEntry(url: file1, relativePath: "track.als"),
            try makeFileEntry(url: file2, relativePath: "Samples/kick.wav")
        ]

        let versionID = "2026-02-25T143022.456-a3f8b12c"
        _ = try await adapter.transfer(files, versionID: versionID, progress: { _ in })

        // Verify both files exist in the version directory
        let versionDir = destRoot.appendingPathComponent(versionID)
        let copiedFile1 = versionDir.appendingPathComponent("track.als")
        let copiedFile2 = versionDir.appendingPathComponent("Samples/kick.wav")

        #expect(FileManager.default.fileExists(atPath: versionDir.path))
        #expect(FileManager.default.fileExists(atPath: copiedFile1.path))
        #expect(FileManager.default.fileExists(atPath: copiedFile2.path))
    }

    @Test("transfer returns BackupFileRecord array with checksums")
    func transferReturnsManifestRecords() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sourceDir = tmp.appendingPathComponent("source")
        let file1 = sourceDir.appendingPathComponent("set.als")
        let file2 = sourceDir.appendingPathComponent("Samples/bass.wav")
        try createFile(file1, content: "live set content")
        try createFile(file2, content: "bass audio content")

        let destRoot = tmp.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true)

        let config = makeConfig(rootPath: destRoot.path)
        let adapter = LocalDestinationAdapter(config: config)

        let files = [
            try makeFileEntry(url: file1, relativePath: "set.als"),
            try makeFileEntry(url: file2, relativePath: "Samples/bass.wav")
        ]

        let versionID = "2026-02-25T143022.456-b4c9d23e"
        let records = try await adapter.transfer(files, versionID: versionID, progress: { _ in })

        // Should have exactly 2 records
        #expect(records.count == 2)

        // All records must have the correct versionID
        #expect(records.allSatisfy { $0.versionID == versionID })

        // relativePaths must match the input
        let recordedPaths = Set(records.map(\.relativePath))
        #expect(recordedPaths == Set(["set.als", "Samples/bass.wav"]))

        // All checksums must be non-empty (xxHash64 hex = 16 hex digits)
        #expect(records.allSatisfy { ($0.checksum?.isEmpty == false) })

        // copied flag must be true for all records
        #expect(records.allSatisfy { $0.copied == true })
    }

    @Test("probe returns available for existing directory")
    func probeReturnAvailableForExistingDir() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = makeConfig(rootPath: tmp.path)
        let adapter = LocalDestinationAdapter(config: config)

        let status = await adapter.probe()

        // Should be available since the directory exists
        guard case .available = status else {
            Issue.record("Expected .available but got \(status)")
            return
        }
    }

    @Test("probe returns unavailable for missing directory")
    func probeReturnUnavailableForMissingDir() async throws {
        let nonExistentPath = "/tmp/nonexistent-backup-dir-\(UUID().uuidString)"
        let config = makeConfig(rootPath: nonExistentPath)
        let adapter = LocalDestinationAdapter(config: config)

        let status = await adapter.probe()

        // Should be unavailable since the directory does not exist
        guard case .unavailable(let reason) = status else {
            Issue.record("Expected .unavailable but got \(status)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(reason.contains(nonExistentPath))
    }
}
