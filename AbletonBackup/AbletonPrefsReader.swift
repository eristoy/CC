// AbletonBackup/AbletonPrefsReader.swift

import Foundation

/// Reads Ableton preferences to discover the Projects folder location.
///
/// Library.cfg is standard UTF-8 XML — parse with XMLDocument (Foundation).
/// Preferences.cfg is a proprietary binary format — do NOT parse it.
///
/// All methods are non-throwing: failures return nil, and the caller falls back
/// to showing a file picker (Phase 3) or starting with no watch folder.
struct AbletonPrefsReader {

    // MARK: - Public API

    /// Discover the Ableton Projects folder using a multi-step strategy.
    ///
    /// Returns the URL of the folder to watch, or nil if discovery fails.
    /// Returned URL is always a directory that exists on disk.
    ///
    /// Strategy:
    /// 1. Check Ableton's default location: ~/Documents/Ableton/Ableton Projects
    /// 2. Parse Library.cfg to find version folder, then check sibling directories
    /// 3. Return nil — Phase 3 settings UI handles the nil case
    static func discoverProjectsFolder() -> URL? {
        // Step 1: Ableton default — confirmed on this machine
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultPath = home.appendingPathComponent("Documents/Ableton/Ableton Projects")
        if FileManager.default.fileExists(atPath: defaultPath.path) {
            return defaultPath
        }

        // Step 2: Parse Library.cfg to derive a hint
        guard let versionFolder = findLatestVersionFolder() else { return nil }
        guard let userLibraryURL = parseUserLibraryPath(from: versionFolder) else { return nil }

        // User Library is something like ~/Music/Ableton
        // Projects folder is typically at the same parent level: ~/Documents/Ableton/Ableton Projects
        // Try common sibling patterns relative to ~/Documents/Ableton/
        let documentsAbleton = home.appendingPathComponent("Documents/Ableton")
        let candidates = [
            documentsAbleton.appendingPathComponent("Ableton Projects"),
            documentsAbleton.appendingPathComponent("Projects"),
            // Also try sibling of User Library
            userLibraryURL.deletingLastPathComponent().appendingPathComponent("Ableton Projects"),
            userLibraryURL.deletingLastPathComponent().appendingPathComponent("Projects"),
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Internal helpers (internal for testability)

    /// Find the most recent Ableton version folder under ~/Library/Preferences/Ableton/.
    ///
    /// Ableton version folders are named "Live {version}" (e.g., "Live 12.2").
    /// Sort descending by lastPathComponent string to pick the newest.
    /// Do NOT hardcode a version number — multiple Ableton versions can coexist.
    static func findLatestVersionFolder() -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Ableton")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        return items
            .filter { $0.lastPathComponent.hasPrefix("Live ") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
    }

    /// Parse Library.cfg and return the ProjectPath value from the UserLibrary element.
    ///
    /// Library.cfg XPath: //UserLibrary/LibraryProject/ProjectPath/@Value
    /// Verified on Ableton 12.2: value is the User Library path, not the Projects folder.
    static func parseUserLibraryPath(from versionFolder: URL) -> URL? {
        let cfg = versionFolder.appendingPathComponent("Library.cfg")
        guard let data = try? Data(contentsOf: cfg) else { return nil }
        guard let doc = try? XMLDocument(data: data, options: []) else { return nil }
        let nodes = try? doc.nodes(forXPath: "//UserLibrary/LibraryProject/ProjectPath/@Value")
        guard let path = (nodes?.first as? XMLNode)?.stringValue, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
