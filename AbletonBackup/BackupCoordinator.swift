import Foundation
import BackupEngine

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

    // MARK: - Login item (APP-03)

    let loginItemManager = LoginItemManager()

    // MARK: - Private

    private var engine: BackupEngine?
    private var db: AppDatabase?
    private var watchedProjectsFolder: URL?
    private var watcher: FSEventsWatcher?
    private let scheduler = SchedulerTask()

    // Phase 2 bootstrap destination ID — constant for upsert idempotency
    private let bootstrapDestID = "bootstrap-local"
    private let bootstrapProjectID = "bootstrap-project"

    // MARK: - Init

    init() {
        Task { @MainActor [weak self] in
            await self?.setup()
        }
    }

    // MARK: - Setup

    private func setup() async {
        // 1. Request notification permission (NOTIF-01, NOTIF-02)
        NotificationService.requestAuthorization()

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
            status = .error("Could not access Application Support: \(error.localizedDescription)")
            return
        }

        // 3. Open/create GRDB database
        let database: AppDatabase
        do {
            let dbPath = appSupport.appendingPathComponent("abletonbackup.db").path
            database = try AppDatabase.makeShared(at: dbPath)
            self.db = database
        } catch {
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
            status = .error("Could not save destination config: \(error.localizedDescription)")
            return
        }

        // 5. Initialize BackupEngine with the bootstrap adapter.
        //    BackupEngine.adapters is private — initialize once with correct adapters.
        //    Phase 3 reinitializes with settings-configured adapters.
        let adapter = LocalDestinationAdapter(config: dest)
        self.engine = BackupEngine(db: database, adapters: [adapter])

        // 6. Discover Ableton Projects folder (DISC-01)
        let folder = AbletonPrefsReader.discoverProjectsFolder()
        self.watchedProjectsFolder = folder

        // 7. Start FSEvents watcher (TRIG-01)
        if let folder {
            startWatching(folder: folder)
        }

        // 8. Start scheduled backup loop (TRIG-02)
        scheduler.start(interval: SchedulerTask.defaultInterval) { [weak self] in
            await self?.runBackup(trigger: .scheduled)
        }
    }

    // MARK: - FSEvents (TRIG-01)

    private func startWatching(folder: URL) {
        // Outer closure is nonisolated (required by FSEventsWatcher API).
        // Inner Task hops explicitly to @MainActor for coordinator state access.
        // Swift 6: valid — the Task closure declares @MainActor isolation explicitly.
        watcher = FSEventsWatcher(url: folder) { [weak self] path in
            Task { @MainActor [weak self] in
                await self?.handleALSChange(at: path)
            }
        }
    }

    private func handleALSChange(at path: String) async {
        // FSEventsWatcher already filters to .als — double-check for safety
        guard path.hasSuffix(".als") else { return }
        await runBackup(trigger: .fsEvent)
    }

    // MARK: - Backup execution (TRIG-01, TRIG-02, TRIG-03)

    /// Run a backup. Guards against concurrent runs via status check.
    /// BackupEngine.runJob() handles per-project deduplication internally.
    func runBackup(trigger: BackupTrigger) async {
        guard case .idle = status else { return }
        guard let engine, let db, let watchedProjectsFolder else { return }

        status = .running
        let projectName = watchedProjectsFolder.lastPathComponent

        // Phase 2 bootstrap: upsert the single watched project into DB
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
            NotificationService.sendBackupSuccess(projectName: projectName)  // NOTIF-01
        } catch {
            let msg = error.localizedDescription
            status = .error(msg)
            NotificationService.sendBackupFailure(projectName: projectName, error: msg)  // NOTIF-02
        }
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
