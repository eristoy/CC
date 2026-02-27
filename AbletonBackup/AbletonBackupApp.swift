import SwiftUI

@main
struct AbletonBackupApp: App {
    @State private var coordinator = BackupCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(coordinator)
        } label: {
            // Dynamic icon driven by BackupCoordinator.status (@Observable)
            Label("AbletonBackup", systemImage: coordinator.statusIcon)
        }
        .menuBarExtraStyle(.menu)   // Standard dropdown menu (not floating window)
    }
}
