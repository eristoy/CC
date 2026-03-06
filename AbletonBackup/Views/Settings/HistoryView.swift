import SwiftUI
import GRDB
import BackupEngine

// MARK: - BackupEvent

/// One logical backup run across all destinations.
/// Groups all BackupVersion entries that share the same timestamp prefix
/// (first 23 characters of the version ID).
private struct BackupEvent: Identifiable {
    var id: String                      // timestamp prefix — first 23 chars of BackupVersion.id
    var timestamp: Date                 // createdAt of first version in the group
    var destinations: [BackupVersion]
    var overallStatus: VersionStatus    // .corrupt if any destination is corrupt, else .verified

    // MARK: Sample summary

    var totalMissingSamples: Int { destinations.reduce(0) { $0 + $1.missingSampleCount } }
    var hasParseWarning: Bool { destinations.contains { $0.hasParseWarning } }
    var hasSampleWarning: Bool { totalMissingSamples > 0 || hasParseWarning }
}

extension BackupEvent: Hashable {
    static func == (lhs: BackupEvent, rhs: BackupEvent) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private func groupVersions(_ versions: [BackupVersion]) -> [BackupEvent] {
    let grouped = Dictionary(grouping: versions) { v in
        String(v.id.prefix(23))  // "yyyy-MM-dd'T'HHmmss.SSS"
    }
    return grouped.map { (prefix, group) in
        let sorted = group.sorted { $0.createdAt < $1.createdAt }
        let isCorrupt = group.contains { $0.status == .corrupt }
        return BackupEvent(
            id: prefix,
            timestamp: sorted.first!.createdAt,
            destinations: group,
            overallStatus: isCorrupt ? .corrupt : .verified
        )
    }.sorted { $0.timestamp > $1.timestamp }
}

// MARK: - HistoryView

struct HistoryView: View {
    @Environment(BackupCoordinator.self) private var coordinator
    @State private var projects: [Project] = []
    @State private var selectedProjectID: String?
    @State private var navigateToVersionID: String?

    private var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if projects.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No backup history yet")
                            .foregroundStyle(.secondary)
                        Text("Backup history will appear here after your first backup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List(projects, id: \.id, selection: $selectedProjectID) { project in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).fontWeight(.medium)
                            if let lastAt = project.lastBackupAt {
                                Text(lastAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No completed backups")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Projects")
        } detail: {
            if let project = selectedProject {
                VersionListView(project: project, navigateToVersionID: $navigateToVersionID)
                    .environment(coordinator)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Select a project to view its backup history")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToVersion)) { note in
            guard let versionID = note.userInfo?["versionID"] as? String else { return }
            navigateToVersionID = versionID
            // Open Settings to History tab so user sees the navigation
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            // Find the project that owns this version
            Task {
                guard let db = coordinator.database else { return }
                if let version = try? await db.pool.read({ database in
                    try BackupVersion.filter(Column("id") == versionID).fetchOne(database)
                }) {
                    selectedProjectID = version.projectID
                }
            }
        }
        .task {
            guard let db = coordinator.database else { return }
            let observation = ValueObservation.tracking { database in
                try Project
                    .filter(Column("lastBackupAt") != nil)
                    .order(Column("name").asc)
                    .fetchAll(database)
            }
            do {
                for try await fresh in observation.values(in: db.pool, scheduling: .mainActor) {
                    projects = fresh
                }
            } catch {
                // Observation ended — view disappeared or DB error; no action needed
            }
        }
    }
}

// MARK: - VersionListView

private struct VersionListView: View {
    @Environment(BackupCoordinator.self) private var coordinator
    let project: Project
    @Binding var navigateToVersionID: String?
    @State private var events: [BackupEvent] = []
    @State private var destinations: [String: DestinationConfig] = [:]  // keyed by id
    @State private var selectedEventForNavigation: BackupEvent?

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No backup versions for \(project.name)")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(events, selection: $selectedEventForNavigation) { event in
                        NavigationLink(value: event) {
                            BackupEventRow(event: event, destinations: destinations)
                        }
                    }
                    .listStyle(.inset)
                    .navigationDestination(for: BackupEvent.self) { event in
                        VersionDetailView(event: event)
                    }
                }
            }
            .navigationTitle(project.name)
        }
        .task(id: project.id) {
            guard let db = coordinator.database else { return }

            // Load destinations once (rarely change)
            let destList = (try? await db.pool.read { database in
                try DestinationConfig.fetchAll(database)
            }) ?? []
            destinations = Dictionary(uniqueKeysWithValues: destList.map { ($0.id, $0) })

            // Observe versions for this project live
            let observation = ValueObservation.tracking { database in
                try BackupVersion
                    .filter(Column("projectID") == project.id)
                    .order(Column("createdAt").desc)
                    .fetchAll(database)
            }
            do {
                for try await fresh in observation.values(in: db.pool, scheduling: .mainActor) {
                    events = groupVersions(fresh)
                    // Auto-navigate if a pending deep-link is set
                    if let targetID = navigateToVersionID {
                        let prefix = String(targetID.prefix(23))
                        selectedEventForNavigation = events.first { $0.id == prefix }
                        navigateToVersionID = nil
                    }
                }
            } catch {
                // Observation ended — view disappeared or project changed
            }
        }
        .onChange(of: events) { _, newEvents in
            if let targetID = navigateToVersionID {
                let prefix = String(targetID.prefix(23))
                selectedEventForNavigation = newEvents.first { $0.id == prefix }
                navigateToVersionID = nil
            }
        }
    }
}

