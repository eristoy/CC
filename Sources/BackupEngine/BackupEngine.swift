import Foundation
import GRDB
import OSLog

// MARK: - BackupEngine

/// The main actor that orchestrates the complete backup pipeline.
///
/// Responsibilities:
/// - Resolves project files and applies incremental skip logic
/// - Fans out transfers to one or more destination adapters concurrently
/// - Manages the full version lifecycle: pending → copying → copy_complete → verifying → verified (or corrupt)
/// - Enforces retention policy after each verified backup
/// - Deduplicates concurrent runJob() calls for the same project
public actor BackupEngine {

    private let logger = Logger(subsystem: "com.abletonbackup", category: "BackupEngine")
    private let db: AppDatabase
    /// Destination adapters keyed by their ID.
    private var adapters: [String: any DestinationAdapter]
    /// Running jobs keyed by projectID — used for deduplication.
    /// Each entry is a Task that can be joined by concurrent callers.
    private var runningJobs: [String: Task<BackupJobResult, Error>]
    /// FileEntry cache keyed by projectID → relativePath → FileEntry.
    ///
    /// Stores the last verified FileEntry for each file (filesystem-precision mtime/size).
    /// Using FileEntry directly avoids the millisecond truncation that occurs when
    /// Date values are stored and retrieved from SQLite via GRDB, which would cause
    /// `entry.mtime > prev.sourceMtime` to return true for unchanged files.
    private var fileEntryCache: [String: [String: FileEntry]]

    // MARK: - Init

    public init(db: AppDatabase, adapters: [any DestinationAdapter]) {
        self.db = db
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.id, $0) })
        self.runningJobs = [:]
        self.fileEntryCache = [:]
    }

    // MARK: - Public API

    /// Run a backup job for the given project to the specified destinations.
    ///
    /// If a job is already running for this project, the second caller joins the same
    /// in-flight task and receives the same result (deduplication).
    ///
    /// - Parameter job: Specifies which project to back up and to which destinations.
    /// - Returns: The aggregated result of the backup, including per-destination outcomes.
    /// - Throws: BackupEngineError.noDestinationsConfigured if none of the destination IDs resolve.
    public func runJob(_ job: BackupJob) async throws -> BackupJobResult {
        // Deduplication: if a job is already running for this project, join it.
        if let existing = runningJobs[job.project.id] {
            logger.debug("runJob: deduplication — joining in-flight task for project=\(job.project.id, privacy: .public)")
            return try await existing.value
        }

        // Start the job as an unstructured Task so concurrent callers can join it.
        // The Task inherits actor isolation (runs on BackupEngine's executor).
        let task = Task { [self] in
            try await self.executeJob(job)
        }
        runningJobs[job.project.id] = task
        defer { runningJobs.removeValue(forKey: job.project.id) }
        return try await task.value
    }

    // MARK: - Private Execution

    private func executeJob(_ job: BackupJob) async throws -> BackupJobResult {
        let project = job.project
        let targetAdapters = job.destinationIDs.compactMap { adapters[$0] }
        guard !targetAdapters.isEmpty else {
            throw BackupEngineError.noDestinationsConfigured
        }

        logger.info("executeJob: start — project=\(project.id, privacy: .public) destinations=\(targetAdapters.map(\.id), privacy: .public)")

        // versionID is assigned here (before step 0) so notifications can reference it
        // before the pending DB rows are created in step 4. No behavior change — versionID
        // was previously assigned just before step 4 and the same value is used throughout.
        let versionID = VersionManager.newVersionID()

        // Step 0: Parse .als file to discover external samples before any file copying.
        // Locked decision: parse before file-copy; caller (BackupCoordinator) sends
        // notifications after inspecting sampleCollection in BackupJobResult.
        let projectURL = URL(fileURLWithPath: project.path)

        // Find the .als file that triggered this job.
        // Use FileManager to enumerate *.als files at the top level of the project folder.
        // The FSEventsWatcher fires on the specific .als file, but BackupJob only carries the project path.
        // Find the newest (most recently modified) .als at the project root — handles multi-ALS projects.
        let alsURL: URL? = {
            let fm = FileManager.default
            let contents = (try? fm.contentsOfDirectory(at: projectURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            let alsFiles = contents.filter { $0.pathExtension == "als" }
            return alsFiles.max {
                let dateA = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let dateB = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return dateA < dateB
            }
        }()

        // Compute sampleCollection as a let so it can be safely captured in concurrent closures.
        let sampleCollection: SampleCollection = {
            guard let alsURL else {
                logger.debug("executeJob: no .als file found in project; skipping ALS parse")
                return .empty
            }
            logger.info("executeJob: parsing .als — \(alsURL.lastPathComponent, privacy: .public)")
            switch ALSParser.parse(alsURL: alsURL, projectDirectory: projectURL) {
            case .parseFailure(let reason):
                logger.warning("executeJob: ALS parse failed — \(reason, privacy: .public); proceeding with plain folder backup")
                return .parseFailure
            case .success(let external, _):
                // Classify external samples: available on disk vs missing/offline
                let available = external.filter { FileManager.default.fileExists(atPath: $0.path) }
                let missing   = external.filter { !FileManager.default.fileExists(atPath: $0.path) }
                logger.info("executeJob: ALS parsed — external=\(external.count) available=\(available.count) missing=\(missing.count)")
                return SampleCollection(
                    collectedPaths: available,
                    missingPaths: missing,
                    hasParseWarning: false
                )
            }
        }()

        // 1. Resolve all files in the project directory.
        let allFiles = try ProjectResolver.resolve(at: URL(fileURLWithPath: project.path))

        // 2. Read the previous FileEntry cache for this project.
        //    Using FileEntry values (filesystem-precision mtime) avoids the mtime truncation
        //    that would occur if we compared against DB-fetched BackupFileRecord.sourceMtime,
        //    which is truncated to millisecond precision by GRDB's ISO8601 date storage.
        let previousEntries = fileEntryCache[project.id] ?? [:]

        // 3. Apply incremental filter: only copy files that changed since last verified backup.
        //    Build a synthetic BackupFileRecord from the cached FileEntry for needsCopy comparison.
        var filesToCopy: [FileEntry] = []
        var skippedCount = 0
        for file in allFiles {
            if let cached = previousEntries[file.relativePath] {
                // Construct a minimal BackupFileRecord from cached FileEntry for comparison.
                // This keeps mtime at filesystem precision — no DB round-trip truncation.
                let synthetic = BackupFileRecord(
                    versionID: "",
                    relativePath: cached.relativePath,
                    sourceMtime: cached.mtime,
                    sourceSize: Int(cached.size)
                )
                if ProjectResolver.needsCopy(entry: file, previousRecord: synthetic) {
                    filesToCopy.append(file)
                } else {
                    skippedCount += 1
                }
            } else {
                // No previous record — new file, always copy.
                filesToCopy.append(file)
            }
        }

        logger.info("executeJob: incremental filter — copy=\(filesToCopy.count) skipped=\(skippedCount)")

        // 4. Create a pending BackupVersion row for each destination.
        for adapter in targetAdapters {
            let version = BackupVersion(
                id: versionID,
                projectID: project.id,
                destinationID: adapter.id,
                status: .pending,
                fileCount: nil,
                totalBytes: nil,
                createdAt: Date(),
                completedAt: nil,
                errorMessage: nil
            )
            try await db.pool.write { db in try version.insert(db) }
        }

        // 5. Transition to copying.
        try await updateVersionStatus(versionID: versionID, status: .copying)

        // 6. Fan out to all destinations concurrently.
        // Capture filesToCopy as a sendable snapshot for use inside the task group.
        let filesToCopySnapshot: [FileEntry] = filesToCopy
        var destinationResults: [DestinationResult] = []
        try await withThrowingTaskGroup(of: DestinationResult.self) { group in
            for adapter in targetAdapters {
                let files = filesToCopySnapshot
                let vid = versionID
                let db = self.db
                group.addTask {
                    do {
                        let records = try await adapter.transfer(files, versionID: vid) { _ in }
                        // Insert BackupFileRecord rows for each copied file.
                        try await db.pool.write { database in
                            for record in records { try record.insert(database) }
                        }
                        return DestinationResult(
                            destinationID: adapter.id,
                            status: .copy_complete,
                            errorMessage: nil
                        )
                    } catch {
                        return DestinationResult(
                            destinationID: adapter.id,
                            status: .corrupt,
                            errorMessage: error.localizedDescription
                        )
                    }
                }
            }
            for try await result in group {
                destinationResults.append(result)
            }
        }

        logger.info("executeJob: fan-out complete — results=\(destinationResults.map { "\($0.destinationID):\($0.status)" }, privacy: .public)")

        // After the TaskGroup fan-out (step 6), copy external samples and write rewritten .als.
        // Only runs if we successfully parsed an .als with no parse warning.
        if let alsURL, !sampleCollection.hasParseWarning {
            for adapter in targetAdapters {
                let versionDir = URL(fileURLWithPath: adapter.config.rootPath).appendingPathComponent(versionID)
                // Copy external samples to Samples/Imported/<full-original-path>
                for sampleURL in sampleCollection.collectedPaths {
                    let relativePath = ALSRewriter.importedRelativePath(for: sampleURL)
                    let destURL = versionDir.appendingPathComponent(relativePath)
                    let destDir = destURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                    try? FileManager.default.copyItem(at: sampleURL, to: destURL)
                }
                // Rewrite .als: update paths to Samples/Imported/ and re-gzip
                let alsName = alsURL.lastPathComponent
                let outputALSURL = versionDir.appendingPathComponent(alsName)
                try? ALSRewriter.rewriteAndCompress(
                    alsURL: alsURL,
                    externalSamples: sampleCollection.collectedPaths,
                    backupProjectURL: versionDir,
                    outputURL: outputALSURL
                )
            }
        }

        // 7. Build manifest from the records now in the database.
        //    Use pool.write (not read) to ensure we see the records just inserted above,
        //    avoiding any WAL snapshot isolation that could miss recently committed writes.
        let allRecords = try await db.pool.write { db in
            try BackupFileRecord
                .filter(Column("versionID") == versionID)
                .fetchAll(db)
        }

        // Use the first adapter's ID in the manifest (single-destination per version design for Phase 1).
        let primaryAdapterID = targetAdapters[0].id
        let manifest = BackupManifest(
            versionID: versionID,
            projectID: project.id,
            destinationID: primaryAdapterID,
            files: allRecords.compactMap { rec in
                rec.checksum.map {
                    ManifestEntry(
                        relativePath: rec.relativePath,
                        size: Int64(rec.sourceSize),
                        checksum: $0
                    )
                }
            }
        )

        // 8. Finalize: transition each destination version to copy_complete with counts.
        for adapter in targetAdapters {
            try await VersionManager.finalizeCopy(
                versionID: versionID,
                manifest: BackupManifest(
                    versionID: versionID,
                    projectID: project.id,
                    destinationID: adapter.id,
                    files: manifest.files
                ),
                db: db.pool
            )
        }

        // 9. Verification pass: re-read destination checksums and compare to stored values.
        try await updateVersionStatus(versionID: versionID, status: .verifying)

        var allVerified = true
        var corruptReason: String? = nil

        // For each destination adapter, re-read each destination file's checksum and compare.
        for adapter in targetAdapters {
            let versionDir = URL(fileURLWithPath: adapter.config.rootPath)
                .appendingPathComponent(versionID)

            for record in allRecords {
                guard let storedChecksum = record.checksum else { continue }
                let destFile = versionDir.appendingPathComponent(record.relativePath)
                let actualChecksum = try FileCopyPipeline.computeChecksum(of: destFile)
                if actualChecksum != storedChecksum {
                    allVerified = false
                    corruptReason = "Checksum mismatch for \(record.relativePath)"
                    break
                }
            }
            if !allVerified { break }
        }

        // 10. Mark version as verified or corrupt.
        if allVerified {
            try await VersionManager.markVerified(versionID: versionID, db: db.pool)
        } else {
            try await VersionManager.markCorrupt(
                versionID: versionID,
                reason: corruptReason ?? "Unknown checksum mismatch",
                db: db.pool
            )
        }

        // 11. Retention pruning — only after new version is verified.
        if allVerified {
            for adapter in targetAdapters {
                _ = try await VersionManager.pruneOldVersions(
                    for: project.id,
                    destinationID: adapter.id,
                    retentionCount: adapter.config.retentionCount,
                    destinationRootPath: adapter.config.rootPath,
                    db: db.pool
                )
            }
        }

        // 12. Update the FileEntry cache so the next backup has incremental data.
        //     We store FileEntry values (filesystem-precision mtime/size) rather than
        //     DB-fetched records to avoid millisecond truncation in future comparisons.
        //     For files that were copied this run: use the new FileEntry from allFiles.
        //     For files that were skipped this run: preserve the previous cached FileEntry.
        if allVerified {
            var nextCache = previousEntries  // start with all previous entries (covers skipped files)
            // Build a lookup of current FileEntry by relativePath
            let currentByPath = Dictionary(uniqueKeysWithValues: allFiles.map { ($0.relativePath, $0) })
            // Override with current entries for files that were copied
            for file in filesToCopy {
                nextCache[file.relativePath] = currentByPath[file.relativePath] ?? file
            }
            fileEntryCache[project.id] = nextCache
        }

        // Persist sample collection metadata to backupVersion rows.
        // Run regardless of parse outcome so the DB always reflects ALS results:
        // - No .als found: all zeros, hasParseWarning=false (empty defaults)
        // - Parse succeeded: counts and paths populated
        // - Parse failed: hasParseWarning=true, counts zero
        if alsURL != nil || sampleCollection.hasParseWarning {
            let collectedJSON = BackupVersion.encodePaths(sampleCollection.collectedPaths)
            let missingJSON   = BackupVersion.encodePaths(sampleCollection.missingPaths)
            try? await db.pool.write { database in
                try database.execute(
                    sql: """
                        UPDATE backupVersion
                        SET collectedSampleCount = ?,
                            collectedSamplePaths = ?,
                            missingSampleCount   = ?,
                            missingSamplePaths   = ?,
                            hasParseWarning      = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        sampleCollection.collectedCount,
                        collectedJSON,
                        sampleCollection.missingCount,
                        missingJSON,
                        sampleCollection.hasParseWarning,
                        versionID
                    ]
                )
            }
        }

        let finalStatus: VersionStatus = allVerified ? .verified : .corrupt
        logger.info("executeJob: complete — versionID=\(versionID, privacy: .public) status=\(finalStatus.rawValue, privacy: .public)")
        return BackupJobResult(
            versionID: versionID,
            projectID: project.id,
            filesCopied: filesToCopy.count,
            filesSkipped: skippedCount,
            totalBytes: manifest.totalBytes,
            status: finalStatus,
            destinationResults: destinationResults,
            sampleCollection: sampleCollection
        )
    }

    // MARK: - Helpers

    /// Update the status of a version across all its DB rows (all destinations share the same versionID).
    private func updateVersionStatus(versionID: String, status: VersionStatus) async throws {
        do {
            try await db.pool.write { db in
                try db.execute(
                    sql: "UPDATE backupVersion SET status = ? WHERE id = ?",
                    arguments: [status.rawValue, versionID]
                )
            }
        } catch {
            logger.error("executeJob: updateVersionStatus failed — \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

// MARK: - BackupEngineError

public enum BackupEngineError: Error, Sendable {
    case noDestinationsConfigured
    case projectNotFound
}
