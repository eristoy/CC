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
            switch coordinator.status {
            case .idle:
                Label("AbletonBackup", systemImage: coordinator.statusIcon)
            case .running:
                Label("AbletonBackup", systemImage: coordinator.statusIcon)
            case .error:
                Label("AbletonBackup", systemImage: coordinator.statusIcon)
            }
        }
        .menuBarExtraStyle(.menu)   // Standard dropdown menu (not floating window)
    }
}
