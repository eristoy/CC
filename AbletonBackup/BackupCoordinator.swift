import Foundation
import BackupEngine
import GRDB
import OSLog

// MARK: - BackupStatus

enum BackupStatus: Sendable, Equatable {
    case idle
    case running
    case error(String)

    /// SF Symbol name for the current status.
    var iconName: String {
        switch self {
        case .idle:    return "waveform"
        case .running: return "arrow.triangle.2.circlepath"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - BackupTrigger

/// The source that initiated a backup run.
enum BackupTrigger: Sendable {
    case fsEvent   // Ableton project save detected via FSEvents
    case scheduled // Periodic scheduler fired
    case manual    // User clicked "Back Up Now"
}

// MARK: - BackupCoordinator

/// Central state container and orchestrator for the AbletonBackup app.
///
/// @Observable + @MainActor: all mutable state is isolated to the main actor so
/// SwiftUI MenuBarExtra views update correctly. Background work is dispatched
/// via Task and hops back to MainActor to update status.
///
/// Multi-watcher model (Phase 3+):
/// - `watchFolders` is the DB-backed list of monitored directories (observable)
/// - `watchers` is the live dictionary of FSEventsWatcher instances keyed by path
/// - `addWatchFolder(url:)` inserts a DB row and starts a new watcher
/// - `removeWatchFolder(_:)` stops the watcher and removes the DB row
@Observable
@MainActor
final class BackupCoordinator {

    // MARK: - Observable state (drives menu bar icon + menu content)

    /// Current backup activity status.
    var status: BackupStatus = .idle

    /// Timestamp of the last completed backup (nil if never run).
    var lastBackupAt: Date? = nil

    /// SF Symbol name for the current status (used in MenuBarExtra label).
    var statusIcon: String { status.iconName }

    /// DB-backed list of watched folders. Drives WatchFolders pane UI.
    var watchFolders: [WatchFolder] = []

    /// Exposes the database pool for Settings/History GRDB ValueObservation.
    var database: AppDatabase? { db }

    private let logger = Logger(subsystem: "com.abletonbackup", category: "Coordinator")

    // MARK: - Login item (APP-03)

    let loginItemManager = LoginItemManager()

    // MARK: - Private

    private var engine: BackupEngine?
    private var db: AppDatabase?
    private var watchers: [String: FSEventsWatcher] = [:]
    private let scheduler = SchedulerTask()

    // Phase 2/3 bootstrap destination ID — constant for upsert idempotency across launches
    private let bootstrapDestID = "bootstrap-local"
    // Single-project ID used in runBackup bootstrap logic
    private let bootstrapProjectID = "bootstrap-project"

    // MARK: - Init

    init() {
        Task { @MainActor [weak self] in
            await self?.setup()
        }
    }

    // MARK: - Setup

    private func setup() async {
        logger.info("setup: start")
        // 1. Notification auth handled at app entry (AbletonBackupApp .task modifier calls NotificationService.setup())
        logger.info("setup: notification auth handled at app entry")

        // 2. Resolve Application Support directory
        let appSupport: URL
        do {
            appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("AbletonBackup")
            try FileManager.default.createDirectory(
                at: appSupport,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("setup: failed — \(error.localizedDescription, privacy: .public)")
            status = .error("Could not access Application Support: \(error.localizedDescription)")
            return
        }

        // 3. Open/create GRDB database
        let database: AppDatabase
        do {
            let dbPath = appSupport.appendingPathComponent("abletonbackup.db").path
            database = try AppDatabase.makeShared(at: dbPath)
            self.db = database
            logger.info("setup: database opened at \(dbPath, privacy: .public)")
        } catch {
            logger.error("setup: failed — \(error.localizedDescription, privacy: .public)")
            status = .error("Database setup failed: \(error.localizedDescription)")
            return
        }

        // 4. Build Phase 2 bootstrap destination (local folder in App Support)
        //    Phase 3 replaces this with real multi-destination configuration from settings UI.
        let backupDir = appSupport.appendingPathComponent("Backup")
        do {
            try FileManager.default.createDirectory(
                at: backupDir,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("setup: failed — \(error.localizedDescription, privacy: .public)")
            status = .error("Could not create backup directory: \(error.localizedDescription)")
            return
        }

        let dest = DestinationConfig(
            id: bootstrapDestID,
            type: .local,
            name: "App Support Backup",
            rootPath: backupDir.path,
            retentionCount: 10,
            createdAt: Date()
        )

        // Upsert destination config into DB (idempotent across launches)
        do {
            try await database.pool.write { db in
                try dest.save(db)
            }
        } catch {
            logger.error("setup: failed — \(error.localizedDescription, privacy: .public)")
            status = .error("Could not save destination config: \(error.localizedDescription)")
            return
        }

        // 5. Initialize BackupEngine with the bootstrap adapter.
        let adapter = LocalDestinationAdapter(config: dest)
        self.engine = BackupEngine(db: database, adapters: [adapter])

        // 6. Bootstrap watch folders: if watchFolder table is empty, seed from AbletonPrefsReader.
        //    On subsequent launches the DB already has rows — skip discovery.
        do {
            let count = try await database.pool.read { db in
                try WatchFolder.fetchCount(db)
            }
            if count == 0, let discovered = AbletonPrefsReader.discoverProjectsFolder() {
                let folder = WatchFolder(path: discovered.path, name: discovered.lastPathComponent)
                try await database.pool.write { db in try folder.save(db) }
                logger.info("setup: bootstrapped watch folder — \(discovered.path, privacy: .public)")
            } else if count == 0 {
                // Not a fatal error — scheduler and manual trigger still start.
                // User can configure in Phase 3 settings.
                logger.warning("setup: Ableton Projects folder not found — configure in Settings")
                status = .error("Ableton Projects folder not found. Configure in Settings.")
                // Do NOT return — scheduler still starts
            }
        } catch {
            logger.warning("setup: watch folder bootstrap failed — \(error.localizedDescription, privacy: .public)")
            // Non-fatal: continue without pre-seeded folder
        }

        // 7. Load all watch folders from DB and start watchers
        do {
            let folders = try await database.pool.read { db in
                try WatchFolder.order(Column("addedAt").asc).fetchAll(db)
            }
            self.watchFolders = folders
            for f in folders {
                startWatcher(for: URL(fileURLWithPath: f.path))
            }
            logger.info("setup: loaded \(folders.count) watch folder(s)")
        } catch {
            logger.error("setup: failed to load watch folders — \(error.localizedDescription, privacy: .public)")
            // Non-fatal: watchers simply won't start, user can reconfigure
        }

        // 8. Start scheduled backup loop (TRIG-02)
        scheduler.start(interval: SchedulerTask.defaultInterval) { [weak self] in
            await self?.runBackup(trigger: .scheduled)
        }
        logger.info("setup: complete — \(self.watchFolders.count) folder(s) watched")
    }

    // MARK: - Watch Folder Management

    /// Add a new folder to the watch list. Inserts a DB row and starts a new FSEventsWatcher.
    /// Does not rebuild existing watchers.
    func addWatchFolder(url: URL) async {
        guard let db else { return }
        let folder = WatchFolder(path: url.path, name: url.lastPathComponent)
        do {
            try await db.pool.write { database in try folder.save(database) }
            watchFolders.append(folder)
            startWatcher(for: url)
            logger.info("addWatchFolder: added \(url.path, privacy: .public)")
        } catch {
            logger.error("addWatchFolder failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Remove a folder from the watch list. Stops the watcher and removes its DB row.
    func removeWatchFolder(_ folder: WatchFolder) async {
        guard let db else { return }
        // Stop watcher first — prevents new events from firing during DB delete
        watchers.removeValue(forKey: folder.path)
        do {
            try await db.pool.write { database in try WatchFolder.deleteOne(database, key: folder.id) }
            watchFolders.removeAll { $0.id == folder.id }
            logger.info("removeWatchFolder: removed \(folder.path, privacy: .public)")
        } catch {
            logger.error("removeWatchFolder failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - FSEvents (TRIG-01)

    private func startWatcher(for url: URL) {
        guard watchers[url.path] == nil else { return }  // already watching
        watchers[url.path] = FSEventsWatcher(url: url) { [weak self] path in
            Task { @MainActor [weak self] in
                await self?.handleALSChange(at: path)
            }
        }
    }

    private func handleALSChange(at path: String) async {
        // FSEventsWatcher already filters to .als — double-check for safety
        guard path.hasSuffix(".als") else { return }

        // Respect auto-backup toggle (APP-04): if the user has disabled auto-backup, skip FSEvent triggers
        guard UserDefaults.standard.object(forKey: "autoBackupEnabled") == nil
              || UserDefaults.standard.bool(forKey: "autoBackupEnabled") else { return }

        // Update lastTriggeredAt for the matching WatchFolder
        let watchedPath = (path as NSString).deletingLastPathComponent
        if let idx = watchFolders.firstIndex(where: { path.hasPrefix($0.path) || watchedPath == $0.path }) {
            watchFolders[idx].lastTriggeredAt = Date()
            // Persist the timestamp update
            if let db, let updatedFolder = watchFolders[safe: idx] {
                let folderToUpdate = updatedFolder
                do {
                    try await db.pool.write { database in try folderToUpdate.save(database) }
                } catch {
                    logger.warning("handleALSChange: failed to update lastTriggeredAt — \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        await runBackup(trigger: .fsEvent)
    }

    // MARK: - Backup execution (TRIG-01, TRIG-02, TRIG-03)

    /// Run a backup. Guards against concurrent runs via status check.
    /// BackupEngine.runJob() handles per-project deduplication internally.
    func runBackup(trigger: BackupTrigger) async {
        logger.info("runBackup: start — trigger=\(String(describing: trigger), privacy: .public)")
        guard case .idle = status else {
            logger.warning("runBackup: guard — already running, ignoring \(String(describing: trigger), privacy: .public) trigger")
            return
        }
        guard let engine, let db else {
            let reason: String
            if engine == nil {
                reason = "Backup engine not initialized — setup may still be in progress"
            } else {
                reason = "Database not ready — setup may still be in progress"
            }
            logger.error("runBackup: guard — not configured: \(reason, privacy: .public)")
            status = .error(reason)
            return
        }
        guard !watchers.isEmpty, let firstFolder = watchFolders.first else {
            let reason = "No watched folder configured — add a folder in Settings"
            logger.error("runBackup: guard — \(reason, privacy: .public)")
            status = .error(reason)
            return
        }

        status = .running
        let watchedProjectsFolder = URL(fileURLWithPath: firstFolder.path)
        let projectName = watchedProjectsFolder.lastPathComponent

        // Phase 2/3 bootstrap: upsert the first watch folder as the single watched project
        // Phase 4+ multi-destination work will replace this with per-folder job dispatch
        let project = Project(
            id: bootstrapProjectID,
            name: projectName,
            path: watchedProjectsFolder.path
        )

        do {
            // Upsert project (idempotent — path and name may not change across runs)
            try await db.pool.write { database in
                try project.save(database)
            }

            let job = BackupJob(project: project, destinationIDs: [bootstrapDestID])
            _ = try await engine.runJob(job)

            status = .idle
            lastBackupAt = Date()
            logger.info("runBackup: success — \(projectName, privacy: .public)")
            NotificationService.sendBackupSuccess(projectName: projectName)  // NOTIF-01
        } catch {
            let msg = error.localizedDescription
            logger.error("runBackup: failed — \(msg, privacy: .public)")
            status = .error(msg)
            NotificationService.sendBackupFailure(projectName: projectName, error: msg)  // NOTIF-02
        }
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

// MARK: - CoordinatorError

enum CoordinatorError: Error, LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Watch folder or database not configured"
        }
    }
}
