// AbletonBackup/SchedulerTask.swift

import Foundation
import OSLog

private let schedLogger = Logger(subsystem: "com.abletonbackup", category: "Scheduler")

/// Runs a repeating action at the specified interval using Swift Concurrency.
///
/// Uses Task.sleep(for:) — no BackgroundTasks framework needed (requires App Store).
/// The task is cancelled and restarted whenever the interval changes.
///
/// @MainActor isolation: stored Task reference is non-Sendable; isolation prevents races.
@MainActor
final class SchedulerTask {
    private var task: Task<Void, Never>?

    /// The default backup interval (1 hour). Phase 3 settings UI exposes this.
    static let defaultInterval: Duration = .seconds(3600)

    // MARK: - Control

    /// Start the scheduler with the given interval and action.
    /// Cancels any existing scheduled task before starting a new one.
    ///
    /// - Parameters:
    ///   - interval: Time to wait between action invocations.
    ///   - action: The async action to run on each tick. Runs on MainActor.
    func start(interval: Duration = defaultInterval, action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    // Task was cancelled during sleep — exit cleanly
                    break
                }
                guard !Task.isCancelled else { break }
                schedLogger.info("SchedulerTask: firing scheduled backup")
                await action()
                _ = self  // keep self alive during action
            }
        }
        schedLogger.info("SchedulerTask: started — interval=\(interval)")
    }

    /// Stop the scheduler.
    func stop() {
        schedLogger.info("SchedulerTask: stopped")
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
