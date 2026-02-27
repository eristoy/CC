import Foundation
import BackupEngine

// MARK: - BackupStatus

/// Represents the current backup activity state.
/// Drives the menu bar icon and status text.
public enum BackupStatus: Sendable {
    case idle
    case running
    case error(String)

    /// SF Symbol name for the current status.
    public var iconName: String {
        switch self {
        case .idle:    return "waveform"
        case .running: return "arrow.triangle.2.circlepath"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - BackupTrigger

/// The source that initiated a backup run.
public enum BackupTrigger: Sendable {
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
public final class BackupCoordinator {
    // MARK: - Published state (drives menu bar icon + menu content)

    /// Current backup activity status.
    public var status: BackupStatus = .idle

    /// Timestamp of the last completed backup (nil if never run).
    public var lastBackupAt: Date? = nil

    /// SF Symbol name for the current status (used in MenuBarExtra label).
    public var statusIcon: String { status.iconName }

    // MARK: - Private dependencies (wired in later plans)

    // FSEventsWatcher is held here after Plan 02-02
    // SchedulerTask is held here after Plan 02-03
    // NotificationService is called here after Plan 02-03

    // MARK: - Init

    public init() {
        // Phase 2: BackupEngine + AppDatabase initialization is deferred to
        // Plan 02-04 where watch folder and destination are wired together.
        // Skeleton kept minimal to compile cleanly.
    }

    // MARK: - Backup execution (stub — completed in Plan 02-04)

    /// Run a backup with the given trigger source.
    /// Guards against concurrent runs for the same trigger source.
    public func runBackup(trigger: BackupTrigger) async {
        guard case .idle = status else { return }
        status = .running
        // Full implementation wired in Plan 02-04
        // Simulates a brief async operation for skeleton compilation
        try? await Task.sleep(for: .milliseconds(100))
        status = .idle
        lastBackupAt = Date()
    }
}
