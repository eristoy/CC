import Testing
import Foundation
@testable import BackupEngine

@Suite("FileCopyPipeline")
struct FileCopyPipelineTests {

    // MARK: - Helpers

    /// Create an isolated temp directory for each test.
    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let dir = base.appendingPathComponent("FileCopyPipelineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Write `content` to `url`.
    private func writeFile(_ url: URL, content: Data) throws {
        try content.write(to: url)
    }

    // MARK: - Tests

    @Test("copies file to destination")
    func copiesFileToDestination() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("source.txt")
        let destination = tmp.appendingPathComponent("dest").appendingPathComponent("output.txt")

        try writeFile(source, content: Data("hello world".utf8))

        _ = try FileCopyPipeline.copyFileWithChecksum(source: source, destination: destination)

        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("checksum matches expected value")
    func checksumMatchesExpectedValue() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Write known content
        let content = Data("known content for checksum verification".utf8)
        let source = tmp.appendingPathComponent("source.bin")
        let destination = tmp.appendingPathComponent("output.bin")
        try writeFile(source, content: content)

        // Copy and get checksum
        let checksum = try FileCopyPipeline.copyFileWithChecksum(
            source: source, destination: destination)

        // Independently compute expected checksum using the same algorithm
        let expected = try FileCopyPipeline.computeChecksum(of: source)

        // The copied file's checksum should equal the source checksum
        // (destination has identical content)
        #expect(checksum == expected)
        #expect(!checksum.isEmpty)
    }

    @Test("checksum detects corruption")
    func checksumDetectsCorruption() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let content = Data("original uncorrupted content for integrity test".utf8)
        let source = tmp.appendingPathComponent("source.bin")
        let destination = tmp.appendingPathComponent("corrupted.bin")
        try writeFile(source, content: content)

        // Copy the file; record the checksum from copy
        let originalChecksum = try FileCopyPipeline.copyFileWithChecksum(
            source: source, destination: destination)

        // Corrupt a single byte in the destination file
        var destData = try Data(contentsOf: destination)
        destData[0] = destData[0] ^ 0xFF  // flip all bits in first byte
        try destData.write(to: destination)

        // Recompute checksum from (now-corrupted) destination
        let corruptedChecksum = try FileCopyPipeline.computeChecksum(of: destination)

        // Checksum mismatch demonstrates the verification mechanism works
        #expect(originalChecksum != corruptedChecksum)
    }

    @Test("creates intermediate directories")
    func createsIntermediateDirectories() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("source.wav")
        // Destination has multiple non-existent intermediate directories
        let destination = tmp
            .appendingPathComponent("level1")
            .appendingPathComponent("level2")
            .appendingPathComponent("level3")
            .appendingPathComponent("output.wav")

        try writeFile(source, content: Data("audio data".utf8))

        _ = try FileCopyPipeline.copyFileWithChecksum(source: source, destination: destination)

        #expect(FileManager.default.fileExists(atPath: destination.path))
        // Verify intermediate directories were created
        let parent = destination.deletingLastPathComponent()
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("large file checksum is consistent")
    func largeFileChecksum() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Write a 10 MB file with repeating byte pattern (simulates audio data)
        let megabyte = 1024 * 1024
        let repeatPattern = Data(repeating: 0xAB, count: 1024)  // 1 KB repeating chunk
        var largeContent = Data()
        largeContent.reserveCapacity(10 * megabyte)
        for _ in 0..<(10 * megabyte / 1024) {
            largeContent.append(repeatPattern)
        }

        let source = tmp.appendingPathComponent("large.wav")
        let destination = tmp.appendingPathComponent("large_copy.wav")
        try writeFile(source, content: largeContent)

        let checksum = try FileCopyPipeline.copyFileWithChecksum(
            source: source, destination: destination)

        // Checksum should be non-empty and deterministic
        #expect(!checksum.isEmpty)

        // Run again to verify determinism
        let destination2 = tmp.appendingPathComponent("large_copy2.wav")
        let checksum2 = try FileCopyPipeline.copyFileWithChecksum(
            source: source, destination: destination2)

        #expect(checksum == checksum2)

        // Verify destination file size matches source
        let destSize = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int ?? 0
        #expect(destSize == 10 * megabyte)
    }
}
