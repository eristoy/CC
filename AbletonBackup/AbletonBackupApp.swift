import SwiftUI

@main
struct AbletonBackupApp: App {
    @State private var coordinator = BackupCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(coordinator)
                .task {
                    // Set notification delegate + request authorization at app launch.
                    // Must happen before BackupCoordinator.setup() posts any notifications.
                    NotificationService.setup()
                }
        } label: {
            // Dynamic icon driven by BackupCoordinator.status (@Observable)
            Label("AbletonBackup", systemImage: coordinator.statusIcon)
        }
        .menuBarExtraStyle(.menu)   // Standard dropdown menu (not floating window)

        Settings {
            SettingsView()
                .environment(coordinator)
        }
    }
}
