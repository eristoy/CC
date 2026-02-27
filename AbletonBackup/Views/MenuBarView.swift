import SwiftUI
import ServiceManagement

/// The dropdown content for the AbletonBackup menu bar item.
struct MenuBarView: View {
    @Environment(BackupCoordinator.self) private var coordinator
    @State private var loginItemError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            statusSection
            Divider()

            // Backup action (TRIG-03)
            backupSection
            Divider()

            // Settings
            settingsSection
            Divider()

            // Quit
            Button("Quit AbletonBackup") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: coordinator.statusIcon)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if let lastAt = coordinator.lastBackupAt {
                Text("Last backup: \(lastAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            } else {
                Text("Never backed up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Backup actions

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Back Up Now") {
                Task { await coordinator.runBackup(trigger: .manual) }
            }
            .disabled(coordinator.status == .running)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Launch at Login toggle (APP-03)
            Toggle(isOn: loginItemBinding) {
                Text("Launch at Login")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Show approval hint if SMAppService requires it
            if coordinator.loginItemManager.status == .requiresApproval {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Approval required in System Settings")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                    Button("Open System Settings…") {
                        coordinator.loginItemManager.openSystemSettings()
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            }

            if let error = loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Helpers

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { coordinator.loginItemManager.isEnabled },
            set: { newValue in
                loginItemError = nil
                do {
                    try coordinator.loginItemManager.setEnabled(newValue)
                } catch {
                    loginItemError = error.localizedDescription
                }
            }
        )
    }

    private var statusColor: Color {
        switch coordinator.status {
        case .idle:    return .green
        case .running: return .blue
        case .error:   return .red
        }
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle:         return "Idle"
        case .running:      return "Backing up…"
        case .error(let e): return "Error: \(e)"
        }
    }
}
