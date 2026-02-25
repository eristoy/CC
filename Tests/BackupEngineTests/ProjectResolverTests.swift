import Testing
import Foundation
@testable import BackupEngine

// RED PHASE: ProjectResolver and FileEntry do not exist yet.
// These tests will fail to compile until Sources/BackupEngine/ProjectResolver.swift is created.
// This is expected — TDD RED state.

@Suite("ProjectResolver")
struct ProjectResolverTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func writeFile(at url: URL, content: String = "test content") throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.data(using: .utf8)!.write(to: url)
    }

    // MARK: - resolve(at:) tests

    @Test("Empty directory returns empty array")
    func emptyDirectoryReturnsEmptyArray() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entries = try ProjectResolver.resolve(at: tempDir)
        #expect(entries.isEmpty)
    }

    @Test("Flat directory with 3 files returns 3 FileEntry values with correct relativePaths")
    func flatDirectoryReturnsCorrectEntries() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeFile(at: tempDir.appendingPathComponent("file1.wav"))
        try writeFile(at: tempDir.appendingPathComponent("file2.wav"))
        try writeFile(at: tempDir.appendingPathComponent("project.als"))

        let entries = try ProjectResolver.resolve(at: tempDir)
        #expect(entries.count == 3)

        let paths = Set(entries.map { $0.relativePath })
        #expect(paths.contains("file1.wav"))
        #expect(paths.contains("file2.wav"))
        #expect(paths.contains("project.als"))

        // No leading slash
        for entry in entries {
            #expect(!entry.relativePath.hasPrefix("/"))
        }
    }

    @Test("Nested directory returns all files with correct relative paths")
    func nestedDirectoryReturnsCorrectRelativePaths() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeFile(at: tempDir.appendingPathComponent("project.als"))
        try writeFile(at: tempDir.appendingPathComponent("Samples/Imported/kick.wav"))
        try writeFile(at: tempDir.appendingPathComponent("Samples/Imported/snare.wav"))
        try writeFile(at: tempDir.appendingPathComponent("Samples/Processed/bass.wav"))

        let entries = try ProjectResolver.resolve(at: tempDir)
        #expect(entries.count == 4)

        let paths = Set(entries.map { $0.relativePath })
        #expect(paths.contains("project.als"))
        #expect(paths.contains("Samples/Imported/kick.wav"))
        #expect(paths.contains("Samples/Imported/snare.wav"))
        #expect(paths.contains("Samples/Processed/bass.wav"))
    }

    @Test("Hidden files (.DS_Store) are excluded from results")
    func hiddenFilesAreExcluded() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeFile(at: tempDir.appendingPathComponent("project.als"))
        try writeFile(at: tempDir.appendingPathComponent(".DS_Store"))
        try writeFile(at: tempDir.appendingPathComponent(".hidden_file"))

        let entries = try ProjectResolver.resolve(at: tempDir)
        // Only non-hidden files should be returned
        #expect(entries.count == 1)
        #expect(entries[0].relativePath == "project.als")
    }

    @Test("Directory entries are excluded from results (only files returned)")
    func directoryEntriesExcluded() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a subdirectory with a file in it
        let subdir = tempDir.appendingPathComponent("Samples")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try writeFile(at: subdir.appendingPathComponent("kick.wav"))

        let entries = try ProjectResolver.resolve(at: tempDir)
        // "Samples" directory itself should NOT appear in results
        let hasDirectoryEntry = entries.contains { $0.relativePath == "Samples" }
        #expect(!hasDirectoryEntry)
        // The file inside should appear
        #expect(entries.count == 1)
        #expect(entries[0].relativePath == "Samples/kick.wav")
    }

    @Test("FileEntry.size matches actual byte count of file")
    func fileSizeMatchesActualBytes() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = "Hello, audio world! This is 36 bytes."
        let fileURL = tempDir.appendingPathComponent("test.txt")
        let data = content.data(using: .utf8)!
        try data.write(to: fileURL)

        let entries = try ProjectResolver.resolve(at: tempDir)
        #expect(entries.count == 1)
        #expect(entries[0].size == Int64(data.count))
    }

    @Test("FileEntry.mtime matches file modification date")
    func fileMtimeMatchesModificationDate() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.wav")
        try writeFile(at: fileURL)

        // Read the actual mtime from file attributes
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let expectedMtime = attrs[.modificationDate] as? Date else {
            Issue.record("Could not read file modification date")
            return
        }

        let entries = try ProjectResolver.resolve(at: tempDir)
        #expect(entries.count == 1)
        // mtime should match within 1 second (accounting for filesystem precision differences)
        let diff = abs(entries[0].mtime.timeIntervalSince(expectedMtime))
        #expect(diff < 1.0)
    }

    // MARK: - needsCopy tests

    @Test("needsCopy returns true when previousRecord is nil (new file)")
    func needsCopyReturnsTrueForNewFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("new.wav")
        try writeFile(at: fileURL)
        let entries = try ProjectResolver.resolve(at: tempDir)
        #expect(entries.count == 1)

        let result = ProjectResolver.needsCopy(entry: entries[0], previousRecord: nil)
        #expect(result == true)
    }

    @Test("needsCopy returns false for matching size and mtime (unchanged file)")
    func needsCopyReturnsFalseForUnchangedFile() {
        let mtime = Date()
        let entry = FileEntry(
            relativePath: "Samples/kick.wav",
            url: URL(fileURLWithPath: "/tmp/kick.wav"),
            size: 1024,
            mtime: mtime
        )
        let record = BackupFileRecord(
            versionID: "v1",
            relativePath: "Samples/kick.wav",
            sourceMtime: mtime,
            sourceSize: 1024,
            checksum: nil,
            copied: true
        )

        let result = ProjectResolver.needsCopy(entry: entry, previousRecord: record)
        #expect(result == false)
    }

    @Test("needsCopy returns true when size differs (changed file)")
    func needsCopyReturnsTrueForSizeChange() {
        let mtime = Date()
        let entry = FileEntry(
            relativePath: "Samples/kick.wav",
            url: URL(fileURLWithPath: "/tmp/kick.wav"),
            size: 2048,  // different from record
            mtime: mtime
        )
        let record = BackupFileRecord(
            versionID: "v1",
            relativePath: "Samples/kick.wav",
            sourceMtime: mtime,
            sourceSize: 1024,  // original size
            checksum: nil,
            copied: true
        )

        let result = ProjectResolver.needsCopy(entry: entry, previousRecord: record)
        #expect(result == true)
    }

    @Test("needsCopy returns true when mtime is newer (changed file)")
    func needsCopyReturnsTrueForNewerMtime() {
        let originalMtime = Date(timeIntervalSinceNow: -3600)  // 1 hour ago
        let newerMtime = Date()  // now (newer)
        let entry = FileEntry(
            relativePath: "Samples/kick.wav",
            url: URL(fileURLWithPath: "/tmp/kick.wav"),
            size: 1024,  // same size
            mtime: newerMtime
        )
        let record = BackupFileRecord(
            versionID: "v1",
            relativePath: "Samples/kick.wav",
            sourceMtime: originalMtime,
            sourceSize: 1024,
            checksum: nil,
            copied: true
        )

        let result = ProjectResolver.needsCopy(entry: entry, previousRecord: record)
        #expect(result == true)
    }
}
