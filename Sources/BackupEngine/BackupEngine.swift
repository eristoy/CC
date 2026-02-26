import Foundation
import GRDB

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

    private let db: AppDatabase
    /// Destination adapters keyed by their ID.
    private var adapters: [String: any DestinationAdapter]
    /// Running jobs keyed by projectID — used for deduplication.
    private var runningJobs: [String: Task<BackupJobResult, Error>]

    // MARK: - Init

    public init(db: AppDatabase, adapters: [any DestinationAdapter]) {
        self.db = db
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.id, $0) })
        self.runningJobs = [:]
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
            return try await existing.value
        }

        let task = Task {
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

        // 1. Resolve all files in the project directory.
        let allFiles = try ProjectResolver.resolve(at: URL(fileURLWithPath: project.path))

        // 2. Fetch previous manifest for incremental comparison (most recent verified version).
        let previousRecords = try await fetchPreviousManifest(projectID: project.id)
        let previousByPath = Dictionary(uniqueKeysWithValues: previousRecords.map { ($0.relativePath, $0) })

        // 3. Apply incremental filter: only copy files that changed since last verified backup.
        var filesToCopy: [FileEntry] = []
        var skippedCount = 0
        for file in allFiles {
            if ProjectResolver.needsCopy(entry: file, previousRecord: previousByPath[file.relativePath]) {
                filesToCopy.append(file)
            } else {
                skippedCount += 1
            }
        }

        // 4. Create a pending BackupVersion row for each destination.
        let versionID = VersionManager.newVersionID()
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

        // 7. Build manifest from the records now in the database.
        let allRecords = try await db.pool.read { db in
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

        let finalStatus: VersionStatus = allVerified ? .verified : .corrupt
        return BackupJobResult(
            versionID: versionID,
            projectID: project.id,
            filesCopied: filesToCopy.count,
            filesSkipped: skippedCount,
            totalBytes: manifest.totalBytes,
            status: finalStatus,
            destinationResults: destinationResults
        )
    }

    // MARK: - Helpers

    /// Update the status of a version across all its DB rows (all destinations share the same versionID).
    private func updateVersionStatus(versionID: String, status: VersionStatus) async throws {
        try await db.pool.write { db in
            try db.execute(
                sql: "UPDATE backupVersion SET status = ? WHERE id = ?",
                arguments: [status.rawValue, versionID]
            )
        }
    }

    /// Fetch BackupFileRecord rows from the most recent verified version for this project.
    ///
    /// Returns an empty array if no verified version exists yet (first backup).
    private func fetchPreviousManifest(projectID: String) async throws -> [BackupFileRecord] {
        try await db.pool.read { db in
            guard let latestVersion = try BackupVersion
                .filter(Column("projectID") == projectID)
                .filter(Column("status") == VersionStatus.verified.rawValue)
                .order(Column("createdAt").desc)
                .fetchOne(db) else {
                return []
            }

            return try BackupFileRecord
                .filter(Column("versionID") == latestVersion.id)
                .fetchAll(db)
        }
    }
}

// MARK: - BackupEngineError

public enum BackupEngineError: Error, Sendable {
    case noDestinationsConfigured
    case projectNotFound
}
