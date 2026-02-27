// AbletonBackup/NotificationService.swift

import UserNotifications
import OSLog

private let notifLogger = Logger(subsystem: "com.abletonbackup", category: "Notifications")

/// Wraps UNUserNotificationCenter for backup success/failure notifications.
///
/// No sandbox entitlements required — distributing outside Mac App Store.
/// NSUserNotificationAlertStyle = alert in Info.plist ensures persistent banners.
///
/// Call setup() once at app launch (AbletonBackupApp .task modifier).
/// setup() sets the delegate (required for foreground delivery) and requests authorization.
struct NotificationService {

    // MARK: - Setup (call once at app launch)

    /// Sets the UNUserNotificationCenter delegate and requests authorization.
    /// Must be called at app launch before any notification is posted.
    /// Without a delegate, foreground notifications are silently suppressed.
    static func setup() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            notifLogger.info("requestAuthorization: granted=\(granted) error=\(error?.localizedDescription ?? "nil", privacy: .public)")
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

// MARK: - NotificationDelegate

/// Ensures notifications display as banners while the app is in the foreground.
/// Menu bar apps are always in the foreground — without this delegate,
/// UNUserNotificationCenter silently drops all notifications.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()
    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner + play sound even when app is in foreground
        completionHandler([.banner, .sound])
    }
}
