import SwiftUI
import GRDB
import BackupEngine

struct DestinationsSettingsView: View {
    @Environment(BackupCoordinator.self) private var coordinator
    @State private var destinations: [DestinationConfig] = []

    var body: some View {
        VStack(spacing: 0) {
            if destinations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No destinations configured")
                        .foregroundStyle(.secondary)
                    Text("Destination configuration will be available in a future update.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(destinations, id: \.id) { dest in
                    DestinationRow(destination: dest)
                }
                .listStyle(.inset)
            }

            // Footer note — no add/remove in Phase 3
            Divider()
            HStack {
                Text("Destination management coming in a future update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.background)
        }
        .task { await loadDestinations() }
    }

    private func loadDestinations() async {
        guard let db = coordinator.database else { return }
        let results = try? await db.pool.read { database in
            try DestinationConfig.order(Column("createdAt").asc).fetchAll(database)
        }
        destinations = results ?? []
    }
}

// MARK: - DestinationRow

struct DestinationRow: View {
    let destination: DestinationConfig

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name)
                    .fontWeight(.medium)
                Text(destination.rootPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Retains \(destination.retentionCount) version\(destination.retentionCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch destination.type {
        case .local:   return "externaldrive.fill"
        case .nas:     return "network"
        case .icloud:  return "icloud.fill"
        case .github:  return "chevron.left.forwardslash.chevron.right"
        }
    }
}
