import SwiftUI

/// The dropdown content shown when the user clicks the menu bar icon.
/// Completed in Plan 02-04 after all components exist.
struct MenuBarView: View {
    @Environment(BackupCoordinator.self) private var coordinator

    var body: some View {
        VStack {
            Text("AbletonBackup")
                .font(.headline)
            Divider()
            Text("Status: \(statusText)")
            Divider()
            Button("Back Up Now") {
                Task { await coordinator.runBackup(trigger: .manual) }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle:         return "Idle"
        case .running:      return "Running…"
        case .error(let e): return "Error: \(e)"
        }
    }
}
