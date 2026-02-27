// AbletonBackup/NotificationService.swift

import UserNotifications
import OSLog

private let notifLogger = Logger(subsystem: "com.abletonbackup", category: "Notifications")

/// Wraps UNUserNotificationCenter for backup success/failure notifications.
///
/// No sandbox entitlements required — distributing outside Mac App Store.
/// NSUserNotificationAlertStyle = alert in Info.plist ensures persistent banners.
///
/// Call requestAuthorization() once at app launch (AbletonBackupApp.init or .task modifier).
/// Do NOT re-request if already denied — check status first.
struct NotificationService {

    // MARK: - Authorization

    /// Request notification permission at first launch.
    /// Safe to call repeatedly — checks current status before requesting.
    /// Nonisolated: UNUserNotificationCenter uses its own internal queue.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            notifLogger.info("requestAuthorization: current status=\(settings.authorizationStatus.rawValue)")
            guard settings.authorizationStatus == .notDetermined else {
                notifLogger.info("requestAuthorization: skipping request — status already determined")
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound]
            ) { granted, error in
                notifLogger.info("requestAuthorization: result granted=\(granted) error=\(error?.localizedDescription ?? "nil", privacy: .public)")
            }
        }
    }

    // MARK: - Backup Success (NOTIF-01)

    /// Post a "Backup Complete" notification for the given project.
    /// - Parameter projectName: The display name of the backed-up project.
    static func sendBackupSuccess(projectName: String) {
        notifLogger.info("sendBackupSuccess: posting — project=\(projectName, privacy: .public)")
        let content = UNMutableNotificationContent()
        content.title = "Backup Complete"
        content.body = "\(projectName) backed up successfully."
        content.sound = .default
        post(content: content, identifier: "success-\(projectName)-\(Date().timeIntervalSince1970)")
    }

    // MARK: - Backup Failure (NOTIF-02)

    /// Post a "Backup Failed" notification with the error description.
    /// - Parameters:
    ///   - projectName: The display name of the project that failed.
    ///   - error: The error message shown in the notification body.
    static func sendBackupFailure(projectName: String, error: String) {
        notifLogger.info("sendBackupFailure: posting — project=\(projectName, privacy: .public)")
        let content = UNMutableNotificationContent()
        content.title = "Backup Failed"
        content.body = "\(projectName): \(error)"
        content.sound = .defaultCritical
        post(content: content, identifier: "failure-\(projectName)-\(Date().timeIntervalSince1970)")
    }

    // MARK: - Private

    private static func post(content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // nil = deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            notifLogger.info("post: delivered identifier=\(identifier, privacy: .public) error=\(error?.localizedDescription ?? "nil", privacy: .public)")
        }
    }
}
