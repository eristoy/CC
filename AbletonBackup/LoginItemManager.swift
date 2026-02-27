// AbletonBackup/LoginItemManager.swift

import ServiceManagement

/// Manages the "Launch at Login" setting using SMAppService (macOS 13+).
///
/// Do NOT use LSSharedFileList — deprecated in macOS 13.
/// Do NOT cache enabled state in UserDefaults — System Settings can change it independently.
///
/// Always read SMAppService.mainApp.status live for current state.
struct LoginItemManager {

    // MARK: - State

    /// Whether the app is currently registered as a login item.
    ///
    /// Reads live from SMAppService — reflects changes made in System Settings.
    /// Returns false for .requiresApproval (registered but not yet approved).
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// The full SMAppService status — exposes .requiresApproval for UI handling.
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    // MARK: - Control (APP-03)

    /// Enable or disable launch at login.
    ///
    /// After enabling, check `status` for `.requiresApproval`:
    /// if present, call `openSystemSettings()` to direct user to System Settings.
    ///
    /// - Parameter enabled: true to register, false to unregister.
    /// - Throws: SMAppServiceError if registration fails unexpectedly.
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    // MARK: - System Settings Deep Link

    /// Open System Settings > General > Login Items.
    ///
    /// Call this when status == .requiresApproval to guide the user to approve
    /// the login item. The user must approve before the app launches at login.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
