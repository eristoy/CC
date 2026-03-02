import SwiftUI
import BackupEngine

struct GeneralSettingsView: View {
    @Environment(BackupCoordinator.self) private var coordinator
    @AppStorage("autoBackupEnabled") private var autoBackupEnabled: Bool = true
    @State private var retentionCount: Int = 10

    var body: some View {
        Form {
            Section("Backup") {
                Toggle("Auto-backup on save", isOn: $autoBackupEnabled)
                    .help("When enabled, saving an Ableton project triggers an automatic backup")
                Stepper("Keep \(retentionCount) version\(retentionCount == 1 ? "" : "s")",
                        value: $retentionCount, in: 1...50)
                    .onChange(of: retentionCount) { _, newValue in
                        saveRetentionCount(newValue)
                    }
                    .help("Number of backup versions to keep per project. Oldest versions are pruned on the next backup run.")
            }

            Section("Login") {
                Toggle("Launch at Login", isOn: loginItemBinding)
                if coordinator.loginItemManager.status == .requiresApproval {
                    Button("Open System Settings to approve…") {
                        coordinator.loginItemManager.openSystemSettings()
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await loadRetentionCount() }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { coordinator.loginItemManager.isEnabled },
            set: { newValue in try? coordinator.loginItemManager.setEnabled(newValue) }
        )
    }

    private func loadRetentionCount() async {
        guard let db = coordinator.database else { return }
        let count = try? await db.pool.read { database in
            try DestinationConfig.fetchOne(database)?.retentionCount
        }
        if let count { retentionCount = count }
    }

    private func saveRetentionCount(_ count: Int) {
        guard let db = coordinator.database else { return }
        Task {
            try? await db.pool.write { database in
                if var dest = try DestinationConfig.fetchOne(database) {
                    dest.retentionCount = count
                    try dest.save(database)
                }
            }
        }
    }
}
