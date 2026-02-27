// AbletonBackup/NotificationService.swift

import UserNotifications

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
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound]
            ) { _, _ in
                // Granted status persists in system preferences.
                // If denied, the user must re-enable in System Settings > Notifications.
            }
        }
    }

    // MARK: - Backup Success (NOTIF-01)

    /// Post a "Backup Complete" notification for the given project.
    /// - Parameter projectName: The display name of the backed-up project.
    static func sendBackupSuccess(projectName: String) {
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
            // Silently ignore delivery errors — notification is best-effort
            _ = error
        }
    }
}
