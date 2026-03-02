import SwiftUI
import AppKit
import BackupEngine

struct WatchFoldersSettingsView: View {
    @Environment(BackupCoordinator.self) private var coordinator
    /// Selected folder ID (String is Hashable — avoids requiring WatchFolder: Hashable)
    @State private var selectedFolderID: String?
    @State private var showRemoveConfirmation = false

    /// The WatchFolder corresponding to the current selection.
    private var selectedFolder: WatchFolder? {
        coordinator.watchFolders.first { $0.id == selectedFolderID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.watchFolders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No watch folders configured")
                        .foregroundStyle(.secondary)
                    Text("Press + to add a folder to monitor for Ableton project saves.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(coordinator.watchFolders, id: \.id, selection: $selectedFolderID) { folder in
                    WatchFolderRow(folder: folder)
                }
                .listStyle(.inset)
            }

            Divider()

            // +/- toolbar below list (macOS standard pattern)
            HStack(spacing: 0) {
                Button {
                    addWatchFolder()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Add watch folder")

                Button {
                    showRemoveConfirmation = true
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(selectedFolderID == nil)
                .help("Remove selected watch folder")

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.background)
        }
        .confirmationDialog(
            "Stop watching '\(selectedFolder?.name ?? "")'?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Watching", role: .destructive) {
                if let folder = selectedFolder {
                    selectedFolderID = nil
                    Task { await coordinator.removeWatchFolder(folder) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing backups are not affected.")
        }
    }

    // CORRECT: runModal() called synchronously on main thread in button action
    private func addWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Watch Folder"
        panel.message = "Select a folder to watch for Ableton project saves"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await coordinator.addWatchFolder(url: url) }
    }
}

// MARK: - WatchFolderRow

struct WatchFolderRow: View {
    let folder: WatchFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(folder.name)
                .fontWeight(.medium)
            Text(folder.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let triggeredAt = folder.lastTriggeredAt {
                Text("Last backup: \(triggeredAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Not yet triggered")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
