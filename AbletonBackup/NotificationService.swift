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

    // MARK: - ALS Sample Warnings (PRSR-01, PRSR-02)

    /// Post a "samples missing" warning notification after a backup with unreachable external samples.
    /// Tapping the notification navigates to the backup history entry for that version.
    /// - Parameters:
    ///   - projectName: Display name of the project.
    ///   - count: Number of missing samples.
    ///   - versionID: The backupVersion.id; stored in userInfo so tap navigates to the right history row.
    static func sendMissingSamplesWarning(projectName: String, count: Int, versionID: String) {
        notifLogger.info("sendMissingSamplesWarning: posting — project=\(projectName, privacy: .public) count=\(count)")
        let content = UNMutableNotificationContent()
        content.title = "\(count) sample\(count == 1 ? "" : "s") missing from \(projectName)"
        content.body = "Backup completed. Tap to view missing sample details."
        content.sound = .default
        content.userInfo = ["versionID": versionID]
        post(content: content, identifier: "missing-samples-\(projectName)-\(Date().timeIntervalSince1970)")
    }

    /// Post a "could not parse .als" warning notification when gzip or XML parsing fails.
    /// Tapping the notification navigates to the backup history entry for that version.
    static func sendALSParseWarning(projectName: String, versionID: String) {
        notifLogger.info("sendALSParseWarning: posting — project=\(projectName, privacy: .public)")
        let content = UNMutableNotificationContent()
        content.title = "Could not parse .als — \(projectName)"
        content.body = "External samples not included. Tap to view backup details."
        content.sound = .default
        content.userInfo = ["versionID": versionID]
        post(content: content, identifier: "als-parse-warning-\(projectName)-\(Date().timeIntervalSince1970)")
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let versionID = response.notification.request.content.userInfo["versionID"] as? String {
            // Post to main thread so HistoryView can respond and navigate to this version
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .navigateToVersion,
                    object: nil,
                    userInfo: ["versionID": versionID]
                )
            }
        }
        completionHandler()
    }
}

// MARK: - Notification.Name

extension Notification.Name {
    static let navigateToVersion = Notification.Name("com.abletonbackup.navigateToVersion")
}