// MARK: - BackupEventRow

private struct BackupEventRow: View {
    let event: BackupEvent
    let destinations: [String: DestinationConfig]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Timestamp
                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .fontWeight(.medium)
                    .foregroundStyle(event.overallStatus == .corrupt ? .red : .primary)

                Spacer()

                // Sample warning badge
                if event.hasSampleWarning {
                    if event.hasParseWarning {
                        Image(systemName: "doc.badge.exclamationmark")
                            .foregroundStyle(.orange)
                            .help("Could not parse .als — external samples not included")
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help("\(event.totalMissingSamples) sample\(event.totalMissingSamples == 1 ? "" : "s") missing")
                    }
                }

                // Status indicator
                if event.overallStatus == .corrupt {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .help(event.destinations.compactMap(\.errorMessage).first ?? "Corrupt version")
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            // Destination icons row
            HStack(spacing: 6) {
                ForEach(event.destinations, id: \.destinationID) { version in
                    if let dest = destinations[version.destinationID] {
                        HStack(spacing: 3) {
                            Image(systemName: destinationIcon(for: dest.type))
                                .font(.caption)
                                .foregroundStyle(version.status == .corrupt ? .red : .blue)
                            Text(dest.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .help("\(dest.name): \(version.status.rawValue)")
                    }
                }

                // File count if available
                if let fileCount = event.destinations.first?.fileCount {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(fileCount) file\(fileCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func destinationIcon(for type: DestinationType) -> String {
        switch type {
        case .local:   return "externaldrive.fill"
        case .nas:     return "network"
        case .icloud:  return "icloud.fill"
        case .github:  return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - VersionDetailView

private struct VersionDetailView: View {
    let event: BackupEvent

    // Aggregate unique paths across all destination versions in this event
    private var collectedPaths: [String] {
        var seen = Set<String>()
        return event.destinations.flatMap {
            BackupVersion.decodePaths($0.collectedSamplePaths)
        }.filter { seen.insert($0).inserted }
    }

    private var missingPaths: [String] {
        var seen = Set<String>()
        return event.destinations.flatMap {
            BackupVersion.decodePaths($0.missingSamplePaths)
        }.filter { seen.insert($0).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header: timestamp + overall status
                HStack {
                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    Spacer()
                    if event.overallStatus == .corrupt {
                        Label("Corrupt", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                // Parse warning banner
                if event.hasParseWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text("Could not parse .als file — external samples were not included in this backup.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Missing samples section
                if !missingPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(missingPaths.count) Missing Sample\(missingPaths.count == 1 ? "" : "s")",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.subheadline.weight(.semibold))
                        ForEach(missingPaths, id: \.self) { path in
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                }

                // Collected samples section
                if !collectedPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(collectedPaths.count) Collected Sample\(collectedPaths.count == 1 ? "" : "s")",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.semibold))
                        ForEach(collectedPaths, id: \.self) { path in
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                }

                if collectedPaths.isEmpty && missingPaths.isEmpty && !event.hasParseWarning {
                    Text("No external samples were referenced in this backup.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Backup Details")
    }
}
